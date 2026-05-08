#!/usr/bin/env pwsh
# ==================================================================================================
#  FILE NAME: gbuild.ps1
#  VERSION: 4.2.0 (PATH SAFETY: Unicode + Spaces Hardened)
#  DESCRIPTION: Build MAUI locally + Deploy + GitHub Actions.
#  CHANGES v4.2.0:
#    [FIX] UTF-8 console encoding toàn cục (chcp 65001 + OutputEncoding) để mọi tool
#          nhận đúng Unicode argument.
#    [FIX] Get-SafePath nâng cấp 3 tầng: kernel32 GetShortPathNameW → FSO → fallback
#          (không còn phụ thuộc FSO-only vốn thất bại khi 8.3 names bị tắt).
#    [FIX] Di chuyển Get-SafePath lên TRƯỚC Get-SmartDotnetPath để hàm đó dùng được.
#    [FIX] $env:PATH, DOTNET_ROOT, ANDROID_HOME, JAVA_HOME luôn nhận short/safe path.
#    [FIX] Start-Process explorer.exe quote đúng path có khoảng trắng.
#    [FIX] Invoke-DeviceDebug bỏ tham số Project bị truyền 2 lần (bug cũ).
#    [FIX] Keystore path trong signing args đi qua Get-SafePath.
#    [FIX] MSBuild -p: props cho Android/Java SDK dùng safe path.
#    [FIX] robocopy sử dụng & operator để PS tự quote path đúng cách.
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

# --------------------------------------------------------------------------------------------------
# [SECTION 1.5] UTF-8 & PATH SAFETY SETUP — PHẢI ĐẶT TRƯỚC MỌI HÀM KHÁC
# --------------------------------------------------------------------------------------------------

# [FIX v4.2.0] Thiết lập UTF-8 toàn cục để mọi external process (dotnet, adb, git...)
# nhận và xuất Unicode đúng. Thiếu bước này thì mọi trick path đều vô nghĩa.
if ($IsWindows) {
    try { & chcp 65001 | Out-Null } catch {}
}
$OutputEncoding           = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8

# [FIX v4.2.0] Get-SafePath — 3 tầng bảo vệ
#   Tầng 1: kernel32 GetShortPathNameW (P/Invoke trực tiếp, không qua COM)
#            → xử lý được cả spaces lẫn Unicode nếu 8.3 names còn bật
#   Tầng 2: FSO ShortPath (fallback COM legacy)
#   Tầng 3: Trả về path tuyệt đối chuẩn hóa, dựa vào UTF-8 encoding đã set
function Get-SafePath {
    param([string]$path)

    if ([string]::IsNullOrWhiteSpace($path)) { return $path }

    # Trên non-Windows (macOS/Linux): resolve thành absolute path là đủ
    if (-not $IsWindows) {
        try { return (Resolve-Path -LiteralPath $path -ErrorAction Stop).ProviderPath }
        catch { return $path }
    }

    # Path không tồn tại → trả về nguyên (có thể là path sẽ được tạo sau)
    if (-not (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue)) { return $path }

    # Normalize về absolute path (loại bỏ .., symlink v.v.)
    $absPath = try {
        (Get-Item -LiteralPath $path -ErrorAction Stop).FullName
    } catch { $path }
    if ([string]::IsNullOrWhiteSpace($absPath)) { return $path }

    # Nếu path đã an toàn (không có space, không có ký tự non-ASCII) → dùng luôn
    if ($absPath -notmatch '[\s\u0080-\uFFFF]') { return $absPath }

    # ── TẦNG 1: kernel32 GetShortPathNameW (P/Invoke) ─────────────────────────
    try {
        # Đăng ký type một lần duy nhất trong session (idempotent)
        if (-not ('GBuild.PathHelper' -as [type])) {
            Add-Type -Namespace 'GBuild' -Name 'PathHelper' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport(
    "kernel32.dll",
    CharSet     = System.Runtime.InteropServices.CharSet.Unicode,
    SetLastError= true)]
public static extern uint GetShortPathName(
    string lpszLongPath,
    System.Text.StringBuilder lpszShortPath,
    uint cchBuffer);
'@ -ErrorAction Stop
        }
        $sb  = [System.Text.StringBuilder]::new(32767)
        $len = [GBuild.PathHelper]::GetShortPathName($absPath, $sb, 32767)
        if ($len -gt 0 -and $len -lt 32767) {
            $shortPath = $sb.ToString(0, [int]$len)
            # Chỉ dùng nếu kết quả thực sự loại bỏ được ký tự nguy hiểm
            if ($shortPath -and ($shortPath -notmatch '[\s\u0080-\uFFFF]')) {
                return $shortPath
            }
        }
    } catch {}

    # ── TẦNG 2: FSO ShortPath (COM, legacy fallback) ──────────────────────────
    try {
        $fso       = New-Object -ComObject Scripting.FileSystemObject -ErrorAction Stop
        $shortPath = if (Test-Path -LiteralPath $absPath -PathType Container) {
            $fso.GetFolder($absPath).ShortPath
        } else {
            $fso.GetFile($absPath).ShortPath
        }
        if ($shortPath -and ($shortPath -notmatch '[\s\u0080-\uFFFF]')) {
            return $shortPath
        }
    } catch {}

    # ── TẦNG 3: Trả về absolute path chuẩn hóa ────────────────────────────────
    # Khi 8.3 names bị tắt hoàn toàn, không còn cách tạo short path.
    # Script đã set chcp 65001 + UTF-8 encoding ở trên nên external tools
    # nhận Unicode args qua W-API của PowerShell & operator.
    return $absPath
}

