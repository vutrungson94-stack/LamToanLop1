#!/usr/bin/env pwsh
# ==================================================================================================
#  FILE NAME: gbuild.ps1
#  VERSION: 4.0.1 (FIXED: File Lock & Aggressive Clean)
#  DESCRIPTION: Build MAUI locally + Deploy + GitHub Actions.
#  FIX: Added Aggressive Clean to prevent XARLP7024 error.
# ==================================================================================================
# --------------------------------------------------------------------------------------------------
# [SECTION 0] KHAI BÁO THAM SỐ
# --------------------------------------------------------------------------------------------------
param(
    [switch]$GitHub,
    [ValidateSet('apk','aab')]
    [string]$Format,
    [switch]$NonInteractive
)

# --------------------------------------------------------------------------------------------------
# [SECTION 1] CẤU HÌNH MÔI TRƯỜNG & BIẾN TOÀN CỤC
# --------------------------------------------------------------------------------------------------
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Global:StartTime = Get-Date

# Bảng màu log
$C_Header = "Magenta"; $C_Info = "Cyan"; $C_Warn = "Yellow"; $C_Err = "Red"; $C_Succ = "Green"; $C_Gray = "DarkGray"

# ==================================================================================================
# [SECTION 2] HÀM BỔ TRỢ (HELPERS)
# ==================================================================================================
# 1. Hàm ghi log
function Write-Log([string]$msg, [string]$color = "White") {
    $time = Get-Date -Format "HH:mm:ss"
    Write-Host "[$time] " -NoNewline -ForegroundColor $C_Gray
    Write-Host $msg -ForegroundColor $color
}

# 2. Hàm Resolve đường dẫn tuyệt đối (Xử lý khoảng trắng)
function Get-SafePath {
    param([string]$path)
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path $path)) { return $path }
    if (-not $IsWindows) { return $path }
    try {
        $fso = New-Object -ComObject Scripting.FileSystemObject
        if (Test-Path $path -PathType Container) { return $fso.GetFolder($path).ShortPath }
        return $fso.GetFile($path).ShortPath
    } catch { return $path }
}

# ==================================================================================================
# [SECTION 2.1] KILL PROCESSES ĐANG GIỮ LOCK FILE — CHỐNG LỖI XARLP7024
# ==================================================================================================
function Invoke-KillBuildProcesses {
    param([string]$ProjectDir)
    
    Write-Log "🔪 Đang quét và kill process đang giữ lock file..." $C_Gray
    
    # Danh sách process cần kill
    $processNames = @('dotnet', 'msbuild', 'vbcscompiler', 'csc', 'VBCSCompiler', 'java')
    
    foreach ($procName in $processNames) {
        try {
            $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue |
                Where-Object {
                    # Kiểm tra an toàn — tránh lỗi property không tồn tại
                    try {
                        ($_.Modules.FileName -like "*$ProjectDir*" -or
                        $_.Path -like "*$ProjectDir*" -or
                        (Get-Item $_.Path -ErrorAction SilentlyContinue).DirectoryName -like "*$ProjectDir*")
                    } catch {
                        $false
                    }
                }
            
            foreach ($proc in $procs) {
                Write-Log "   🎯 Kill $procName (PID: $($proc.Id))..." $C_Warn
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Log "   ⚠️  Lỗi khi quét process $procName : $($_.Exception.Message)" $C_Warn
        }
    }
    
    # Chờ 800ms để hệ thống nhả file handle
    Start-Sleep -Milliseconds 800
}

# ==================================================================================================
# [SECTION 2.2] KIỂM TRA FILE BỊ KHÓA
# ==================================================================================================
function Test-FileLocked {
    param([string]$FilePath)
    
    try {
        # Thử mở file với quyền ReadWrite — nếu fail nghĩa là file đang bị lock
        $file = [System.IO.File]::Open($FilePath, 'Open', 'Read', 'ReadWrite')
        $file.Close()
        return $false  # File không bị lock
    } catch {
        return $true   # File đang bị lock
    }
}

# ==================================================================================================
# [SECTION 2.3] ĐỢI FILE ĐƯỢC RELEASE
# ==================================================================================================
function Wait-FileUnlocked {
    param([string]$FilePath, [int]$MaxWaitSeconds = 10)
    
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $MaxWaitSeconds) {
        if (-not (Test-FileLocked -FilePath $FilePath)) {
            return $true
        }
        Start-Sleep -Milliseconds 200
    }
    return $false  # Timeout
}

