#!/usr/bin/env pwsh
# ==================================================================================================
#  FILE NAME: gbuild.ps1
#  VERSION: 3.0.0 (ULTIMATE EDITION)
#  AUTHOR: AI ASSISTANT FOR MAUI DEVELOPERS
#  DESCRIPTION: Build MAUI locally with System/Local SDK support and GitHub Actions integration.
#  SPECIALTY: Fixed space-path issue (G:\TRUNG SON), Runtime Host Error, and Android SDK lookup.
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

# Bảng màu log chuyên nghiệp
$C_Header = "Magenta"; $C_Info = "Cyan"; $C_Warn = "Yellow"; $C_Err = "Red"; $C_Succ = "Green"; $C_Gray = "DarkGray"

# ==================================================================================================
# [SECTION 2] HÀM BỔ TRỢ (HELPERS)
# ==================================================================================================

# 1. Hàm ghi log có định dạng
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

# 3. Hàm lấy Short Path trên Windows (Giải quyết lỗi Runtime Host khi đường dẫn có khoảng trắng)
function Get-WindowsShortPath {
    param([string]$longPath)
    if (-not $IsWindows -or -not (Test-Path $longPath)) { return $longPath }
    try {
        $fso = New-Object -ComObject Scripting.FileSystemObject
        if (Test-Path $longPath -PathType Container) {
            return $fso.GetFolder($longPath).ShortPath
        } else {
            return $fso.GetFile($longPath).ShortPath
        }
    } catch { return $longPath }
}

# 4. Tìm Android SDK của Google (Hỗ trợ nhiều biến môi trường và đường dẫn mặc định)
function Get-AndroidSdkPath {
    Write-Log "🔍 Đang săn tìm Android SDK của Google..." $C_Gray
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

# Hàm tìm đường dẫn Java JDK (Local hoặc System)
function Get-JavaSdkPath {
    # 1. Ưu tiên kiểm tra folder .sdk/jdk trong project
    $localJdk = Join-Path $PSScriptRoot ".sdk\jdk"
    if (Test-Path (Join-Path $localJdk "bin\javac.exe")) {
        return Get-SafePath $localJdk
    }
    # 2. Nếu không có, thử lấy từ biến môi trường của máy
    if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME "bin\javac.exe"))) {
        return Get-SafePath $env:JAVA_HOME
    }
    return $null
}

# 5. Phân giải Dotnet Exe (Ưu tiên Máy -> Local thư mục .sdk)
function Resolve-DotnetExe {
    Write-Log "🔍 Đang kiểm tra .NET SDK..." $C_Gray

    # Ưu tiên 1: Kiểm tra SDK Máy (Đảm bảo máy có cài SDK, không chỉ là Runtime)
    $sysDotnet = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($sysDotnet) {
        $sdks = & $sysDotnet.Source --list-sdks 2>&1
        if ($LASTEXITCODE -eq 0 -and $sdks) {
            Write-Log "🚀 Sử dụng .NET SDK hệ thống." $C_Info
            return $sysDotnet.Source
        } else {
            Write-Log "⚠️ Phát hiện dotnet command nhưng không có SDK trên máy. Chuyển sang Local SDK..." $C_Warn
        }
    } else {
        Write-Log "⚠️ Không tìm thấy lệnh dotnet trên máy. Chuyển sang Local SDK..." $C_Warn
    }

    # Ưu tiên 2: SDK Local trong .sdk (theo cây thư mục hiện tại)
    $localDir = Join-Path $PSScriptRoot ".sdk"
    $localExe = Join-Path $localDir "dotnet.exe"
    if (-not $IsWindows) { $localExe = Join-Path $localDir "dotnet" }

    if (Test-Path $localExe) {
        $sdkRoot = Get-SafePath $localDir
        $exePath = Join-Path $sdkRoot (Split-Path $localExe -Leaf)
        
        Write-Log "📦 Kích hoạt SDK Local tại: $sdkRoot" $C_Warn

        # Thiết lập biến môi trường để Dotnet Host không bị lỗi đường dẫn
        $env:DOTNET_ROOT = $sdkRoot
        ${env:DOTNET_ROOT(x86)} = $sdkRoot
        $env:DOTNET_MULTILEVEL_LOOKUP = "0"
        $env:DOTNET_MSBUILD_SDK_RESOLVER_CLI_DIR = $sdkRoot
        $env:DOTNET_SDK_WORKLOAD_MANIFEST_ROOT = Join-Path $sdkRoot "sdk-manifests"
        $env:DOTNET_SDK_WORKLOAD_PACK_ROOT = Join-Path $sdkRoot "packs"
        
        # Đưa path SDK local lên đầu ưu tiên
        $env:PATH = "$sdkRoot$([IO.Path]::PathSeparator)$env:PATH"

        return $exePath
    }
    
    Write-Log "❌ Không tìm thấy .NET SDK trên hệ thống lẫn trong thư mục .sdk!" $C_Err
    return $null
}