# ==================================================================================================
# [SECTION 2] HÀM BỔ TRỢ (HELPERS)
# ==================================================================================================

# ==================================================================================================
# HÀM TÌM KIẾM .NET SDK THÔNG MINH
# ==================================================================================================
function Get-SmartDotnetPath {
    Write-Host "🔍 Đang kiểm tra SDK .NET cài sẵn (dotnet trong PATH)..." -ForegroundColor Cyan

    # 1. Ưu tiên dotnet hệ thống có SDK
    if (Get-Command "dotnet" -ErrorAction SilentlyContinue) {
        $sdkCheck = & dotnet --list-sdks 2>&1
        if ($sdkCheck -and $sdkCheck -match '\d+\.\d+\.\d+') {
            Write-Host "✅ Sử dụng dotnet từ PATH (có SDK)." -ForegroundColor Green
            return (Get-Command dotnet).Source
        } else {
            Write-Host "⚠️ dotnet trong PATH không có SDK, bỏ qua." -ForegroundColor Yellow
        }
    }

    Write-Host "⚙️ Đang quét nhanh thư mục dự án..." -ForegroundColor Cyan

    # 2. Quét nhanh thư mục chứa script và thư mục hiện tại (độ sâu 4)
    $quickPaths = @($PSScriptRoot, (Get-Location).Path)
    foreach ($qPath in $quickPaths) {
        $sdks = @(Get-ChildItem -Path $qPath -Directory -Recurse -Depth 4 -Filter '.sdk' -ErrorAction SilentlyContinue)
        foreach ($sdkDir in $sdks) {
            $dotnetExe = Join-Path $sdkDir.FullName "dotnet.exe"
            if (Test-Path $dotnetExe) {
                $sdkCheck = & $dotnetExe --list-sdks 2>&1
                if ($sdkCheck -and $sdkCheck -match '\d+\.\d+\.\d+') {
                    Write-Host "✅ Đã tìm thấy SDK local gần dự án: $($sdkDir.FullName)" -ForegroundColor Green
                    # [FIX v4.2.0] Dùng Get-SafePath trước khi set vào env vars
                    $safeSdkPath = Get-SafePath $sdkDir.FullName
                    $env:DOTNET_ROOT                           = $safeSdkPath
                    $env:DOTNET_MSBUILD_SDK_RESOLVER_CLI_DIR  = $safeSdkPath
                    $env:DOTNET_MULTILEVEL_LOOKUP              = "0"
                    # [FIX v4.2.0] Thêm safe path vào PATH thay vì path gốc
                    $env:PATH = "$safeSdkPath;" + $env:PATH
                    return Get-SafePath $dotnetExe
                }
            }
        }
    }

    Write-Host "⚙️ Đang quét toàn bộ ổ đĩa (cả USB nếu có) tìm SDK local..." -ForegroundColor Cyan

    # 3. Lấy danh sách ổ cứng cố định và USB
    $allDrives = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2 or DriveType=3" | Select-Object -ExpandProperty DeviceID)
    if ($null -eq $allDrives -or $allDrives.Count -eq 0) {
        $allDrives = Get-PSDrive -PSProvider FileSystem | Where-Object { $null -ne $_.Used } | Select-Object -ExpandProperty Root
    }

    foreach ($drive in $allDrives) {
        $root = $drive + "\"
        Write-Host "   Đang quét ổ $root ..." -ForegroundColor DarkGray
        try {
            # Tìm tất cả thư mục .sdk không giới hạn độ sâu, dùng -Filter để tối ưu
            $sdks = @(Get-ChildItem -Path $root -Directory -Recurse -Filter '.sdk' -ErrorAction SilentlyContinue)
            foreach ($sdkDir in $sdks) {
                $dotnetExe = Join-Path $sdkDir.FullName "dotnet.exe"
                if (Test-Path $dotnetExe) {
                    $sdkCheck = & $dotnetExe --list-sdks 2>&1
                    if ($sdkCheck -and $sdkCheck -match '\d+\.\d+\.\d+') {
                        Write-Host "✅ Đã tìm thấy SDK local tại: $($sdkDir.FullName)" -ForegroundColor Green
                        # [FIX v4.2.0] Dùng Get-SafePath trước khi set vào env vars
                        $safeSdkPath = Get-SafePath $sdkDir.FullName
                        $env:DOTNET_ROOT                           = $safeSdkPath
                        $env:DOTNET_MSBUILD_SDK_RESOLVER_CLI_DIR  = $safeSdkPath
                        $env:DOTNET_MULTILEVEL_LOOKUP              = "0"
                        # [FIX v4.2.0] Thêm safe path vào PATH thay vì path gốc
                        $env:PATH = "$safeSdkPath;" + $env:PATH
                        return Get-SafePath $dotnetExe
                    }
                }
            }
        } catch {
            # ổ đĩa không truy cập được
        }
    }

    Write-Host "❌ Không tìm thấy bất kỳ SDK .NET nào." -ForegroundColor Red
    return $null
}