# ==================================================================================================
# [SECTION 2.4] AUTO-CLEAN BUILD ARTIFACTS — CHỐNG LOCK FILE & UNSATISFIEDLINKERROR
# ==================================================================================================
function Invoke-CleanBuildArtifacts {
    param([string]$ProjectDir)
    
    Write-Log "🧹 Đang dọn dẹp build artifacts cũ..." $C_Gray
    
    # ── BƯỚC 0: KILL PROCESS TRƯỚC KHI CLEAN ─────────────────────────────
    Invoke-KillBuildProcesses -ProjectDir $ProjectDir
    
    # ── BƯỚC 1: Xóa folder bin/obj/.vs với retry logic ───────────────────
    $foldersToClean = @(
        (Join-Path $ProjectDir "bin"),
        (Join-Path $ProjectDir "obj"),
        (Join-Path $ProjectDir ".vs")
    )
    
    foreach ($folder in $foldersToClean) {
        if (Test-Path $folder) {
            $retryCount = 0
            $maxRetries = 10  # Tăng lên 10 lần retry
            $deleted = $false
            
            while (-not $deleted -and $retryCount -lt $maxRetries) {
                try {
                    # Kiểm tra xem folder có file nào bị lock không
                    $files = Get-ChildItem $folder -Recurse -File -ErrorAction SilentlyContinue
                    $lockedFiles = @()
                    foreach ($f in $files) {
                        if (Test-FileLocked -FilePath $f.FullName) {
                            $lockedFiles += $f.FullName
                        }
                    }
                    
                    if ($lockedFiles.Count -gt 0) {
                        Write-Log "   ⏳ File đang bị khóa, chờ 1s..." $C_Gray
                        Start-Sleep -Seconds 1
                        $retryCount++
                        continue
                    }
                    
                    Remove-Item -Path $folder -Recurse -Force -ErrorAction Stop
                    $deleted = $true
                    Write-Log "   ✅ Đã xóa: $folder" $C_Gray
                } catch {
                    $retryCount++
                    if ($retryCount -lt $maxRetries) {
                        $delay = $retryCount * 500
                        Write-Log "   ⏳ File bị lock, chờ ${delay}ms rồi thử lại ($retryCount/$maxRetries)..." $C_Gray
                        Start-Sleep -Milliseconds $delay
                        
                        # Thử kill process lần nữa nếu vẫn fail ở lần 5
                        if ($retryCount -eq 5) {
                            Invoke-KillBuildProcesses -ProjectDir $ProjectDir
                        }
                    } else {
                        Write-Log "   ⚠️  Không xóa được sau $maxRetries lần: $folder" $C_Warn
                        Write-Log "      💡 Mẹo: Đóng VS Code, tắt antivirus, rồi chạy lại" $C_Info
                    }
                }
            }
        }
    }
    
    # ── BƯỚC 2: Clean Android intermediate cache sâu ─────────────────────
    $androidCachePaths = @(
        (Join-Path $env:LOCALAPPDATA "Xamarin\MonoAndroid"),
        (Join-Path $env:LOCALAPPDATA "Temp\Xamarin"),
        (Join-Path $env:LOCALAPPDATA "Temp\MonoAndroid")
    )
    
    foreach ($cachePath in $androidCachePaths) {
        if (Test-Path $cachePath) {
            try {
                Get-ChildItem $cachePath -Recurse -Include "*.stamp","*.zip","__environment__.txt","res.zip.*" -ErrorAction SilentlyContinue |
                    Remove-Item -Force -ErrorAction SilentlyContinue
                Write-Log "   ✅ Đã xóa Android cache files trong: $cachePath" $C_Gray
            } catch {
                Write-Log "   ⚠️  Không xóa được cache: $cachePath" $C_Warn
            }
        }
    }
    
    # ── BƯỚC 3: Clean sâu trong obj/Release/net10.0-android/ ─────────────
    $androidObj = Join-Path $ProjectDir "obj\Release\net10.0-android"
    if (Test-Path $androidObj) {
        try {
            Get-ChildItem $androidObj -Recurse -Include "*.so","*.dll","*.stamp","__environment__.txt","res.zip.*" -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
            Write-Log "   ✅ Đã xóa Android native cache trong obj/" $C_Gray
        } catch {
            Write-Log "   ⚠️  Không xóa được native cache: $($_.Exception.Message)" $C_Warn
        }
    }
    
    # ── BƯỚC 4: Đợi hệ thống giải phóng file handle ──────────────────────
    Start-Sleep -Milliseconds 1200
    Write-Log "✅ Dọn dẹp hoàn tất!" $C_Succ
}