# QUÉT THIẾT BỊ ĐANG KẾT NỐI VỚI ADB (Dành cho Android Debug/Run trực tiếp)
function Get-ConnectedDevices {
    $sdk = Get-AndroidSdkPath
    if (!$sdk) { return @() }
    $adb = Join-Path $sdk "platform-tools\adb.exe"
    if (!(Test-Path $adb)) { return @() }
    
    # Lấy danh sách thiết bị từ adb
    $adbOut = @(& $adb devices | Select-String -Pattern "\tdevice$")
    return $adbOut
}

# THỰC THI DEBUG (RUN) TRỰC TIẾP LÊN THIẾT BỊ (Sử dụng -t:Run thay vì publish)
function Invoke-DeviceDebug {
    param([string]$Project, [string]$Tfm)
    
    $devices = @(Get-ConnectedDevices)
    if ($devices.Count -eq 0) {
        Write-Log "❌ Không tìm thấy thiết bị Android nào đang kết nối (device)!" $C_Err
        Write-Log "👉 Hãy đảm bảo đã bật USB Debugging và 'adb devices' có phản hồi." $C_Warn
        return
    }

    # TỰ ĐỘNG CẤU HÌNH CHO MỘT SỐ THIẾT BỊ NHƯ XIAOMI (Tránh lỗi cài đặt qua USB)
    $sdk = Get-AndroidSdkPath
    $adb = if ($sdk) { Join-Path $sdk "platform-tools\adb.exe" } else { "adb" }

    Write-Log "🛠  Đang tối ưu cấu hình cài đặt cho Xiaomi..." $C_Gray
    # Tắt xác minh app qua USB (Tránh bảng hỏi của Google Play Protect)
    & $adb shell settings put global verifier_verify_adb_installs 0
    & $adb shell settings put global package_verifier_enable 0
    # ---------------------------------------

    Write-Host "`n📱 PHÁT HIỆN THIẾT BỊ: $($devices[0].ToString().Trim())" -ForegroundColor $C_Info
    $confirm = Read-Host "`n❓ Bạn có muốn bắt đầu gỡ lỗi trên thiết bị này không? (Y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') { return }

    $dotnet = Resolve-DotnetExe
    $androidSdk = Get-AndroidSdkPath
    $javaSdk = Get-JavaSdkPath

    Write-Log "🚀 Đang triển khai app lên thiết bị... (Vui lòng mở khóa màn hình)" $C_Succ
    
    # Lệnh chạy debug (Sử dụng -t:Run)
    & $dotnet build -t:Run -f $Tfm `
        "-p:AndroidSdkDirectory=$androidSdk" `
        "-p:JavaSdkDirectory=$javaSdk" `
        (Get-SafePath $Project)
}

# 6. Đọc TFMs từ file csproj
function Get-CsprojTfms {
    param([string]$projPath)
    if (-not (Test-Path $projPath)) { return @() }
    
    $content = Get-Content $projPath -Raw
    $tfms = @()

    # Quét tất cả các thẻ TargetFramework hoặc TargetFrameworks
    $tfmMatches = [regex]::Matches($content, '<TargetFrameworks?>([^<]+)</TargetFrameworks?>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    foreach ($m in $tfmMatches) {
        $val = $m.Groups[1].Value.Trim()
        $parts = $val.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)
        foreach ($p in $parts) { $tfms += $p.Trim() }
    }

    $uniqueTfms = $tfms | Sort-Object -Unique
    if ($uniqueTfms) {
        Write-Log "📱 Các nền tảng phát hiện: $($uniqueTfms -join ', ')" $C_Gray
    }
    return $uniqueTfms
}

# 7. Tìm project MAUI thông minh hơn
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

# 8. Quản lý Keystore (Android)
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

# 9. Giao diện nhập thông tin Keystore
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

# 10. Hiển thị thông tin tổng kết sau build
function Show-BuildSummary([string]$dir) {
    if (-not (Test-Path $dir)) { return }
    $files = Get-ChildItem $dir -File | Where-Object { $_.Extension -in '.apk','.aab','.msix','.ipa','.pkg' }
    if (-not $files) {
        Write-Log "⚠️ Build hoàn tất nhưng không thấy file output mong đợi trong $dir" $C_Warn
        return
    }
    Write-Host "`n🚀 --- TỔNG KẾT BUILD ---" -ForegroundColor $C_Succ
    Write-Host "📂 Thư mục: $dir" -ForegroundColor $C_Gray
    foreach ($f in $files) {
        $size = [math]::Round($f.Length / 1MB, 2)
        $type = if ($f.Name -match 'Signed|Release') { "💎 Release" } else { "📦 Debug/Unsigned" }
        Write-Host "  $type  -> $($f.Name) ($size MB)" -ForegroundColor White
    }
    if ($IsWindows) { Start-Process explorer.exe -ArgumentList $dir }
}

