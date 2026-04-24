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

function ProcessBuildAndShow {
    param([string]$Project, [string]$Tfm, [string]$OutputSubDir, [string[]]$BuildArgs)

    # Làm sạch folder output
    $rawOut = Join-Path $PSScriptRoot "publish-output\$OutputSubDir"
    if (Test-Path $rawOut) { Remove-Item $rawOut -Recurse -Force -EA SilentlyContinue }
    New-Item -ItemType Directory $rawOut | Out-Null
    
    # Chuyển mọi đường dẫn về Safe Path (Khử khoảng trắng)
    $safeProj = Get-SafePath $Project
    $safeOut = Get-SafePath $rawOut

    $dotnet = Resolve-DotnetExe
    if (-not $dotnet) { Write-Log "❌ Không tìm thấy SDK .NET!" $C_Err; exit 1 }

    $androidSdk = Get-AndroidSdkPath

    # Mảng tham số build chuẩn (Xử lý khoảng trắng tuyệt đối)
    $params = @(
        "publish", $safeProj,
        "-f", $Tfm,
        "-c", "Release",
        "--output", $safeOut,
        "-p:UseMaui=true",
        "-p:SingleProject=true",
        "--no-self-contained"
    )

    if ($androidSdk) { $params += "-p:AndroidSdkDirectory=$androidSdk" }
    if ($BuildArgs) { $params += $BuildArgs }

    Write-Host ("`n" + ("=" * 60)) -ForegroundColor $C_Gray
    Write-Log "🚀 ĐANG TIẾN HÀNH BUILD: $Tfm" $C_Info
    Write-Host ("=" * 60) -ForegroundColor $C_Gray

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & $dotnet $params

    if ($LASTEXITCODE -ne 0) {
        Write-Log "❌ BUILD THẤT BẠI (Mã lỗi: $LASTEXITCODE)" $C_Err
        exit 1
    }

    $sw.Stop()
    Write-Log "✅ THÀNH CÔNG TRONG $($sw.Elapsed.TotalSeconds.ToString('F1')) GIÂY" $C_Succ
    
    # Mở folder kết quả
    if ($IsWindows) { Start-Process explorer.exe -ArgumentList $rawOut }
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
║         🚀  MAUI ULTIMATE BUILD TOOL — VIP PRO MAX V1             ║
║      (Fixed: Space Paths, Runtime Host & Android SDK Errors)      ║
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
    $choice = '6'
} else {
    Write-Host "`n👉 CHỌN NỀN TẢNG MUỐN XUẤT BẢN:" -ForegroundColor White
    if ($androidTfm) { 
        Write-Host "  [1] Android APK  (Cài đặt nhanh)" -ForegroundColor $C_Info
        Write-Host "  [2] Android AAB  (Google Play)" -ForegroundColor $C_Info
    }
    if ($iosTfm -and $IsMacOS) { Write-Host "  [3] iOS IPA" -ForegroundColor "Magenta" }
    if ($macTfm -and $IsMacOS) { Write-Host "  [4] Mac Catalyst" -ForegroundColor "Magenta" }
    if ($winTfm -and $IsWindows) { Write-Host "  [5] Windows MSIX" -ForegroundColor "DarkYellow" }
    
    Write-Host "  [6] GitHub Cloud Build" -ForegroundColor $C_Succ
    Write-Host "  [0] Thoát" -ForegroundColor $C_Gray
    
    $in = Read-Host "`n⌨  Nhập số"
    $choice = if ($in) { $in } else { '1' }
}

# 4. Thực thi Logic Build
switch ($choice) {
    '1' { 
        if (!$androidTfm) { Write-Log "❌ Project này không hỗ trợ Android!" $C_Err; exit 1 }
        ProcessBuildAndShow -Project $projPath -Tfm $androidTfm -OutputSubDir "apk" -BuildArgs @("-p:AndroidPackageFormat=apk") 
    }
    '2' {
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
    '3' { ProcessBuildAndShow -Project $projPath -Tfm $iosTfm -OutputSubDir "ios" -BuildArgs @("-p:ArchiveOnBuild=true") }
    '4' { ProcessBuildAndShow -Project $projPath -Tfm $macTfm -OutputSubDir "mac" }
    '5' { ProcessBuildAndShow -Project $projPath -Tfm $winTfm -OutputSubDir "win" -BuildArgs @("-p:WindowsPackageType=MSIX") }
    '6' {
        $gh = if (Get-Command gh -EA SilentlyContinue) { "gh" } else { Get-SafePath (Join-Path $PSScriptRoot "gh.exe") }
        if ($gh -eq "gh" -or (Test-Path $gh)) { & $gh workflow run build.yml -f "package_format=apk" ; Write-Log "🚀 Đã gửi lên GitHub!" $C_Succ }
    }
    '0' { exit 0 }
}

Write-Log "🏁 HOÀN TẤT TRONG $([math]::Round(((Get-Date) - $Global:StartTime).TotalSeconds, 1))s." $C_Gray
# ==================================================================================================
# KẾT THÚC FILE (END OF SCRIPT)
# ==================================================================================================