# 3. Tìm Android SDK
function Get-AndroidSdkPath {
    Write-Log "🔍 Đang săn tìm Android SDK..." $C_Gray
    $searchList = @(
        (Join-Path $PSScriptRoot ".sdk\android-sdk"),
        $env:ANDROID_HOME,
        $env:ANDROID_SDK_ROOT,
        (Join-Path $env:LOCALAPPDATA "Android\Sdk"),
        "C:\Program Files (x86)\Android\android-sdk"
    )
    foreach ($p in $searchList) {
        if ($p -and (Test-Path $p)) {
            $found = (Get-Item $p).FullName.TrimEnd('\')
            Write-Log "✅ Đã thấy Android SDK: $found" $C_Succ
            return Get-SafePath $found
        }
    }
    return $null
}

# 4. Tìm Java JDK
function Get-JavaSdkPath {
    $localJdk = Join-Path $PSScriptRoot ".sdk\jdk"
    if (Test-Path (Join-Path $localJdk "bin\javac.exe")) { return Get-SafePath $localJdk }
    if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME "bin\javac.exe"))) { return Get-SafePath $env:JAVA_HOME }
    return $null
}

# 5. Phân giải Dotnet Exe (System > Local .sdk)
function Resolve-DotnetExe {
    Write-Log "🔍 Đang kiểm tra .NET SDK..." $C_Gray
    # Ưu tiên 1: System
    $sysDotnet = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($sysDotnet) {
        $sdks = & $sysDotnet.Source --list-sdks 2>&1
        if ($LASTEXITCODE -eq 0 -and $sdks) {
            Write-Log "🚀 Sử dụng .NET SDK hệ thống." $C_Info
            return $sysDotnet.Source
        }
    }
    # Ưu tiên 2: Local
    $localDir = Join-Path $PSScriptRoot ".sdk"
    $localExe = Join-Path $localDir "dotnet.exe"
    if (Test-Path $localExe) {
        $sdkRoot = Get-SafePath $localDir
        $exePath = Join-Path $sdkRoot (Split-Path $localExe -Leaf)
        Write-Log "📦 Kích hoạt SDK Local tại: $sdkRoot" $C_Warn
        $env:DOTNET_ROOT = $sdkRoot
        ${env:DOTNET_ROOT(x86)} = $sdkRoot
        $env:DOTNET_MULTILEVEL_LOOKUP = "0"
        $env:PATH = "$sdkRoot$([IO.Path]::PathSeparator)$env:PATH"
        return $exePath
    }
    Write-Log "❌ Không tìm thấy .NET SDK!" $C_Err
    return $null
}

# 6. Đọc TFMs
function Get-CsprojTfms {
    param([string]$projPath)
    if (-not (Test-Path $projPath)) { return @() }
    $content = Get-Content $projPath -Raw
    $tfms = @()
    $tfmMatches = [regex]::Matches($content, '<TargetFrameworks?>([^<]+)</TargetFrameworks?>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    foreach ($m in $tfmMatches) {
        $val = $m.Groups[1].Value.Trim()
        $parts = $val.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)
        foreach ($p in $parts) { $tfms += $p.Trim() }
    }
    return $tfms | Sort-Object -Unique
}

# 7. Tìm project MAUI
function Get-MauiCsproj {
    Write-Log "📂 Đang quét tìm file project MAUI..." $C_Gray
    $files = Get-ChildItem . -Recurse -Filter *.csproj -File |
        Where-Object { $_.FullName -notmatch '[\\/](obj|bin|node_modules|.sdk)[\\/]' }
    foreach ($f in $files) {
        $content = Get-Content $f.FullName -Raw -EA SilentlyContinue
        if ($content -match '<UseMaui>\s*true\s*</UseMaui>' -or $content -match 'net\d+(\.\d+)?-(android|ios|windows)') {
            return $f
        }
    }
    return $null
}

