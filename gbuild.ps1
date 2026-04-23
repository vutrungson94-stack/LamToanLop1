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
$C_Header = "Magenta"
$C_Info   = "Cyan"
$C_Warn   = "Yellow"
$C_Err    = "Red"
$C_Succ   = "Green"
$C_Gray   = "DarkGray"

# ==================================================================================================
# [SECTION 2] HÀM BỔ TRỢ (HELPERS)
# ==================================================================================================

# 1. Hàm ghi log có định dạng
function Write-Log([string]$msg, [string]$color = "White") {
    $time = Get-Date -Format "HH:mm:ss"
    Write-Host "[$time] " -NoNewline -ForegroundColor $C_Gray
    Write-Host $msg -ForegroundColor $color
}

# 2. Hàm Resolve đường dẫn tuyệt đối (Xử lý khoảng trắng TRUNG SON)
function Get-SafePath([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    $full = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $path))
    return $full.TrimEnd('\')
}

# 3. Hàm lấy Short Path (8.3) để trị dứt điểm lỗi -2147450735 trên Windows
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

# 4. Tìm Android SDK (Fix lỗi XA5300)
function Get-AndroidSdkPath {
    Write-Log "🔍 Đang tìm Android SDK..." $C_Gray
    $list = @(
        (Join-Path $PSScriptRoot ".sdk\android-sdk"),
        $env:ANDROID_HOME,
        $env:ANDROID_SDK_ROOT,
        (Join-Path $env:LOCALAPPDATA "Android\Sdk")
    )
    foreach ($p in $list) {
        if ($p -and (Test-Path $p)) {
            $path = (Get-Item $p).FullName.TrimEnd('\')
            Write-Log "✅ Thấy Android SDK: $path" $C_Succ
            return $path
        }
    }
    Write-Log "⚠️ Không thấy Android SDK trên máy!" $C_Warn
    return $null
}

# 5. Phân giải Dotnet Exe (Ưu tiên Máy -> Local)
function Resolve-DotnetExe {
    # 1. Thử dùng lệnh hệ thống
    $sys = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($sys) {
        Write-Log "🚀 Sử dụng .NET SDK hệ thống." $C_Info
        return "dotnet"
    }

    # 2. Sử dụng SDK Local
    $localDir = Get-SafePath ".sdk"
    $localExe = Join-Path $localDir "dotnet.exe"
    if (-not $IsWindows) { $localExe = Join-Path $localDir "dotnet" }

    if (Test-Path $localExe) {
        # Dùng Short Path cho thư mục SDK để tránh lỗi Host Runtime do khoảng trắng
        $sdkRoot = if ($IsWindows) { Get-WindowsShortPath $localDir } else { $localDir }
        $exePath = Join-Path $sdkRoot (Split-Path $localExe -Leaf)

        Write-Log "📦 Sử dụng SDK Local: $sdkRoot" $C_Warn

        # Thiết lập biến môi trường cực kỳ chi tiết để fix lỗi -2147450735
        $env:DOTNET_ROOT = $sdkRoot
        ${env:DOTNET_ROOT(x86)} = $sdkRoot
        $env:DOTNET_MULTILEVEL_LOOKUP = "0"
        $env:DOTNET_MSBUILD_SDK_RESOLVER_CLI_DIR = $sdkRoot
        $env:DOTNET_SDK_WORKLOAD_MANIFEST_ROOT = Join-Path $sdkRoot "sdk-manifests"
        $env:DOTNET_SDK_WORKLOAD_PACK_ROOT = Join-Path $sdkRoot "packs"
        $env:PATH = "$sdkRoot$([IO.Path]::PathSeparator)$env:PATH"

        return $exePath
    }
    return $null
}

# 6. Đọc TFMs từ file csproj
function Get-CsprojTfms {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) {
        Write-Log "❌ Đường dẫn project không hợp lệ: '$Path'" $C_Err
        return @()
    }
    try {
        [xml]$xml = Get-Content -LiteralPath $Path -ErrorAction Stop
        $tfms = @()
        $nodes = $xml.SelectNodes("//Project/PropertyGroup[TargetFramework or TargetFrameworks]")
        foreach ($n in $nodes) {
            if ($n.TargetFramework) { $tfms += $n.TargetFramework }
            if ($n.TargetFrameworks) { $tfms += $n.TargetFrameworks }
        }
        $result = ($tfms -join ';').Split(';', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() }
        return $result | Sort-Object -Unique
    } catch {
        Write-Log "❌ Không thể đọc file project: $($_.Exception.Message)" $C_Err
        return @()
    }
}