# ==================================================================================================
# [SECTION 3] TIẾN TRÌNH BUILD CHÍNH (THE CORE ENGINE)
# ==================================================================================================

# 11. Tự động tìm thiết bị + deploy APK (Ưu tiên máy thật)
function Invoke-AutoDeploy {
    param([string]$ApkPath, [string]$AppId)

    $sdk    = Get-AndroidSdkPath
    $adb    = if ($sdk) { Join-Path $sdk "platform-tools\adb.exe" } else { "adb" }

    if (-not (Test-Path $adb) -and $adb -ne "adb") {
        Write-Log "⚠️ Không tìm thấy adb.exe - Bỏ qua auto deploy." $C_Warn
        return
    }

    # ── BƯỚC 1: Lấy toàn bộ danh sách thiết bị đang kết nối ──────────────
    $rawList = @(& $adb devices 2>&1)
    $allDevices = @($rawList |
        Where-Object { $_ -match "\tdevice$" } |
        ForEach-Object { ($_ -split "\t")[0].Trim() })

    if ($allDevices.Count -eq 0) {
        Write-Log "⚠️ Không tìm thấy thiết bị nào - Bỏ qua auto deploy." $C_Warn
        Write-Log "👉 Cắm USB / Bật USB Debugging / adb connect <ip>:5555" $C_Info
        return
    }

    # ── BƯỚC 2: Phân loại thiết bị ────────────────────────────────────────
    # Máy thật: serial có dạng ABC123XY hoặc IP (WiFi ADB)
    # Máy ảo:   serial bắt đầu bằng "emulator-" hoặc "127.0.0.1:"
    $realDevices = @($allDevices | Where-Object {
        $_ -notmatch "^emulator-" -and $_ -notmatch "^127\.0\.0\."
    })
    $emulators = @($allDevices | Where-Object {
        $_ -match "^emulator-" -or $_ -match "^127\.0\.0\."
    })

    # Ưu tiên: Máy thật → Máy ảo
    $orderedDevices = @()
    if ($realDevices.Count -gt 0) { $orderedDevices += $realDevices }
    if ($emulators.Count -gt 0)   { $orderedDevices += $emulators }

    Write-Log "📱 Thiết bị phát hiện: $($allDevices.Count) (Thật: $($realDevices.Count), Ảo: $($emulators.Count))" $C_Info

    # ── BƯỚC 3: Chọn thiết bị ─────────────────────────────────────────────
    $targetDevice = $null

    if ($orderedDevices.Count -eq 1) {
        # Chỉ có 1 thiết bị → Chọn luôn
        $targetDevice = $orderedDevices[0]
        $label = if ($realDevices -contains $targetDevice) { "📱 Máy thật" } else { "🖥️  Máy ảo" }
        Write-Log "$label được chọn tự động: $targetDevice" $C_Succ
    } else {
        # Nhiều thiết bị → Hiển thị menu chọn
        Write-Host "`n📋 DANH SÁCH THIẾT BỊ:" -ForegroundColor $C_Info
        for ($i = 0; $i -lt $orderedDevices.Count; $i++) {
            $d = $orderedDevices[$i]
            # Lấy tên model thiết bị
            $model = & $adb -s $d shell getprop ro.product.model 2>&1
            $model = $model -replace "`r|`n", ""
            $label = if ($realDevices -contains $d) { "📱 Máy thật" } else { "🖥️  Máy ảo " }
            Write-Host "  [$($i+1)] $label | $d | $model" -ForegroundColor White
        }
        Write-Host "  [0] Bỏ qua deploy" -ForegroundColor $C_Gray

        $choice = Read-Host "`n⌨  Chọn thiết bị (Enter = tự động chọn thiết bị đầu tiên)"
        if ([string]::IsNullOrWhiteSpace($choice)) {
            $targetDevice = $orderedDevices[0]
        } elseif ($choice -eq "0") {
            Write-Log "⏭️  Bỏ qua deploy." $C_Gray
            return
        } else {
            $idx = [int]$choice - 1
            if ($idx -ge 0 -and $idx -lt $orderedDevices.Count) {
                $targetDevice = $orderedDevices[$idx]
            } else {
                Write-Log "❌ Lựa chọn không hợp lệ." $C_Err
                return
            }
        }
    }

    # ── BƯỚC 4: Lấy tên model thiết bị đã chọn ───────────────────────────
    $modelName = (& $adb -s $targetDevice shell getprop ro.product.model 2>&1) -replace "`r|`n", ""
    Write-Log "🎯 Deploy lên: $modelName ($targetDevice)" $C_Info

    # ── BƯỚC 5: Gỡ app cũ + xóa cache Dalvik ────────────────────────────
    Write-Log "🗑️  Gỡ app cũ ($AppId)..." $C_Warn
    & $adb -s $targetDevice uninstall $AppId 2>&1 | Out-Null

    Write-Log "🧹 Xóa Dalvik cache..." $C_Warn
    & $adb -s $targetDevice shell "run-as $AppId rm -rf /data/data/$AppId/cache" 2>&1 | Out-Null
    & $adb -s $targetDevice shell "rm -rf /data/dalvik-cache/*" 2>&1 | Out-Null

    # ── BƯỚC 6: Cài APK mới ──────────────────────────────────────────────
    Write-Log "📦 Đang cài APK..." $C_Info
    $installOut = & $adb -s $targetDevice install -r "`"$ApkPath`"" 2>&1

    if ($installOut -match "Success") {
        Write-Log "✅ Cài đặt thành công!" $C_Succ

        # ── BƯỚC 7: Tự động khởi động app ────────────────────────────────
        # Lấy MainActivity hash từ APK đang cài (không hardcode)
        $mainActivity = & $adb -s $targetDevice shell "pm dump $AppId" 2>&1 |
            Select-String "android.intent.action.MAIN" -Context 0,3 |
            ForEach-Object { $_.Context.PostContext } |
            Select-String "$AppId/" |
            ForEach-Object { ($_ -split "$AppId/")[1].Trim() -replace "\s.*", "" } |
            Select-Object -First 1

        if ($mainActivity) {
            Write-Log "🚀 Khởi động: $AppId/$mainActivity" $C_Info
            & $adb -s $targetDevice shell "am start -n $AppId/$mainActivity" 2>&1 | Out-Null
        } else {
            # Fallback: dùng monkey để launch app
            Write-Log "🚀 Khởi động app (fallback)..." $C_Info
            & $adb -s $targetDevice shell "monkey -p $AppId -c android.intent.category.LAUNCHER 1" 2>&1 | Out-Null
        }
    } else {
        Write-Log "❌ Cài đặt thất bại!" $C_Err
        Write-Log "$installOut" $C_Warn
    }
}

function ProcessBuildAndShow {
    param([string]$Project, [string]$Tfm, [string]$OutputSubDir, [string[]]$BuildArgs)

    # Làm sạch folder output
    $rawOut = Join-Path $PSScriptRoot "publish-output\$OutputSubDir"
    if (Test-Path $rawOut) { 
        Get-ChildItem $rawOut -Recurse | Remove-Item -Force -EA SilentlyContinue
        Remove-Item $rawOut -Recurse -Force -EA SilentlyContinue 
    }
    New-Item -ItemType Directory -Force -Path $rawOut | Out-Null
    
    # Chuyển mọi đường dẫn về Safe Path (Khử khoảng trắng)
    $safeProj = Get-SafePath $Project
    $safeOut  = Get-SafePath $rawOut

    $dotnet = Resolve-DotnetExe
    if (-not $dotnet) { Write-Log "❌ Không tìm thấy SDK .NET!" $C_Err; exit 1 }

    # Lấy đường dẫn các SDK quan trọng
    $androidSdk = Get-AndroidSdkPath
    $javaSdk    = Get-JavaSdkPath

    # Mảng tham số build chuẩn
    $params = @(
        "publish", $safeProj,
        "-f", $Tfm,
        "-c", "Release",
        "--output", $safeOut,
        "-p:UseMaui=true",
        "-p:SingleProject=true"
    )

    if ($androidSdk) { $params += "-p:AndroidSdkDirectory=$androidSdk" }
    if ($javaSdk)    { $params += "-p:JavaSdkDirectory=$javaSdk" }
    if ($BuildArgs)  { $params += $BuildArgs }

    Write-Host ("`n" + "┌" + ("─" * 58) + "┐") -ForegroundColor $C_Gray
    Write-Log " 🚀 ĐANG TIẾN HÀNH BUILD: $Tfm" $C_Info
    Write-Log " 📁 Output: $OutputSubDir" $C_Gray
    Write-Host ("└" + ("─" * 58) + "┘") -ForegroundColor $C_Gray

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    # Thực thi lệnh build (bỏ -v diag để tăng tốc)
    & $dotnet $params

    if ($LASTEXITCODE -ne 0) {
        Write-Log "❌ BUILD THẤT BẠI (Mã lỗi: $LASTEXITCODE)" $C_Err
        exit 1
    }

    $sw.Stop()
    Write-Log "✅ THÀNH CÔNG TRONG $($sw.Elapsed.TotalSeconds.ToString('F1')) GIÂY" $C_Succ

    # ── AUTO DEPLOY (chỉ với APK, không deploy AAB) ───────────────────────
    if ($Tfm -match "android" -and $OutputSubDir -eq "apk") {
        $apkFile = Get-ChildItem $rawOut -Filter "*Signed*.apk" -Recurse |
                   Select-Object -First 1
        if (-not $apkFile) {
            $apkFile = Get-ChildItem $rawOut -Filter "*.apk" -Recurse |
                       Select-Object -First 1
        }

        if ($apkFile) {
            # Lấy ApplicationId từ csproj
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
        # AAB hoặc platform khác → Mở folder
        if ($IsWindows) { Start-Process explorer.exe -ArgumentList $rawOut }
    }
}

# ==================================================================================================
# [SECTION 4] GITHUB ACTIONS INTEGRATION
# ==================================================================================================

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
# [SECTION 5] LUỒNG ĐIỀU KHIỂN CHÍNH (MAIN FLOW)
# ==================================================================================================

Write-Host @"
`n╔════════════════════════════════════════════════════════════════════╗
║         🚀  MAUI ULTIMATE BUILD TOOL — VIP PRO MAX V1              ║
║      (Fixed: Space Paths, Runtime Host & Android SDK Errors)       ║
╚════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor $C_Header

# 1. Tìm Project
$csproj = Get-MauiCsproj
if (-not $csproj) { Write-Log "❌ Không tìm thấy project MAUI nào trong thư mục này!" $C_Err; exit 1 }
$projPath = $csproj.FullName
Write-Log "📄 Project mục tiêu: $($csproj.Name)" $C_Info

# 2. Xử lý Nền tảng (TFM)
$tfms = @(Get-CsprojTfms -projPath $projPath)
if ($tfms.Count -eq 0) { Write-Log "❌ Không thể đọc danh sách TargetFrameworks!" $C_Err; exit 1 }

$androidTfm = $tfms | Where-Object { $_ -match 'android' } | Select-Object -First 1
$winTfm     = $tfms | Where-Object { $_ -match 'windows' } | Select-Object -First 1
$iosTfm     = $tfms | Where-Object { $_ -match 'ios' } | Select-Object -First 1
$macTfm     = $tfms | Where-Object { $_ -match 'maccatalyst' } | Select-Object -First 1

# 3. Menu Lựa chọn
$choice = '0'
if ($GitHub -or $NonInteractive) {
    $choice = '1'
} else {
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
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' } # Mặc định là debug nếu chỉ nhấn Enter
}

# 4. Thực thi Logic Build
switch ($choice) {
    '1' {
        if (!$androidTfm) { Write-Log "❌ Project này không hỗ trợ Android!" $C_Err; exit 1 }
        Invoke-DeviceDebug -Project $projPath -Tfm $androidTfm
    }
    '2' { 
        if (!$androidTfm) { Write-Log "❌ Project này không hỗ trợ Android!" $C_Err; exit 1 }
        ProcessBuildAndShow -Project $projPath -Tfm $androidTfm -OutputSubDir "apk" -BuildArgs @("-p:AndroidPackageFormat=apk") 
    }
    '3' {
        if (!$androidTfm) { Write-Log "❌ Project này không hỗ trợ Android!" $C_Err; exit 1 }
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
# ==================================================================================================
# KẾT THÚC FILE (END OF SCRIPT)
# ==================================================================================================