# 8. Quản lý Keystore
function Find-AndroidKeystore([string]$projectDir) {
    Write-Log "🔐 Đang tìm kiếm Keystore để ký..." $C_Gray
    $propsFile = Join-Path $projectDir 'signing.properties'
    if (Test-Path $propsFile) {
        $props = @{}
        Get-Content $propsFile | ForEach-Object { if ($_ -match '^\s*([^#=]+?)\s*=\s*(.+)$') { $props[$matches[1].Trim()] = $matches[2].Trim() } }
        $ksPath = $props['storeFile']
        if ($ksPath -and -not ([System.IO.Path]::IsPathRooted($ksPath))) { $ksPath = Join-Path $projectDir $ksPath }
        if ($ksPath -and (Test-Path $ksPath)) {
            Write-Log "📝 Đã nạp thông tin từ signing.properties" $C_Succ
            return @{ Path = $ksPath; StorePass = $props['storePassword']; Alias = $props['keyAlias']; KeyPass = $props['keyPassword']; Source = 'properties' }
        }
    }
    $ksFile = Get-ChildItem $projectDir -Recurse -Include *.keystore,*.jks | Where-Object { $_.FullName -notmatch '[\\/](obj|bin)[\\/]' } | Select-Object -First 1
    if ($ksFile) { return @{ Path = $ksFile.FullName; Source = 'file' } }
    return $null
}

function Read-KeystoreInteractive([hashtable]$ks) {
    Write-Host "`n--- THÔNG TIN KÝ ANDROID ---" -ForegroundColor $C_Info
    Write-Host "📍 File: $($ks.Path)" -ForegroundColor $C_Gray
    if (-not $ks.StorePass) {
        $sp = Read-Host "🔑 Nhập Store Password (Enter để bỏ qua ký)"
        if ([string]::IsNullOrWhiteSpace($sp)) { return $null }
        $ks.StorePass = $sp
    }
    if (-not $ks.Alias) {
        $ka = Read-Host "🔑 Nhập Key Alias (Mặc định: key0)"
        $ks.Alias = if ($ka) { $ka } else { 'key0' }
    }
    if (-not $ks.KeyPass) {
        $kp = Read-Host "🔑 Nhập Key Password (Để trống = giống Store Pass)"
        $ks.KeyPass = if ($kp) { $kp } else { $ks.StorePass }
    }
    return $ks
}

# ==================================================================================================
# [SECTION 2.5] AGGRESSIVE CLEAN & KILL (CHỐNG LỖI LOCK FILE)
# ==================================================================================================
function Invoke-AggressiveClean {
    param([string]$ProjectDir)
    
    Write-Log "🧹 Bắt đầu quy trình dọn dẹp và kill process..." $C_Gray
    
    # --- BƯỚC 1: KILL .NET HOST ---
    Write-Log "🔪 Đang quét process .NET Host đang giữ file..." $C_Gray
    try {
        $hostProcs = Get-Process -Name "dotnet" -ErrorAction SilentlyContinue | 
            Where-Object { $_.Path -like "*$ProjectDir*" -or $_.WorkingDirectory -like "*$ProjectDir*" }
        
        if ($hostProcs) {
            foreach ($proc in $hostProcs) {
                Write-Log "   🔴 Kill process .NET Host (PID: $($proc.Id))..." $C_Warn
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            }
            Start-Sleep -Milliseconds 800 # Chờ Windows nhả handle
        } else {
            Write-Log "   ℹ️ Không tìm thấy process .NET Host nào đang chạy." $C_Gray
        }
    } catch {
        Write-Log "   ⚠️ Lỗi khi kill process: $_" $C_Warn
    }

    # --- BƯỚC 2: XÓA THƯ MỤC RÁC ---
    $foldersToClean = @(
        (Join-Path $ProjectDir "bin"),
        (Join-Path $ProjectDir "obj"),
        (Join-Path $ProjectDir ".vs")
    )

    foreach ($folder in $foldersToClean) {
        if (Test-Path $folder) {
            $retry = 0
            $max = 3
            $deleted = $false
            while (-not $deleted -and $retry -lt $max) {
                try {
                    Remove-Item -Path $folder -Recurse -Force -ErrorAction Stop
                    $deleted = $true
                    Write-Log "   ✅ Đã xóa: $folder" $C_Gray
                } catch {
                    $retry++
                    Write-Log "   ⏳ File bị khóa, chờ 500ms rồi thử lại ($retry/$max)..." $C_Gray
                    Start-Sleep -Milliseconds 500
                }
            }
        }
    }

    # --- BƯỚC 3: DỌN CACHE XAMARIN ---
    $androidCache = Join-Path $env:LOCALAPPDATA "Xamarin\MonoAndroid"
    if (Test-Path $androidCache) {
        try {
            Get-ChildItem $androidCache -Recurse -Include "*.stamp","res.zip.*","__environment__.txt" -EA SilentlyContinue |
                Remove-Item -Force -EA SilentlyContinue
            Write-Log "   ✅ Đã dọn dẹp cache Android trung gian" $C_Gray
        } catch { }
    }
    
    Write-Log "✅ Dọn dẹp hoàn tất!" $C_Succ
}