# Khởi tạo biến $dotnetCmd để sử dụng cho toàn bộ quá trình build phía sau
$global:dotnetCmd = Get-SmartDotnetPath
if (-not $global:dotnetCmd) {
    Write-Host "❌ Không có SDK .NET, không thể tiếp tục." -ForegroundColor Red
    exit 1
}

# 1. Hàm ghi log
function Write-Log([string]$msg, [string]$color = "White") {
    $time = Get-Date -Format "HH:mm:ss"
    Write-Host "[$time] " -NoNewline -ForegroundColor $C_Gray
    Write-Host $msg -ForegroundColor $color
}

# 2. Tìm Android SDK
function Get-AndroidSdkPath {
    Write-Log "🔍 Đang săn tìm Android SDK..." $C_Gray
    $searchList = @(
        (Join-Path $PSScriptRoot ".sdk\android-sdk"),
        (Join-Path $PSScriptRoot "..\.sdk\android-sdk"),
        (Join-Path (Get-Location) ".sdk\android-sdk"),
        $env:ANDROID_HOME,
        $env:ANDROID_SDK_ROOT,
        (Join-Path $env:LOCALAPPDATA "Android\Sdk"),
        "C:\Program Files (x86)\Android\android-sdk",
        "C:\Android\android-sdk"
    )
    foreach ($p in $searchList) {
        if ($p -and (Test-Path $p)) {
            $found = (Get-Item -LiteralPath $p).FullName.TrimEnd('\')
            Write-Log "✅ Đã thấy Android SDK: $found" $C_Succ
            $safePath = Get-SafePath $found
            # [FIX v4.2.0] Set ANDROID_HOME với safe path để child processes dùng được
            $env:ANDROID_HOME     = $safePath
            $env:ANDROID_SDK_ROOT = $safePath
            return $safePath
        }
    }

    # Nếu chưa tìm thấy, quét các ổ cứng cố định với độ sâu 3
    Write-Log "⚙️ Đang quét ổ cứng tìm Android SDK..." $C_Gray
    $fixedDrives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Select-Object -ExpandProperty DeviceID
    foreach ($drive in $fixedDrives) {
        $root = $drive + "\"
        $androidDirs = Get-ChildItem -Path $root -Directory -Recurse -Depth 4 -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -eq "android-sdk" -or (Test-Path (Join-Path $_.FullName "platform-tools\adb.exe")) }
        if ($androidDirs) {
            $found = $androidDirs[0].FullName
            Write-Log "✅ Đã thấy Android SDK: $found" $C_Succ
            $safePath = Get-SafePath $found
            $env:ANDROID_HOME     = $safePath
            $env:ANDROID_SDK_ROOT = $safePath
            return $safePath
        }
    }

    Write-Log "❌ Không tìm thấy Android SDK." $C_Err
    return $null
}

# 3. Tìm Java JDK
function Get-JavaSdkPath {
    # 1. Kiểm tra các vị trí ưu tiên (gần script, biến môi trường)
    $searchList = @(
        (Join-Path $PSScriptRoot ".sdk\jdk"),
        (Join-Path $PSScriptRoot "..\.sdk\jdk"),
        (Join-Path $PSScriptRoot "..\..\..\.sdk\jdk"),
        (Join-Path (Get-Location) ".sdk\jdk"),
        $env:JAVA_HOME
    )
    foreach ($p in $searchList) {
        if ($p -and (Test-Path (Join-Path $p "bin\javac.exe"))) {
            Write-Log "✅ Đã tìm thấy Java SDK: $p" $C_Succ
            $safePath = Get-SafePath $p
            # [FIX v4.2.0] Set JAVA_HOME với safe path
            $env:JAVA_HOME = $safePath
            return $safePath
        }
    }

    # 2. Quét các ổ đĩa cục bộ tìm thư mục chứa `bin\javac.exe` (độ sâu 5)
    Write-Log "⚙️ Đang quét ổ đĩa tìm Java SDK..." $C_Gray
    $fixedDrives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Select-Object -ExpandProperty DeviceID
    foreach ($drive in $fixedDrives) {
        $root = $drive + "\"
        # Tìm `javac.exe` với độ sâu 5 (đủ cho `.sdk/jdk/bin` hoặc `Common/.sdk/jdk/bin`)
        $javacCandidates = @(Get-ChildItem -Path $root -Filter "javac.exe" -Recurse -Depth 5 -ErrorAction SilentlyContinue)
        foreach ($javac in $javacCandidates) {
            $binDir = $javac.Directory
            $jdkDir = $binDir.Parent.FullName
            # Kiểm tra cấu trúc thư mục `jdk/bin/javac.exe` và có `java.exe`
            if ((Test-Path (Join-Path $jdkDir "bin\javac.exe")) -and (Test-Path (Join-Path $jdkDir "bin\java.exe"))) {
                Write-Log "✅ Đã tìm thấy Java SDK: $jdkDir" $C_Succ
                $safePath = Get-SafePath $jdkDir
                $env:JAVA_HOME = $safePath
                return $safePath
            }
        }
    }

    # 3. Không tìm thấy
    Write-Log "❌ Không tìm thấy Java JDK. Hãy đặt JDK vào thư mục '.sdk\jdk' gần script hoặc cài đặt JDK." $C_Err
    return $null
}

# 4. Đọc TFMs
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