# 7. Tìm project MAUI thông minh hơn
function Get-MauiCsproj {
    Write-Log "📂 Tìm kiếm file project..." $C_Gray
    # Tìm ưu tiên ở thư mục gốc trước, sau đó mới Recurse
    $files = Get-ChildItem . -Filter *.csproj -File
    if (-not $files) {
        $files = Get-ChildItem . -Recurse -Filter *.csproj -File | 
                 Where-Object { $_.FullName -notmatch '[\\/](obj|bin|node_modules|.sdk)[\\/]' }
    }
    
    foreach ($f in $files) {
        $content = Get-Content $f.FullName -Raw -EA SilentlyContinue
        if ($content -match '<UseMaui>\s*true\s*</UseMaui>') { return $f }
    }
    return $files | Select-Object -First 1
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

function ProcessBuildAndShow {
     param([string]$Project, [string]$Tfm, [string]$OutputSubDir, [string[]]$BuildArgs)

    # Chuyển mọi đường dẫn về Short Path để MSBuild không bị lỗi
    $rawOut = Join-Path $PSScriptRoot "publish-output\$OutputSubDir"
    if (!(Test-Path $rawOut)) { New-Item -ItemType Directory $rawOut | Out-Null }
    
    $shortProject = Get-ShortPath $Project
    $shortOut = Get-ShortPath $rawOut

    $dotnet = Resolve-DotnetExe
    if (-not $dotnet) { Write-Log "❌ Không thấy SDK!" $C_Err; exit 1 }

    $androidSdk = Get-AndroidSdkPath

    # Tham số build (Sử dụng Short Path cho tất cả)
    $params = @(
        "publish", $shortProject,
        "-f", $Tfm,
        "-c", "Release",
        "--output", $shortOut,
        "-p:UseMaui=true",
        "-p:SingleProject=true"
    )

    if ($androidSdk) { 
        $params += "-p:AndroidSdkDirectory=$androidSdk" 
    }
    if ($BuildArgs) { $params += $BuildArgs }

    Write-Log "🔥 Đang thực thi build..." $C_Info
    
    # Thực thi
    & $dotnet $params

    if ($LASTEXITCODE -ne 0) {
        Write-Log "❌ BUILD THẤT BẠI! Code: $LASTEXITCODE" $C_Err
        if ($LASTEXITCODE -eq -2147450735) {
            Write-Log "💡 LỖI: .NET Host vẫn không nhận diện được folder 'shared'. Hãy thử cài .NET SDK bản cài đặt (msi) lên máy." $C_Warn
        }
        exit 1
    }
    Write-Log "✅ THÀNH CÔNG!" $C_Succ
    if ($IsWindows) { Start-Process explorer.exe -ArgumentList $rawOut }
}

# ==================================================================================================
# [SECTION 4] GITHUB ACTIONS INTEGRATION
# ==================================================================================================

function Invoke-GitHubBuild([string]$PackageFormat) {
    Write-Log "☁ Đang kết nối GitHub Cloud..." $C_Info
    $gh = if (Get-Command gh -EA SilentlyContinue) { "gh" } else { Resolve-SafePath "gh.exe" }
    
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
║         🚀  MAUI ULTIMATE BUILD TOOL — VIP PRO MAX V3             ║
║      (Fixed: Space Paths, Runtime Host & Android SDK Errors)      ║
╚════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor $C_Info

# 1. Tìm Project
$csproj = Get-MauiCsproj
if (-not $csproj) { Write-Log "❌ Không tìm thấy file .csproj MAUI nào!" $C_Err; exit 1 }
$projPath = $csproj.FullName

# 2. Xử lý TFM (Hỗ trợ net10 fallback)
$rawTfms = Get-CsprojTfms -ProjPath $projPath
$tfms = @()

foreach ($t in $rawTfms) {
    if ($t -like 'net10.0*') { 
        $osPart = $t -replace '^net10\.0-',''
        $tfms += "net8.0-$osPart"
        Write-Log "🔄 Auto-fallback: $t -> net8.0-$osPart" $C_Gray
    } else { $tfms += $t }
}
$tfms = $tfms | Sort-Object -Unique

# Phân tách nền tảng
$androidTfm = $tfms | Where-Object { $_ -match 'android' } | Select-Object -First 1
$winTfm     = $tfms | Where-Object { $_ -match 'windows' } | Select-Object -First 1
$iosTfm     = $tfms | Where-Object { $_ -match 'ios' } | Select-Object -First 1

# 3. Xử lý Lựa chọn (Menu hoặc Param)
$choice = '0'

if ($GitHub -or $NonInteractive) {
    $choice = '6'
} else {
    Write-Host "`n🎯 CHỌN NỀN TẢNG MUỐN BUILD:" -ForegroundColor White
    Write-Host "  [1] Android APK  (Phát triển/Cài nhanh)" -ForegroundColor $C_Info
    Write-Host "  [2] Android AAB  (Phát hành Google Play - Có ký)" -ForegroundColor $C_Info
    
    if ($IsWindows) {
        Write-Host "  [5] Windows MSIX (Cài trên PC)" -ForegroundColor $C_Warn
    }
    if ($IsMacOS) {
        Write-Host "  [3] iOS IPA      (Cần Xcode/Mac)" -ForegroundColor $C_Warn
    }
    
    Write-Host "  [6] GitHub Build (Build trên Cloud GitHub)" -ForegroundColor $C_Succ
    Write-Host "  [0] Thoát" -ForegroundColor $C_Gray
    
    $userInput = Read-Host "`n👉 Lựa chọn của bạn"
    $choice = if ($userInput) { $userInput } else { '1' }
}

# 4. Thực thi Build
switch ($choice) {
    '0' { Write-Log "👋 Tạm biệt!" $C_Gray; exit 0 }
    
    '1' {
        if (-not $androidTfm) { Write-Log "❌ Project không hỗ trợ Android!" $C_Err; exit 1 }
        ProcessBuildAndShow -Project $projPath -Tfm $androidTfm -OutputSubDir "android-apk" -BuildArgs @("-p:AndroidPackageFormat=apk")
    }

    '2' {
        if (-not $androidTfm) { Write-Log "❌ Project không hỗ trợ Android!" $C_Err; exit 1 }
        $ks = Find-AndroidKeystore (Split-Path $projPath)
        $signArgs = @("-p:AndroidPackageFormat=aab")
        
        if ($ks) {
            $ks = Read-KeystoreInteractive $ks
            if ($ks) {
                Write-Log "🔏 Đang áp dụng chứng chỉ ký cho AAB..." $C_Succ
                $signArgs += "-p:AndroidSigningKeyStore=$($ks.Path)"
                $signArgs += "-p:AndroidSigningStorePass=$($ks.StorePass)"
                $signArgs += "-p:AndroidSigningKeyAlias=$($ks.Alias)"
                $signArgs += "-p:AndroidSigningKeyPass=$($ks.KeyPass)"
            }
        }
        ProcessBuildAndShow -Project $projPath -Tfm $androidTfm -OutputSubDir "android-aab" -BuildArgs $signArgs
    }

    '3' {
        if (-not $IsMacOS) { Write-ColorLog "❌ iOS build chỉ hỗ trợ trên macOS!" $C_Err; exit 1 }
        ProcessBuildAndShow -Project $projPath -Tfm $iosTfm -OutputSubDir "ios-ipa" -BuildArgs @("-p:ArchiveOnBuild=true", "-p:RuntimeIdentifier=ios-arm64")
    }

    '4' {
        if (-not $IsMacOS) { Write-ColorLog "❌ Mac build chỉ hỗ trợ trên macOS!" $C_Err; exit 1 }
        ProcessBuildAndShow -Project $projPath -Tfm $macTfm -OutputSubDir "mac-bundle" -BuildArgs @("-p:RuntimeIdentifier=maccatalyst-x64")
    }

    '5' {
        if (-not $IsWindows) { Write-Log "Chỉ chạy được trên Windows!" $C_Err; exit 1 }
        ProcessBuildAndShow -Project $projPath -Tfm $winTfm -OutputSubDir "windows" -BuildArgs @("-p:WindowsPackageType=MSIX")
    }

    '6' {
        $fmt = if ($Format) { $Format } else { "apk" }
        Invoke-GitHubBuild -PackageFormat $fmt
    }

    default { Write-Log "Lựa chọn không hợp lệ!" $C_Err }
}

$totalTime = (Get-Date) - $Global:StartTime
Write-Host "`n✨ HOÀN TẤT TRONG $($totalTime.Minutes)m $($totalTime.Seconds)s. CHÚC MẠNH KHỎE!" -ForegroundColor $C_Succ

# ==================================================================================================
# KẾT THÚC FILE (END OF SCRIPT)
# ==================================================================================================