# ==================================================================================================
# [SECTION 3] TIẾN TRÌNH BUILD & DEPLOY
# ==================================================================================================
function Invoke-DeviceDebug {
    param([string]$Project, [string]$Tfm)
    $sdk = Get-AndroidSdkPath
    if (!$sdk) { return }
    $adb = Join-Path $sdk "platform-tools\adb.exe"
    if (!(Test-Path $adb)) { return }

    $devices = @(& $adb devices | Select-String -Pattern "\tdevice$")
    if ($devices.Count -eq 0) {
        Write-Log "❌ Không tìm thấy thiết bị Android nào đang kết nối!" $C_Err
        return
    }

    # Tắt xác minh app cho Xiaomi
    Write-Log "🛠  Đang tối ưu cài đặt cho Xiaomi..." $C_Gray
    & $adb shell settings put global verifier_verify_adb_installs 0
    & $adb shell settings put global package_verifier_enable 0

    Write-Host "`n📱 PHÁT HIỆN THIẾT BỊ: $($devices[0].ToString().Trim())" -ForegroundColor $C_Info
    $confirm = Read-Host "`n❓ Bạn có muốn bắt đầu gỡ lỗi trên thiết bị này không? (Y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') { return }

    $dotnet = Resolve-DotnetExe
    $androidSdk = Get-AndroidSdkPath
    $javaSdk = Get-JavaSdkPath
    Write-Log "🚀 Đang triển khai app lên thiết bị..." $C_Succ
    
    & $dotnet build -t:Run -f $Tfm `
        "-p:AndroidSdkDirectory=$androidSdk" `
        "-p:JavaSdkDirectory=$javaSdk" `
        (Get-SafePath $Project)
}

function Invoke-AutoDeploy {
    param([string]$ApkPath, [string]$AppId)
    $sdk = Get-AndroidSdkPath
    $adb = if ($sdk) { Join-Path $sdk "platform-tools\adb.exe" } else { "adb" }
    if (-not (Test-Path $adb) -and $adb -ne "adb") {
        Write-Log "⚠️ Không tìm thấy adb.exe - Bỏ qua auto deploy." $C_Warn
        return
    }

    # ── BƯỚC 1: KIỂM TRA FILE APK ──────────────────────────────────────
    if (-not (Test-Path $ApkPath)) {
        Write-Log "❌ File APK không tồn tại: $ApkPath" $C_Err
        return
    }

    # ── BƯỚC 2: Lấy danh sách thiết bị ─────────────────────────────────
    $rawList = @(& $adb devices 2>&1)
    $allDevices = @($rawList | Where-Object { $_ -match "\tdevice$" } | ForEach-Object { ($_ -split "\t")[0].Trim() })
    if ($allDevices.Count -eq 0) {
        Write-Log "⚠️ Không tìm thấy thiết bị nào." $C_Warn
        return
    }

    # ── BƯỚC 3: Phân loại & Chọn thiết bị ──────────────────────────────
    $realDevices = @($allDevices | Where-Object { $_ -notmatch "^emulator-" -and $_ -notmatch "^127\.0\.0\." })
    $emulators   = @($allDevices | Where-Object { $_ -match "^emulator-" -or $_ -match "^127\.0\.0\." })
    $targetDevice = if ($realDevices.Count -gt 0) { $realDevices[0] } else { $emulators[0] }
    Write-Log "🎯 Deploy lên: $targetDevice" $C_Info

    # ── BƯỚC 4: Gỡ app cũ + Chờ hệ thống Android ───────────────────────
    Write-Log "🗑️  Gỡ app cũ ($AppId)..." $C_Warn
    & $adb -s $targetDevice uninstall $AppId 2>&1 | Out-Null
    Start-Sleep -Milliseconds 1200 # Chờ PackageManager giải phóng hoàn toàn

    # ── BƯỚC 5: Cài đặt với chế độ tolerant & chống lỗi Streamed ────────
    Write-Log "📦 Đang cài APK (chống lỗi Streamed & tự cấp quyền)..." $C_Info
    # -r: replace, -d: downgrade, -t: test, -g: grant permissions, --no-streaming: tránh corruption
    $installArgs = "-s", $targetDevice, "install", "-r", "-d", "-t", "-g", "--no-streaming", $ApkPath
    $installOut = @(& $adb @installArgs 2>&1)
    $fullLog = $installOut -join "`n"

    if ($fullLog -match "Success") {
        Write-Log "✅ Cài đặt thành công!" $C_Succ
        # ── BƯỚC 6: Tự động lấy MainActivity & Khởi động app ────────
        $mainActivity = $fullLog | Select-String "$AppId/" | Select-Object -First 1
        if ($mainActivity) {
            $act = ($mainActivity -split "$AppId/")[1].Trim() -replace "\s.*", ""
            if ($act) {
                Write-Log "🚀 Khởi động: $AppId/$act" $C_Info
                & $adb -s $targetDevice shell "am start -n $AppId/$act" 2>&1 | Out-Null
            }
        }
    } else {
        Write-Log "❌ Cài đặt thất bại! Chi tiết Android:" $C_Err
        # Log toàn bộ output để debug chính xác
        $installOut | ForEach-Object { Write-Log "   $_" $C_Warn }
        Write-Log "💡 Mẹo: Nếu báo 'UPDATE_INCOMPATIBLE', chạy thủ công: adb -s $targetDevice uninstall $AppId" $C_Info
    }
}