# 5. Tìm project MAUI
function Get-MauiCsproj {
    Write-Log "📂 Đang quét tìm file project..." $C_Gray
    $files = Get-ChildItem . -Recurse -Filter *.csproj -File |
        Where-Object { $_.FullName -notmatch '[\\/](obj|bin|node_modules|.sdk)[\\/]' }
    
    foreach ($f in $files) {
        $content = Get-Content $f.FullName -Raw -EA SilentlyContinue
        # Chấp nhận cả project MAUI truyền thống và project Web SDK
        if ($content -match '<UseMaui>\s*true\s*</UseMaui>' -or 
            $content -match 'net\d+(\.\d+)?-(android|ios|windows)' -or
            $content -match 'Sdk="Microsoft\.NET\.Sdk\.Web"') {
            return $f
        }
    }
    return $null
}

# 6. Quản lý Keystore
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
# [SECTION 2.1] CLEAN & KILL OPTIMIZED — CHỐNG LOCK FILE & TỐI ƯU TỐC ĐỘ
# ==================================================================================================

# Hàm kiểm tra file lock
function Test-FileLocked {
    param([string]$FilePath)
    try {
        $file = [System.IO.File]::Open($FilePath, 'Open', 'Read', 'ReadWrite')
        $file.Close()
        return $false
    } catch { return $true }
}

# Hàm Kill Process an toàn
function Invoke-KillBuildProcesses {
    param(
        [string]$ProjectDir,
        [string]$OutputSubDir
    )
    # 1. Các tiến trình hệ thống hỗ trợ build (luôn cần tắt)
    $buildSystemProcs = @('dotnet', 'msbuild', 'vbcscompiler', 'csc')
    foreach ($proc in $buildSystemProcs) {
        Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue
    }

    # 2. Tự động xác định tên file .exe mục tiêu dựa trên cấu trúc thư mục publish
    $outputPath = Join-Path $PSScriptRoot "publish-output\$OutputSubDir"
    if (Test-Path $outputPath) {
        $targetExes = Get-ChildItem -Path $outputPath -Filter "*.exe" -Recurse
        
        foreach ($exe in $targetExes) {
            $exeName = $exe.BaseName
            
            Get-Process -Name $exeName -ErrorAction SilentlyContinue | Where-Object {
                try {
                    $_.Path -like "*publish-output*"
                } catch { $false }
            } | Stop-Process -Force -ErrorAction SilentlyContinue
            
            Write-Log "🎯 Đã giải phóng file khóa: $($exe.Name)" "Yellow"
        }
    }
    
    Start-Sleep -Milliseconds 800
}