function ProcessBuildAndShow {
    param([string]$Project, [string]$Tfm, [string]$OutputSubDir, [string[]]$BuildArgs)
    
    # 🔥 [FIX] AGGRESSIVE CLEAN TRƯỚC KHI BUILD
    $projectDir = Split-Path $Project -Parent
    
    #kill process đang giữ lock file & dọn dẹp build artifacts cũ
    Invoke-KillBuildProcesses -ProjectDir $projectDir

    #dọn dẹp build artifacts cũ với retry logic chống lock file
    Invoke-CleanBuildArtifacts -ProjectDir $projectDir

    # Chờ thêm 1s để đảm bảo hệ thống đã nhả file handle
    Start-Sleep -Seconds 1
    
    Invoke-AggressiveClean -ProjectDir $projectDir
    
    # Làm sạch folder output
    $rawOut = Join-Path $PSScriptRoot "publish-output\$OutputSubDir"
    if (Test-Path $rawOut) { Remove-Item $rawOut -Recurse -Force -EA SilentlyContinue }
    New-Item -ItemType Directory -Force -Path $rawOut | Out-Null
    
    $safeProj = Get-SafePath $Project
    $safeOut  = Get-SafePath $rawOut
    $dotnet = Resolve-DotnetExe
    if (-not $dotnet) { Write-Log "❌ Không tìm thấy SDK .NET!" $C_Err; exit 1 }
    
    $androidSdk = Get-AndroidSdkPath
    $javaSdk    = Get-JavaSdkPath
    
    # Build params
    $params = @(
        "publish", $safeProj,
        "-f", $Tfm,
        "-c", "Release",
        "--output", $safeOut,
        "-p:UseMaui=true",
        "-p:SingleProject=true"
    )
    
    # Force native rebuild flags cho Android
    if ($Tfm -match "android") {
        $params += @(
            "-p:AndroidUseSharedRuntime=false",
            "-p:EmbedAssembliesIntoApk=true"
        )
        Write-Log "🔧 Đã kích hoạt native rebuild mode" $C_Info
    }
    
    if ($androidSdk) { $params += "-p:AndroidSdkDirectory=$androidSdk" }
    if ($javaSdk)    { $params += "-p:JavaSdkDirectory=$javaSdk" }
    if ($BuildArgs)  { $params += $BuildArgs }
    
    Write-Host ("`n" + "┌" + ("─" * 58) + "┐") -ForegroundColor $C_Gray
    Write-Log " 🚀 ĐANG TIẾN HÀNH BUILD: $Tfm" $C_Info
    Write-Host ("└" + ("─" * 58) + "┘") -ForegroundColor $C_Gray
    
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & $dotnet $params
    if ($LASTEXITCODE -ne 0) {
        Write-Log "❌ BUILD THẤT BẠI (Mã lỗi: $LASTEXITCODE)" $C_Err
        exit 1
    }
    $sw.Stop()
    Write-Log "✅ THÀNH CÔNG TRONG $($sw.Elapsed.TotalSeconds.ToString('F1')) GIÂY" $C_Succ
    
    # Auto Deploy
    if ($Tfm -match "android" -and $OutputSubDir -eq "apk") {
        $apkFile = Get-ChildItem $rawOut -Filter "*Signed*.apk" -Recurse | Select-Object -First 1
        if (-not $apkFile) { $apkFile = Get-ChildItem $rawOut -Filter "*.apk" -Recurse | Select-Object -First 1 }
        
        if ($apkFile) {
            $csprojContent = Get-Content $safeProj -Raw -EA SilentlyContinue
            $appIdMatch    = [regex]::Match($csprojContent, '<ApplicationId>([^<]+)</ApplicationId>')
            $appId         = if ($appIdMatch.Success) { $appIdMatch.Groups[1].Value.Trim() } else { "com.companyname.app" }
            
            Write-Host "`n" -NoNewline
            Invoke-AutoDeploy -ApkPath $apkFile.FullName -AppId $appId
        } else {
            Write-Log "⚠️ Không tìm thấy APK để deploy." $C_Warn
            if ($IsWindows) { Start-Process explorer.exe -ArgumentList $rawOut }
        }
    } else {
        if ($IsWindows) { Start-Process explorer.exe -ArgumentList $rawOut }
    }
}

function Invoke-GitHubBuild([string]$PackageFormat) {
    Write-Log "☁ Đang kết nối GitHub Cloud..." $C_Info
    $gh = if (Get-Command gh -EA SilentlyContinue) { "gh" } else { Get-SafePath "gh.exe" }
    if (-not (Test-Path $gh) -and $gh -ne "gh") {
        Write-Log "❌ Không tìm thấy gh.exe (GitHub CLI)!" $C_Err
        return
    }
    $branch = git branch --show-current 2>$null
    if (-not $branch) { $branch = "main" }
    Write-Log "🚀 Đang gửi yêu cầu build $PackageFormat lên nhánh $branch..." $C_Succ
    & $gh workflow run build.yml --ref $branch -f "package_format=$PackageFormat"
    Write-Log "✅ Đã trigger thành công. Vui lòng kiểm tra web GitHub." $C_Info
}

# ==================================================================================================
# [SECTION 4] MAIN FLOW
# ==================================================================================================
Write-Host @"
`n╔════════════════════════════════════════════════════════════════════╗
║         🚀  MAUI BUILD TOOL — VIP PRO MAX V1                       ║
║      (Fixed: File Lock, Space Paths & Auto Deploy)                 ║
╚════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor $C_Header

# Quản lý global.json
$dotnetExe = Resolve-DotnetExe
if ($dotnetExe) {
    $sdks = & $dotnetExe --list-sdks
    if ($sdks) {
        $latestSdk = ($sdks[-1] -split ' ')[0]
        $gJsonPath = Join-Path $PSScriptRoot "global.json"
        $needsUpdate = $true
        
        if (Test-Path $gJsonPath) {
            try {
                $json = Get-Content $gJsonPath -Raw | ConvertFrom-Json
                if ($json.sdk -and $json.sdk.version -eq $latestSdk) {
                    $needsUpdate = $false
                    Write-Host "✅ global.json đã tồn tại ($latestSdk)" -ForegroundColor Green
                } else {
                    Write-Host "⚠️ global.json version cũ -> Sẽ cập nhật." -ForegroundColor Yellow
                }
            } catch {}
        }
        
        if ($needsUpdate) {
            @{ sdk = @{ version = $latestSdk; rollForward = "latestMajor"; allowPrerelease = $true } } |
                ConvertTo-Json -Depth 3 | Out-File $gJsonPath -Encoding utf8 -Force
            Write-Host "🧾 Đã cập nhật global.json ($latestSdk)" -ForegroundColor Cyan
        }
    }
}

# 1. Tìm Project
$csproj = Get-MauiCsproj
if (-not $csproj) { Write-Log "❌ Không tìm thấy project MAUI!" $C_Err; exit 1 }
$projPath = $csproj.FullName
Write-Log "📄 Project mục tiêu: $($csproj.Name)" $C_Info

# 2. Xử lý TFM
$tfms = @(Get-CsprojTfms -projPath $projPath)
if ($tfms.Count -eq 0) { Write-Log "❌ Không đọc được TargetFrameworks!" $C_Err; exit 1 }

$androidTfm = $tfms | Where-Object { $_ -match 'android' } | Select-Object -First 1
$winTfm     = $tfms | Where-Object { $_ -match 'windows' } | Select-Object -First 1
$iosTfm     = $tfms | Where-Object { $_ -match 'ios' } | Select-Object -First 1
$macTfm     = $tfms | Where-Object { $_ -match 'maccatalyst' } | Select-Object -First 1

# 3. Menu
$choice = '0'
if ($GitHub -or $NonInteractive) { $choice = '1' }
else {
    Write-Host "`n👉 CHỌN NỀN TẢNG MUỐN XUẤT BẢN:" -ForegroundColor White
    if ($androidTfm) {
        Write-Host "  [1] Debug trên thiết bị Android" -ForegroundColor $C_Gray
        Write-Host "  [2] Android APK  (Cài đặt nhanh)" -ForegroundColor $C_Info
        Write-Host "  [3] Android AAB  (Google Play)" -ForegroundColor $C_Info
    }
    if ($iosTfm -and $IsMacOS) { Write-Host "  [4] iOS IPA" -ForegroundColor "Magenta" }
    if ($macTfm -and $IsMacOS) { Write-Host "  [5] Mac Catalyst" -ForegroundColor "Magenta" }
    if ($winTfm -and $IsWindows) { Write-Host "  [6] Windows MSIX" -ForegroundColor "DarkYellow" }
    Write-Host "  [7] GitHub Cloud Build" -ForegroundColor $C_Succ
    Write-Host "  [0] Thoát" -ForegroundColor $C_Gray
    $choice = Read-Host "`n⌨  Nhập số"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }
}