# Hàm Clean tối ưu
function Invoke-SmartClean {
    param([string]$ProjectDir)
    Write-Log "🧹 Đang dọn dẹp build artifacts cũ..." $C_Gray

    # BƯỚC 1: Kill process mạnh mẽ hơn
    Invoke-KillBuildProcesses -ProjectDir $ProjectDir
    Start-Sleep -Milliseconds 800

    $foldersToClean = @(
        (Join-Path $ProjectDir "bin"),
        (Join-Path $ProjectDir "obj"),
        (Join-Path $ProjectDir ".vs")
    )

    foreach ($folder in $foldersToClean) {
        if (-not (Test-Path $folder)) { continue }

        $retryCount = 0
        $maxRetries = 4
        $deleted = $false

        while (-not $deleted -and $retryCount -lt $maxRetries) {
            try {
                $emptyDir = Join-Path $env:TEMP "empty_dir_$(Get-Random)"
                New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null

                # 🔧 FIX: Dùng Start-Process + quote path để tránh lỗi khoảng trắng/unicode
                $proc = Start-Process -FilePath "robocopy" -ArgumentList "`"$emptyDir`" `"$folder`" /MIR /NFL /NDL /NJH /NJS /nc /ns /np" -NoNewWindow -Wait -PassThru -RedirectStandardOutput $null -RedirectStandardError $null
                
                # Robocopy exit code 0 hoặc 1 là thành công
                if ($proc.ExitCode -le 1) {
                    Remove-Item -LiteralPath $folder -Force -ErrorAction Stop
                    $deleted = $true
                } else {
                    throw "Robocopy failed with exit code $($proc.ExitCode)"
                }

                Remove-Item -LiteralPath $emptyDir -Force -ErrorAction SilentlyContinue
                Write-Log "   ✅ Đã xóa: $folder" $C_Gray
            } catch {
                $retryCount++
                Write-Log "   ⚠️ Không xóa được $folder, đang thử lại ($retryCount/$maxRetries)..." $C_Warn
                Start-Sleep -Milliseconds 500
                
                # 🔧 FIX: Kill lại process nếu retry >= 2
                if ($retryCount -ge 2) {
                    Invoke-KillBuildProcesses -ProjectDir $ProjectDir
                    Start-Sleep -Milliseconds 600
                }
                
                # Fallback cuối cùng nếu robocopy vẫn lỗi
                if ($retryCount -eq $maxRetries) {
                    try {
                        Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction Stop
                        $deleted = $true
                        Write-Log "   ✅ Đã xóa (Fallback): $folder" $C_Gray
                    } catch {
                        Write-Log "   ❌ Không thể xóa $folder. Cần đóng IDE hoặc xóa thủ công." $C_Err
                    }
                }
            }
        }
    }

    # BƯỚC 3: Clean Android Cache (chọn lọc để tăng tốc)
    $androidCache = Join-Path $env:LOCALAPPDATA "Xamarin\MonoAndroid"
    if (Test-Path $androidCache) {
        try {
            Get-ChildItem $androidCache -Recurse -Include "*.stamp","res.zip.*","__environment__.txt" -EA SilentlyContinue |
            Remove-Item -Force -EA SilentlyContinue
        } catch {}
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
    Write-Log "🛠  Đang tối ưu cài đặt cho Xiaomi..." $C_Gray
    & $adb shell settings put global verifier_verify_adb_installs 0 2>&1 | Out-Null
    & $adb shell settings put global package_verifier_enable 0 2>&1 | Out-Null
    
    Write-Host "`n📱 PHÁT HIỆN THIẾT BỊ: $($devices[0].ToString().Trim())" -ForegroundColor $C_Info
    $confirm = Read-Host "`n❓ Bạn có muốn bắt đầu gỡ lỗi trên thiết bị này không? (Y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') { return }
    
    $androidSdk = Get-AndroidSdkPath
    $javaSdk    = Get-JavaSdkPath

    # [FIX v4.2.0] Lấy safe path cho project và các SDK
    $safeProject    = Get-SafePath $Project
    $safeAndroidSdk = Get-SafePath $androidSdk
    $safeJavaSdk    = Get-SafePath $javaSdk

    Write-Log "🚀 Đang triển khai app lên thiết bị..." $C_Succ

    # [FIX v4.2.0] Bỏ bug cũ: $Project bị truyền 2 lần (lần 2 là (Get-SafePath $Project))
    # Dùng array để PS tự quote đúng từng argument
    $debugParams = @(
        "build", $safeProject,
        "-t:Run",
        "-f", $Tfm,
        "-p:AndroidSdkDirectory=$safeAndroidSdk",
        "-p:JavaSdkDirectory=$safeJavaSdk"
    )
    & $global:dotnetCmd @debugParams
}

function Invoke-AutoDeploy {
    param(
        [string]$ApkPath, 
        [string]$AppId,
        [string]$AndroidSdkPath
    )

    $sdk = $AndroidSdkPath
    if (-not $sdk) { $sdk = Get-AndroidSdkPath }  # fallback nếu không truyền
    $adb = if ($sdk) { Join-Path $sdk "platform-tools\adb.exe" } else { "adb" }
    if (-not (Test-Path $adb) -and $adb -ne "adb") { return }
    
    if (-not (Test-Path $ApkPath)) { return }

    # [FIX v4.2.0] Đảm bảo APK path an toàn trước khi truyền cho adb
    $safeApkPath = Get-SafePath $ApkPath
    
    $rawList = @(& $adb devices 2>&1)
    $allDevices = @($rawList | Where-Object { $_ -match "\tdevice$" } | ForEach-Object { ($_ -split "\t")[0].Trim() })
    if ($allDevices.Count -eq 0) { return }
    
    $realDevices = @($allDevices | Where-Object { $_ -notmatch "^emulator-" -and $_ -notmatch "^127\.0\.0\." })
    $emulators   = @($allDevices | Where-Object { $_ -match "^emulator-" -or $_ -match "^127\.0\.0\." })
    $targetDevice = if ($realDevices.Count -gt 0) { $realDevices[0] } else { $emulators[0] }
    
    Write-Log "🗑️  Gỡ app cũ ($AppId)..." $C_Warn
    & $adb -s $targetDevice uninstall $AppId 2>&1 | Out-Null
    Start-Sleep -Milliseconds 800
    
    Write-Log "📦 Đang cài APK..." $C_Info
    # [FIX v4.2.0] Dùng $safeApkPath thay vì $ApkPath trực tiếp
    $installOut = & $adb -s $targetDevice install -r -d -t -g --no-streaming $safeApkPath 2>&1
    
    if ($installOut -match "Success") {
        Write-Log "✅ Cài đặt thành công!" $C_Succ
        $mainAct = $installOut | Select-String "$AppId/" | Select-Object -First 1
        if ($mainAct) {
            $act = ($mainAct -split "$AppId/")[1].Trim() -replace "\s.*", ""
            if ($act) {
                Write-Log "🚀 Khởi động: $AppId/$act" $C_Info
                & $adb -s $targetDevice shell "am start -n $AppId/$act" 2>&1 | Out-Null
            }
        }
    } else {
        Write-Log "❌ Cài đặt thất bại!" $C_Err
        Write-Log $installOut $C_Warn
    }
}

function ProcessBuildAndShow {
    param([string]$Project, [string]$Tfm, [string]$OutputSubDir, [string[]]$BuildArgs)

    $projectDir = Split-Path $Project -Parent
    Invoke-SmartClean -ProjectDir $projectDir
    Start-Sleep -Seconds 1

    # Làm sạch folder output
    $rawOut = Join-Path $PSScriptRoot "publish-output\$OutputSubDir"
    if (Test-Path $rawOut) { Remove-Item -LiteralPath $rawOut -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path $rawOut | Out-Null

    # Đảm bảo dùng đường dẫn tuyệt đối của dotnet.exe
    $dotnetExe = $global:dotnetCmd
    if (-not $dotnetExe) {
        Write-Log "❌ KHÔNG TÌM THẤY SDK .NET!" $C_Err
        exit 1
    }

    # [FIX v4.2.0] Lấy safe path cho output dir, project và dotnet
    $safeRawOut = Get-SafePath $rawOut
    $safeProject = Get-SafePath $Project

    Write-Log "🐞 Sử dụng dotnet: $dotnetExe" $C_Gray
    Write-Log "🐞 TFM: $Tfm | Output: $rawOut" $C_Gray

    # Xác định nền tảng trước để dùng cho kiểm tra
    $isAndroidPlatform = $Tfm -match 'android'
    $isApplePlatform   = $Tfm -match '(ios|maccatalyst)'
    $isWindowsPlatform = $Tfm -match 'windows'
    $isWebPlatform     = -not ($isAndroidPlatform -or $isApplePlatform -or $isWindowsPlatform)

    # Tìm Android SDK và Java SDK (trả về safe path)
    $androidSdk = Get-AndroidSdkPath
    $javaSdk    = Get-JavaSdkPath

    # Kiểm tra nếu build Android mà không có Android SDK thì dừng sớm
    if ($isAndroidPlatform -and (-not $androidSdk)) {
        Write-Log "❌ Không tìm thấy Android SDK. Hãy đặt SDK vào thư mục '.sdk\android-sdk' gần script hoặc cài Android SDK." $C_Err
        exit 1
    }

    if ($isAndroidPlatform -and (-not $javaSdk)) {
        Write-Log "❌ Không tìm thấy Java JDK. Hãy đặt JDK vào thư mục '.sdk\jdk' gần script hoặc cài đặt JDK." $C_Err
        exit 1
    }

    # [FIX v4.2.0] Dùng $safeProject và $safeRawOut trong params
    # PS & operator tự quote từng element của array — không cần ghép chuỗi thủ công
    $params = @(
        "publish", $safeProject,
        "-f", $Tfm,
        "-c", "Release",
        "--output", $safeRawOut
    )

    # Thêm tham số riêng cho từng nền tảng
    if ($isAndroidPlatform -or $isApplePlatform) {
        if ($isAndroidPlatform) {
            $params += @(
                "-p:AndroidUseSharedRuntime=false",
                "-p:EmbedAssembliesIntoApk=true"
            )
        }
    }
    elseif ($isWindowsPlatform) {
        $params += @("--self-contained", "true")
    }
    elseif ($isWebPlatform) {
        $params += @(
            "-r", "win-x64",
            "--self-contained", "true",
            "-p:PublishSingleFile=true",
            "-p:IncludeAllContentForSelfExtract=true"
        )
    }

    $csprojContent = Get-Content $Project -Raw -EA SilentlyContinue
    if ($csprojContent -match '<UseMaui>\s*true\s*</UseMaui>') {
        $params += @(
            "-p:UseMaui=true",
            "-p:SingleProject=true"
        )
    }
    $params += @("-p:BuildInParallel=true", "-m")
    $params += "-v", "normal"
    # $params += "-v", "detailed"

    # [FIX v4.2.0] androidSdk và javaSdk đã là safe path (từ Get-AndroidSdkPath / Get-JavaSdkPath)
    if ($androidSdk) { $params += "-p:AndroidSdkDirectory=$androidSdk" }
    if ($javaSdk)    { $params += "-p:JavaSdkDirectory=$javaSdk" }

    if ($BuildArgs)  { $params += $BuildArgs }

    Write-Host ("`n" + "┌" + ("─" * 58) + "┐") -ForegroundColor $C_Gray
    Write-Log " 🚀 ĐANG TIẾN HÀNH BUILD: $Tfm" $C_Info
    Write-Host ("└" + ("─" * 58) + "┘") -ForegroundColor $C_Gray

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $output = & $dotnetExe @params 2>&1 | ForEach-Object {
        $line = $_ 
        Write-Host "    $line" -ForegroundColor DarkGray
        $line
    }
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        Write-Log "❌ BUILD THẤT BẠI (Mã lỗi: $exitCode)" $C_Err
        Write-Host "--- Chi tiết lỗi từ dotnet ---" -ForegroundColor $C_Err
        Write-Host $output -ForegroundColor $C_Err
        Write-Host "-----------------------------" -ForegroundColor $C_Err
        exit 1
    }
    $sw.Stop()

    Write-Log "✅ THÀNH CÔNG TRONG $($sw.Elapsed.TotalSeconds.ToString('F1')) GIÂY" $C_Succ

    # Auto Deploy
    if ($isAndroidPlatform -and $OutputSubDir -eq "apk") {
        $apkFile = Get-ChildItem $rawOut -Filter "*Signed*.apk" -Recurse | Select-Object -First 1
        if (-not $apkFile) { $apkFile = Get-ChildItem $rawOut -Filter "*.apk" -Recurse | Select-Object -First 1 }
        if ($apkFile) {
            $appIdMatch = [regex]::Match($csprojContent, '<ApplicationId>([^<]+)</ApplicationId>')
            $appId      = if ($appIdMatch.Success) { $appIdMatch.Groups[1].Value.Trim() } else { "com.companyname.app" }
            Write-Host "`n" -NoNewline
            Invoke-AutoDeploy -ApkPath $apkFile.FullName -AppId $appId -AndroidSdkPath $androidSdk
        } else {
            Write-Log "⚠️ Không tìm thấy APK để deploy." $C_Warn
            # [FIX v4.2.0] Quote path để Explorer mở đúng khi có khoảng trắng/unicode
            if ($IsWindows) { Start-Process explorer.exe -ArgumentList "`"$rawOut`"" }
        }
    } else {
        # [FIX v4.2.0] Quote path để Explorer mở đúng khi có khoảng trắng/unicode
        if ($IsWindows) { Start-Process explorer.exe -ArgumentList "`"$rawOut`"" }
    }
}

function Invoke-GitHubBuild([string]$PackageFormat) {
    Write-Log "☁ Đang kết nối GitHub Cloud..." $C_Info
    $gh = if (Get-Command gh -EA SilentlyContinue) { "gh" } else { Get-SafePath "gh.exe" }
    if (-not (Test-Path $gh) -and $gh -ne "gh") { Write-Log "❌ Không tìm thấy gh.exe (GitHub CLI)!" $C_Err; return }
    
    $branch = git branch --show-current 2>$null
    if (-not $branch) { $branch = "main" }
    
    Write-Log "🚀 Đang gửi yêu cầu build $PackageFormat lên nhánh $branch..." $C_Succ
    & $gh workflow run build.yml --ref $branch -f "package_format=$PackageFormat"
    Write-Log "✅ Đã trigger thành công. Vui lòng kiểm tra web GitHub." $C_Info
}

# ==================================================================================================
# HÀM LẤY TARGET FRAMEWORK (TFM) CAO NHẤT
# ==================================================================================================
function Get-LatestInstalledTfm {
    Write-Host "🔍 Đang xác định Target Framework (TFM) cao nhất..." -ForegroundColor DarkGray
    try {
        $sdks = & $global:dotnetCmd --list-sdks
        if ($sdks) {
            $latest = $sdks[-1] 
            if ($latest -match "^(\d+\.\d+)") {
                $tfm = "net$($matches[1])"
                Write-Host "✅ TFM tự động chọn: $tfm" -ForegroundColor Green
                return $tfm
            }
        }
    } catch {
        Write-Host "⚠️ Cảnh báo: Không thể đọc danh sách SDK. Sử dụng mặc định." -ForegroundColor Yellow
    }
    return "net10.0" 
}

# ==================================================================================================
# [SECTION 4] MAIN FLOW
# ==================================================================================================

# Khởi tạo phiên bản TFM hiện tại của máy
$currentTfm = Get-LatestInstalledTfm
Write-Log "🔍 Đã nhận diện TFM mục tiêu: $currentTfm" "Cyan"


Write-Host @"
`n╔════════════════════════════════════════════════════════════════════╗
║         🚀  MAUI & WEB BUILD TOOL — VIP PRO MAX V2                 ║
║      (Optimized: No Duplicates, Fast Clean, Auto Deploy)           ║
╚════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor $C_Header

# 1. Quản lý global.json và SDK
if ($global:dotnetCmd) { 
    $sdks = & $global:dotnetCmd --list-sdks
    if ($sdks) {
        $latestSdk = ($sdks[-1] -split ' ')[0]
        $gJsonPath = Join-Path $PSScriptRoot "global.json"
        $needsUpdate = $true
        if (Test-Path $gJsonPath) {
            try {
                $json = Get-Content $gJsonPath -Raw | ConvertFrom-Json
                if ($json.sdk -and $json.sdk.version -eq $latestSdk) { $needsUpdate = $false }
            } catch {}
        }
        if ($needsUpdate) {
            @{ sdk = @{ version = $latestSdk; rollForward = "latestMajor"; allowPrerelease = $true } } |
                ConvertTo-Json -Depth 3 | Out-File $gJsonPath -Encoding utf8 -Force
            Write-Host "🧾 Đã cập nhật global.json ($latestSdk)" -ForegroundColor Cyan
        }
    }
}

# 2. Tìm Project (Tự động nhận diện MAUI hoặc Web)
$csproj = Get-MauiCsproj
if (-not $csproj) { Write-Log "❌ Không tìm thấy project hợp lệ!" $C_Err; exit 1 }
$projPath = $csproj.FullName
$csprojContent = Get-Content $projPath -Raw
$isWebProject = $csprojContent -match 'Sdk="Microsoft\.NET\.Sdk\.Web"'
Write-Log "📄 Project mục tiêu: $($csproj.Name)" $C_Info

# 3. Xử lý TFMs (Target Frameworks)
$tfms = @(Get-CsprojTfms -projPath $projPath)
$androidTfm = $tfms | Where-Object { $_ -match 'android' } | Select-Object -First 1
$winTfm     = $tfms | Where-Object { $_ -match 'windows' } | Select-Object -First 1
$iosTfm     = $tfms | Where-Object { $_ -match 'ios' } | Select-Object -First 1
$macTfm     = $tfms | Where-Object { $_ -match 'maccatalyst' } | Select-Object -First 1

# 4. Hiển thị Menu lựa chọn
$choice = '0'
if ($GitHub -or $NonInteractive) { $choice = '1' }
else {
    Write-Host "`n👉 CHỌN NỀN TẢNG MUỐN XUẤT BẢN:" -ForegroundColor White
    
    # Nhóm Android
    if ($androidTfm) {
        Write-Host "  [1] Debug trực tiếp trên thiết bị Android" -ForegroundColor $C_Gray
        Write-Host "  [2] Xuất bản Android APK (Cài đặt nhanh)" -ForegroundColor $C_Info
        Write-Host "  [3] Xuất bản Android AAB (Google Play)" -ForegroundColor $C_Info
    }
    
    # Nhóm Apple
    if ($iosTfm -and $IsMacOS) { Write-Host "  [4] Xuất bản iOS IPA" -ForegroundColor "Magenta" }
    if ($macTfm -and $IsMacOS) { Write-Host "  [5] Xuất bản Mac Catalyst" -ForegroundColor "Magenta" }
    
    # Nhóm Windows & Web
    if ($winTfm -or $isWebProject) {
        Write-Host "  [6] Xuất bản Windows MSIX (Đóng gói cài đặt)" -ForegroundColor "DarkYellow"
    }
    if ($isWebProject) {
        Write-Host "  [7] Xuất bản Web UI (Bản chạy trình duyệt)" -ForegroundColor "Cyan"
    }

    Write-Host "  [8] GitHub Cloud Build (Trình tự động hóa)" -ForegroundColor $C_Succ
    Write-Host "  [0] Thoát" -ForegroundColor $C_Gray
    
    $choice = Read-Host "`n⌨  Nhập số"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }
}

# 5. Thực thi theo lựa chọn
switch ($choice) {
    '1' {
        if (!$androidTfm) { Write-Log "❌ Project không hỗ trợ Android!" $C_Err; exit 1 }
        Invoke-DeviceDebug -Project $projPath -Tfm $androidTfm
    }
    '2' {
        ProcessBuildAndShow -Project $projPath -Tfm $androidTfm -OutputSubDir "apk" -BuildArgs @("-p:AndroidPackageFormat=apk")
    }
    '3' {
        $ks = Find-AndroidKeystore (Split-Path $projPath)
        $bArgs = @("-p:AndroidPackageFormat=aab")
        if ($ks) {
            $p = Read-Host "🔑 Nhập Keystore Password để ký AAB"
            if ($p) {
                # [FIX v4.2.0] Keystore path qua Get-SafePath để xử lý khoảng trắng/unicode
                $safeKsPath = Get-SafePath $ks.Path
                $bArgs += "-p:AndroidSigningKeyStore=$safeKsPath"
                $bArgs += "-p:AndroidSigningStorePass=$p"
                $bArgs += "-p:AndroidSigningKeyAlias=key0"
                $bArgs += "-p:AndroidSigningKeyPass=$p"
            }
        }
        ProcessBuildAndShow -Project $projPath -Tfm $androidTfm -OutputSubDir "aab" -BuildArgs $bArgs
    }
    '4' { ProcessBuildAndShow -Project $projPath -Tfm $iosTfm -OutputSubDir "ios" -BuildArgs @("-p:ArchiveOnBuild=true") }
    '5' { ProcessBuildAndShow -Project $projPath -Tfm $macTfm -OutputSubDir "mac" }
    '6' {
        $targetTfm = if ($winTfm) { $winTfm } else { "$currentTfm-windows10.0.19041.0" }
        ProcessBuildAndShow -Project $projPath -Tfm $targetTfm -OutputSubDir "win" -BuildArgs @(
            "-p:WindowsPackageType=None", 
            "-p:PublishSingleFile=false",
            "--self-contained", "true"
        )
    }
    '7' {
        if ($isWebProject) {
            ProcessBuildAndShow -Project $projPath -Tfm $currentTfm -OutputSubDir "web" -BuildArgs @(
                "-p:PublishSingleFile=false"
            )
            $exeName = [System.IO.Path]::GetFileNameWithoutExtension($projPath) + ".exe"
            $webOutDir = Join-Path $PSScriptRoot "publish-output\web"
            $exePath = Join-Path $webOutDir $exeName
            $url = "http://localhost:5000"

            if (Test-Path $exePath) {
                Write-Log "🚀 Đang khởi chạy ứng dụng ngầm tại $url..." "Green"
                # [FIX v4.2.0] FilePath và WorkingDirectory dùng safe path
                $safeExePath   = Get-SafePath $exePath
                $safeWebOutDir = Get-SafePath $webOutDir
                Start-Process -FilePath $safeExePath -ArgumentList "--urls=$url" -WorkingDirectory $safeWebOutDir -WindowStyle Hidden -PassThru | Out-Null
                Start-Sleep -Seconds 2
                Start-Process $url
                Write-Log "✅ Đã xong! App đang chạy độc lập. Script sẽ tự thoát." "Yellow"
                Write-Log "💡 Cách tắt app:" "Cyan"
                Write-Log "   1. Nhấn vào icon Tray trên thanh tác vụ Windows -> Exit" "Cyan"
                Write-Log "   2. Hoặc đóng toàn bộ cửa sổ ứng dụng/trình duyệt." "Cyan"
            } else {
                Write-Log "❌ Không tìm thấy file $exeName tại $webOutDir!" "Red"
            }
        }
    }
    '8' {
        $gh = if (Get-Command gh -EA SilentlyContinue) { "gh" } else { Get-SafePath (Join-Path $PSScriptRoot "gh.exe") }
        if ($gh -eq "gh" -or (Test-Path $gh)) { 
            & $gh workflow run build.yml -f "package_format=apk" 
            Write-Log "🚀 Đã gửi yêu cầu build lên GitHub!" $C_Succ
        }
    }
    '0' { exit 0 }
}

Write-Log "🏁 HOÀN TẤT TRONG $([math]::Round(((Get-Date) - $Global:StartTime).TotalSeconds, 1))s." $C_Gray