# 4. Thực thi
switch ($choice) {
    '1' {
        if (!$androidTfm) { Write-Log "❌ Project không hỗ trợ Android!" $C_Err; exit 1 }
        Invoke-DeviceDebug -Project $projPath -Tfm $androidTfm
    }
    '2' {
        if (!$androidTfm) { Write-Log "❌ Project không hỗ trợ Android!" $C_Err; exit 1 }
        ProcessBuildAndShow -Project $projPath -Tfm $androidTfm -OutputSubDir "apk" -BuildArgs @("-p:AndroidPackageFormat=apk")
    }
    '3' {
        if (!$androidTfm) { Write-Log "❌ Project không hỗ trợ Android!" $C_Err; exit 1 }
        $ks = Find-AndroidKeystore (Split-Path $projPath)
        $bArgs = @("-p:AndroidPackageFormat=aab")
        if ($ks) {
            $p = Read-Host "🔑 Nhập Keystore Password để ký AAB"
            if ($p) {
                $bArgs += "-p:AndroidSigningKeyStore=$($ks.Path)"
                $bArgs += "-p:AndroidSigningStorePass=$p"
                $bArgs += "-p:AndroidSigningKeyAlias=key0"
                $bArgs += "-p:AndroidSigningKeyPass=$p"
            }
        }
        ProcessBuildAndShow -Project $projPath -Tfm $androidTfm -OutputSubDir "aab" -BuildArgs $bArgs
    }
    '4' { ProcessBuildAndShow -Project $projPath -Tfm $iosTfm -OutputSubDir "ios" -BuildArgs @("-p:ArchiveOnBuild=true") }
    '5' { ProcessBuildAndShow -Project $projPath -Tfm $macTfm -OutputSubDir "mac" }
    '6' { ProcessBuildAndShow -Project $projPath -Tfm $winTfm -OutputSubDir "win" -BuildArgs @("-p:WindowsPackageType=MSIX") }
    '7' {
        $gh = if (Get-Command gh -EA SilentlyContinue) { "gh" } else { Get-SafePath (Join-Path $PSScriptRoot "gh.exe") }
        if ($gh -eq "gh" -or (Test-Path $gh)) { & $gh workflow run build.yml -f "package_format=apk" ; Write-Log "🚀 Đã gửi lên GitHub!" $C_Succ }
    }
    '0' { exit 0 }
}

Write-Log "🏁 HOÀN TẤT TRONG $([math]::Round(((Get-Date) - $Global:StartTime).TotalSeconds, 1))s." $C_Gray