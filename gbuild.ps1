#!/usr/bin/env pwsh
# =======================================================================
#  gbuild.ps1  — Build MAUI locally + trigger GitHub Actions
#  Drop vào bất kỳ project MAUI nào, chạy được ngay.
#
#  Dùng lệnh:
#    pwsh ./gbuild.ps1                          # menu tương tác
#    pwsh ./gbuild.ps1 -GitHub                  # kích hoạt GH Actions + download
#    pwsh ./gbuild.ps1 -GitHub -Format aab      # GH Actions, chọn AAB
#    pwsh ./gbuild.ps1 -GitHub -NonInteractive  # dùng trong pipe/CI
# =======================================================================

# 1) Tham số ở đầu script (không CmdletBinding)
param(
    [switch]$GitHub,
    [ValidateSet('apk','aab')]
    [string]$Format,
    [switch]$NonInteractive
)

# 2) Không ghi đè OS biến. Dựa vào 2 đặc tính có sẵn của PowerShell:
#    - $IsWindows
#    - $IsMacOS
#    - $IsLinux
#
# 3) Chuẩn bị môi trường
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =======================================================================
# I. HÀM BỔ TRỢ (HELPERS)
# =======================================================================

# 1) Resolve dotnet exe
function Resolve-DotnetExe {
    $ext = if ($IsWindows) { ".exe" } else { "" }
    $localSdkDir = Join-Path $PSScriptRoot ".sdk"
    $localDotnet = Join-Path $localSdkDir "dotnet$ext"

    if (Test-Path $localDotnet) {
        $fullPath = (Get-Item $localDotnet).FullName
        $fullDir = (Get-Item $localSdkDir).FullName
        
        Write-Host "✅ Đang sử dụng SDK Local: $fullDir" -ForegroundColor Yellow

        # ÉP SDK CHỈ NHÌN VÀO THƯ MỤC LOCAL
        $env:DOTNET_ROOT = $fullDir
        $env:DOTNET_MULTILEVEL_LOOKUP = "0"
        $env:DOTNET_MSBUILD_SDK_RESOLVER_CLI_DIR = $fullDir
        
        # QUAN TRỌNG: Chỉ định nơi tìm MAUI Workload (Android/iOS)
        $env:DOTNET_SDK_WORKLOAD_MANIFEST_ROOT = Join-Path $fullDir "sdk-manifests"
        $env:DOTNET_SDK_WORKLOAD_PACK_ROOT = Join-Path $fullDir "packs"
        
        $env:PATH = "$fullDir$([IO.Path]::PathSeparator)$env:PATH"

        return $fullPath
    }

    $cmd = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($cmd) { return "dotnet" }
    return $null
}

function Get-AndroidSdkPath {
    # 1. Kiểm tra biến môi trường hệ thống (Dùng toán tử -and để tránh lỗi Null)
    if ($env:ANDROID_HOME -and (Test-Path $env:ANDROID_HOME)) { 
        return $env:ANDROID_HOME 
    }
    if ($env:ANDROID_SDK_ROOT -and (Test-Path $env:ANDROID_SDK_ROOT)) { 
        return $env:ANDROID_SDK_ROOT 
    }

    # 2. Kiểm tra folder mặc định của Android Studio (Thường nằm ở AppData)
    if ($env:LOCALAPPDATA) {
        $defaultPath = Join-Path $env:LOCALAPPDATA "Android\Sdk"
        if (Test-Path $defaultPath) { return $defaultPath }
    }

    # 3. Kiểm tra folder .sdk\android-sdk trong thư mục project
    $localPath = Join-Path $PSScriptRoot ".sdk\android-sdk"
    if (Test-Path $localPath) { return $localPath }

    return $null
}

# 2) Get-CsprojTfms: Robust parsing TargetFramework/TargetFrameworks
function Get-CsprojTfms {
    param([string]$ProjPath)
    [xml]$xml = Get-Content -LiteralPath $ProjPath

    $tfmList = @()
    $propertyGroups = $xml.SelectNodes("//Project/PropertyGroup[TargetFramework or TargetFrameworks]")

    foreach ($pg in $propertyGroups) {
        if ($pg.TargetFramework)  { $tfmList += $pg.TargetFramework }
        if ($pg.TargetFrameworks) { $tfmList += $pg.TargetFrameworks }
    }

    if (-not $tfmList -or $tfmList.Count -eq 0) { return @() }

    $joined = ($tfmList -join ';').Trim()
    if ([string]::IsNullOrWhiteSpace($joined)) { return @() }

    $tfms = $joined.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() }

    if ($tfms -is [string]) { return @($tfms) } else { return $tfms }
}

# 3) Show-OutputFiles
function Show-OutputFiles([string]$dir, [string[]]$extensions) {
    $exts = $extensions -join ','
    $files = Get-ChildItem $dir -File | Where-Object { $_.Extension.ToLower() -in $extensions.ToLower() }
    if (-not $files) {
        Write-Warning "⚠️ Không tìm thấy file output với extension '$exts' trong $dir"
        return
    }
    Write-Host "`n📂 Output Dir: $dir" -ForegroundColor Cyan
    foreach ($f in $files) {
        $label = if ($f.Name -match 'Signed|Release' -or $f.Name -match '\.pfx$') { '🔏 SIGNED' } else { '📦 unsigned' }
        Write-Host "  $label  $($f.Name)  [$([math]::Round($f.Length/1MB,2)) MB]" -ForegroundColor Green
    }
    # Mở thư mục trên OS tương ứng
    if ($IsWindows -and $files) {
        Start-Process explorer.exe -ArgumentList (Resolve-Path $dir)
    } elseif ($IsMacOS -and $files) {
        open (Resolve-Path $dir)
    } elseif ($IsLinux -and $files) {
        xdg-open (Resolve-Path $dir) 2>&1 | Out-Null
    }
}

# 4) Get-MauiCsproj: tìm project MAUI
function Get-MauiCsproj {
    $all = Get-ChildItem . -Recurse -Filter *.csproj -File |
        Where-Object { $_.FullName -notmatch '[\\/](obj|bin|packages|node_modules)[\\/]' -and $_.Name -notmatch '\.Tests\.' } |
        Sort-Object FullName
    foreach ($c in $all) {
        $raw = Get-Content $c.FullName -Raw -EA SilentlyContinue
        if ($raw -match '<UseMaui>\s*true\s*</UseMaui>') { return $c }
    }
    foreach ($c in $all) {
        $tfms = Get-CsprojTfms $c.FullName
        if ($tfms | Where-Object { $_ -match '^net\d+(\.\d+)?-(android|ios|maccatalyst|windows)' }) { return $c }
    }
    return ($all | Select-Object -First 1)
}

# 5) Android Keystore (optional)
function Find-AndroidKeystore([string]$projectDir) {
    $propsFile = Join-Path $projectDir 'signing.properties'
    if (Test-Path $propsFile) {
        $props = @{}
        Get-Content $propsFile | ForEach-Object {
            if ($_ -match '^\s*([^#=]+?)\s*=\s*(.+)$') { $props[$matches[1].Trim()] = $matches[2].Trim() }
        }
        $ksPath = $props['storeFile']
        if ($ksPath -and -not ([System.IO.Path]::IsPathRooted($ksPath))) {
            $ksPath = Join-Path $projectDir $ksPath
        }
        if ($ksPath -and (Test-Path $ksPath)) {
            return @{
                KeystorePath = $ksPath
                StorePass    = $props['storePassword']
                KeyAlias     = $props['keyAlias']
                KeyPass      = $props['keyPassword']
                Source       = 'signing.properties'
            }
        }
    }
    $ksFile = Get-ChildItem $projectDir -Recurse -File |
        Where-Object { $_.Extension -in '.keystore','.jks' -and $_.FullName -notmatch '[\\/](obj|bin)[/]' } |
        Select-Object -First 1
    if ($ksFile) {
        return @{
            KeystorePath = $ksFile.FullName
            StorePass    = $null
            KeyAlias     = $null
            KeyPass      = $null
            Source       = $ksFile.Name
        }
    }
    return $null
}
function Read-SigningInfo([hashtable]$ks) {
    Write-Host "`n🔑 Keystore: $($ks.KeystorePath)" -ForegroundColor Cyan
    Write-Host "   Nguồn   : $($ks.Source)" -ForegroundColor DarkGray
    if (-not $ks.StorePass) {
        $sp = Read-Host "🔑 Store password (Nhấn Enter để bỏ qua ký)"
        if ([string]::IsNullOrWhiteSpace($sp)) { return $null }
        $ks.StorePass = $sp
    }
    if (-not $ks.KeyAlias) {
        $ka = Read-Host "🔑 Key alias (mặc định: key0)"
        $ks.KeyAlias = if ([string]::IsNullOrWhiteSpace($ka)) { 'key0' } else { $ka }
    }
    if (-not $ks.KeyPass) {
        $kp = Read-Host "🔑 Key password (Nhấn Enter = giống store password)"
        $ks.KeyPass = if ([string]::IsNullOrWhiteSpace($kp)) { $ks.StorePass } else { $kp }
    }
    return $ks
}

# =======================================================================
# II. HÀM XỬ LÝ BUILD (ProcessBuildAndShow)
# =======================================================================
function ProcessBuildAndShow {
    param(
        [string]$Project,
        [string]$Tfm,
        [string]$OutputSubDir,
        [string[]]$BuildArgs
    )
    $publishDir = Join-Path $PSScriptRoot 'publish-output'
    $fullOutputFolder = Join-Path $publishDir $OutputSubDir

    if (Test-Path $fullOutputFolder) {
        Remove-Item $fullOutputFolder -Recurse -Force -EA SilentlyContinue
    }
    New-Item -ItemType Directory $fullOutputFolder | Out-Null

    $dotnetExe = Resolve-DotnetExe
    if (-not $dotnetExe) { exit 1 }

    # 1. Lấy đường dẫn Android SDK
    $androidSdk = Get-AndroidSdkPath
    
    # 2. Xử lý đường dẫn: Xóa dấu gạch chéo cuối cùng để tránh lỗi escape trong MSBuild
    if ($androidSdk) { $androidSdk = $androidSdk.TrimEnd('\') }
    $cleanProject = $Project.TrimEnd('\')
    $cleanOutput = $fullOutputFolder.TrimEnd('\')

    # 3. Tạo mảng tham số (Quan trọng: Dùng dấu nháy đơn bọc nháy kép cho thuộc tính có khoảng trắng)
    $dotnetArgs = @(
        "publish",
        "`"$cleanProject`"",
        "-f", $Tfm,
        "-c", "Release",
        "--output", "`"$cleanOutput`"",
        "-p:UseMaui=true",
        "-p:SingleProject=true"
    )

    # Nếu tìm thấy Android SDK, ép nó sử dụng bằng tham số -p
    if ($androidSdk) {
        Write-Host "🤖 Sử dụng Android SDK: $androidSdk" -ForegroundColor Gray
        $dotnetArgs += "-p:AndroidSdkDirectory=`"$androidSdk`""
    }

    if ($BuildArgs) { $dotnetArgs += $BuildArgs }

    Write-Host "`n🚀 Bắt đầu build..." -ForegroundColor Cyan
    
    # Thực thi bằng toán tử & và truyền mảng tham số
    # Đây là cách an toàn nhất để PowerShell không làm hỏng khoảng trắng
    & $dotnetExe $dotnetArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Host "`n❌ Build thất bại." -ForegroundColor Red
        if (-not $androidSdk) {
            Write-Host "👉 Lỗi: Không tìm thấy Android SDK. Hãy copy Android SDK vào thư mục .sdk\android-sdk" -ForegroundColor Yellow
        }
        exit 1
    }
    Write-Host "✅ Build thành công." -ForegroundColor Green
}

# =======================================================================
# III. GITHUB ACTIONS — (giữ tối giản cho độ ổn định)
# =======================================================================
function Invoke-GitHubBuild([string]$PackageFormat) {
    $gh = $null
    if ($IsWindows) {
        $ghExe = Join-Path $PSScriptRoot 'gh.exe'
        $gh = if (Test-Path $ghExe) { $ghExe } elseif (Get-Command gh -ErrorAction SilentlyContinue) { 'gh' } else { $null }
    } else {
        $gh = if (Get-Command gh -ErrorAction SilentlyContinue) { 'gh' } else { $null }
    }

    if (-not $gh) {
        Write-Host "❌ GitHub CLI (gh) chưa cài đặt hoặc không có trong PATH." -ForegroundColor Red
        exit 1
    }

    & $gh auth status *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Chưa đăng nhập GitHub CLI. Chạy: gh auth login --scopes workflow" -ForegroundColor Red
        exit 1
    }

    $currentBranch = if (Get-Command git -ErrorAction SilentlyContinue) { git branch --show-current 2>$null } else { 'main' }
    if (-not $currentBranch) { $currentBranch = 'main' }

    $activeWf = @()
    try { $activeWf = & $gh workflow list --json id,name,state --limit 100 | ConvertFrom-Json } catch { }
    if (-not $activeWf -or $activeWf.Count -eq 0) {
        Write-Host "❌ Không tìm thấy workflow hoạt động." -ForegroundColor Red; exit 1
    }

    $selectedWF = $activeWf | Where-Object { $_.name -match 'Build|MAUI|Android' } | Select-Object -First 1
    if (-not $selectedWF) { $selectedWF = $activeWf[0] }

    Write-Host "🚀 Kích hoạt workflow '$($selectedWF.name)' ..." -ForegroundColor Cyan
    & $gh workflow run $selectedWF.id --ref $currentBranch -f "package_format=$PackageFormat" 2>$null

    # Tải artifact nhanh nhất (simplified)
    $outDir = 'apk-output'
    if (Test-Path $outDir) { Remove-Item "$outDir\*" -Recurse -Force -EA SilentlyContinue } else { New-Item -ItemType Directory $outDir | Out-Null }
    & $gh run download --dir $outDir

    Write-Host "`n🎉 Hoàn tất GitHub Actions." -ForegroundColor Green
    Show-OutputFiles $outDir @('.apk','.aab')
}

# =======================================================================
# IV. MAIN FLOW
# =======================================================================

# 1) Tìm MAUI project
$csproj = Get-MauiCsproj
if (-not $csproj) {
    Write-Host "❌ Không tìm thấy file .csproj MAUI nào." -ForegroundColor Red
    exit 1
}
$projectDir = Split-Path $csproj.FullName
Write-Host "📄 Sử dụng project: $($csproj.Name)" -ForegroundColor Cyan

# 2) Đọc TFMs
$tfmsFromCsprojRaw = Get-CsprojTfms -ProjPath $csproj.FullName
$tfms = @()
if ($tfmsFromCsprojRaw) {
    foreach ($t in @($tfmsFromCsprojRaw)) {
        if (-not [string]::IsNullOrWhiteSpace($t)) { $tfms += $t.Trim() }
    }
}
$tfms = $tfms | Sort-Object -Unique

# 3) Fallback net10.0 nếu cần
$processedTFMs = @(); $hasNet10TFMs = $false
foreach ($t in $tfms) {
    if ($t -like 'net10.0*') {
        $hasNet10TFMs = $true
        $osPart = $t -replace '^net10\.0-',''
        $fallback = $tfms | Where-Object { $_ -match "^net\d+(\.\d+)?-$osPart$" } | Sort-Object { [version]($_.Split('-')[0].Replace('net','')) } -Descending | Select-Object -First 1
        if ($fallback) { $processedTFMs += $fallback } else { $processedTFMs += 'net8.0-android' }
    } else { $processedTFMs += $t }
}
$tfms = $processedTFMs | Sort-Object -Unique
if ($hasNet10TFMs -and $tfms.Count -eq 0) {
    Write-Host "❌ Lỗi: net10.0 detected nhưng không có fallback." -ForegroundColor Red; exit 1
}

# 4) Phân loại TFMs theo nền tảng
$androidTfmCandidates = $tfms | Where-Object { $_ -match '^net\d+(\.\d+)?-android$' }
$iosTfmCandidates     = $tfms | Where-Object { $_ -match '^net\d+(\.\d+)?-ios$' }
$macTfmCandidates     = $tfms | Where-Object { $_ -match '^net\d+(\.\d+)?-maccatalyst$' }
$winTfmCandidates     = $tfms | Where-Object { $_ -match '^net\d+(\.\d+)?-windows(\d+\.\d+\.\d+)?$' }

$androidTfm = $androidTfmCandidates | Sort-Object { [version]($_.Split('-')[0].Replace('net','')) } -Descending | Select-Object -First 1
$iosTfm     = $iosTfmCandidates     | Sort-Object { [version]($_.Split('-')[0].Replace('net','')) } -Descending | Select-Object -First 1
$macTfm     = $macTfmCandidates     | Sort-Object { [version]($_.Split('-')[0].Replace('net','')) } -Descending | Select-Object -First 1
$winTfm     = $winTfmCandidates     | Sort-Object { [version]($_.Split('-')[0].Replace('net','')) } -Descending | Select-Object -First 1

# 5) Menu/CI flow
$publishDir = Join-Path $PSScriptRoot 'publish-output'
$selectedOption = $null

if ($GitHub -or $NonInteractive) {
    $selectedOption = '6'
    $packageFormatForCI = $Format
    if (-not $packageFormatForCI) { $packageFormatForCI = 'apk' }
} else {
    # Simple interactive menu (không quá dài để tránh rối)
    Write-Host "`n╔═══════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host " 🔨  MAUI BUILD TOOL — VIP PRO           " -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════╝`n" -ForegroundColor Cyan
    Write-Host "  [0] Thoát"
    Write-Host "  [1] Android — APK  (local build)"
    Write-Host "  [2] Android — AAB  (local build)"
    if ($IsMacOS) {
        if ($iosTfm) { Write-Host "  [3] iOS            (macOS)" } else { Write-Host "  [3] iOS (không có TFM)"; }
        if ($macTfm) { Write-Host "  [4] Mac Catalyst   (macOS)" } else { Write-Host "  [4] Mac Catalyst (không có TFM)"; }
    }
    if ($IsWindows) {
        if ($winTfm) { Write-Host "  [5] Windows MSIX   (local)" } else { Write-Host "  [5] Windows MSIX (không có TFM)"; }
    }
    Write-Host "  [6] ☁  GitHub Actions — Trigger + Download"
    $choice = Read-Host "`n👉 Chọn tùy chọn (Enter = 0)"
    $selectedOption = if ([string]::IsNullOrWhiteSpace($choice)) { '0' } else { $choice }
  }

switch ($selectedOption) {
  '0' { Write-Host 'Đã thoát.' -ForegroundColor Gray; exit 0 }
  '1' {
      if (-not $androidTfm) { Write-Host "❌ Không thấy TFM Android." -ForegroundColor Red; exit 1 }
      ProcessBuildAndShow -Project $csproj.FullName -Tfm $androidTfm -OutputSubDir 'android-apk' -BuildArgs @("-p:AndroidPackageFormat=apk")
      Show-OutputFiles (Join-Path $publishDir 'android-apk') @('.apk')
      Write-Host "`n✅ Build Android APK hoàn tất." -ForegroundColor Green
  }
  '2' {
      if (-not $androidTfm) { Write-Host "❌ Không thấy TFM Android." -ForegroundColor Red; exit 1 }
      $buildArgs = @("-p:AndroidPackageFormat=aab")
      $ksInfo = Find-AndroidKeystore $projectDir
      if ($ksInfo) {
          if ($NonInteractive) {
              Write-Host "⚠️ NonInteractive: Không thể hỏi password Keystore." -ForegroundColor Yellow
          } else { $ksInfo = Read-SigningInfo $ksInfo }
      }
      if ($ksInfo -and $ksInfo.StorePass) {
          Write-Host "🔏 Ký package với Keystore..." -ForegroundColor Green
          $buildArgs += @(
              "-p:AndroidSigningKeyStore=$($ksInfo.KeystorePath)",
              "-p:AndroidSigningStorePass=$($ksInfo.StorePass)",
              "-p:AndroidSigningKeyAlias=$($ksInfo.KeyAlias)",
              "-p:AndroidSigningKeyPass=$($ksInfo.KeyPass)"
          )
      } else {
          Write-Host "⚠️ Không có thông tin Keystore hoặc bỏ qua ký." -ForegroundColor Yellow
      }
      ProcessBuildAndShow -Project $csproj.FullName -Tfm $androidTfm -OutputSubDir 'android-aab' -BuildArgs $buildArgs
      Show-OutputFiles (Join-Path $publishDir 'android-aab') @('.aab')
      Write-Host "`n✅ Build Android AAB hoàn tất." -ForegroundColor Green
  }
  '3' {
      if (-not $IsMacOS) { Write-Host "❌ Lỗi: iOS chỉ chạy được trên macOS." -ForegroundColor Red; exit 1 }
      if (-not $iosTfm) { Write-Host "❌ Không tìm thấy TFM iOS trong .csproj." -ForegroundColor Red; exit 1 }
      $buildArgs = @("-p:ArchiveOnBuild=true", "-p:RuntimeIdentifier=ios-arm64")
      ProcessBuildAndShow -Project $csproj.FullName -Tfm $iosTfm -OutputSubDir 'ios-ipa' -BuildArgs $buildArgs
      Show-OutputFiles (Join-Path $publishDir 'ios-ipa') @('.ipa', '.app')
      Write-Host "`n✅ Build iOS IPA hoàn tất." -ForegroundColor Green
  }
  '4' {
      if (-not $IsMacOS) { Write-Host "❌ Lỗi: Mac Catalyst chỉ chạy được trên macOS." -ForegroundColor Red; exit 1 }
      if (-not $macTfm) { Write-Host "❌ Không tìm thấy TFM Mac Catalyst trong .csproj." -ForegroundColor Red; exit 1 }
      $buildArgs = @("-p:RuntimeIdentifier=maccatalyst-x64")
      ProcessBuildAndShow -Project $csproj.FullName -Tfm $macTfm -OutputSubDir 'maccatalyst-bundle' -BuildArgs $buildArgs
      Show-OutputFiles (Join-Path $publishDir 'maccatalyst-bundle') @('.pkg', '.dmg', '.app')
      Write-Host "`n✅ Build Mac Catalyst Bundle hoàn tất." -ForegroundColor Green
  }
  '5' {
      if (-not $IsWindows) { Write-Host "❌ Windows MSIX chỉ chạy trên Windows." -ForegroundColor Red; exit 1 }
      if (-not $winTfm) { Write-Host "❌ Không thấy TFM Windows trong .csproj." -ForegroundColor Red; exit 1 }
      $buildArgs = @("-p:WindowsPackageType=MSIX", "-p:GenerateAppxPackageOnBuild=true")
      $pfxFile = Get-ChildItem $projectDir -Recurse -File -Filter *.pfx | Where-Object { $_.FullName -notmatch '[\\/](obj|bin)[\\/]' } | Select-Object -First 1
      $signed = $false
      if ($pfxFile) {
          if ($NonInteractive) {
              Write-Host "⚠️ NonInteractive: Không thể hỏi PFX." -ForegroundColor Yellow
          } else {
              $pfxPass = Read-Host "🔑 PFX password ($($pfxFile.Name)) - Enter để bỏ qua ký"
              if (-not [string]::IsNullOrWhiteSpace($pfxPass)) {
                  $buildArgs += @("-p:PackageCertificateKeyFile=$($pfxFile.FullName)", "-p:PackageCertificatePassword=$pfxPass")
                  $signed = $true
              }
          }
      }
      if (-not $signed) { Write-Host "⚠️ Không có PFX hoặc bỏ qua ký." -ForegroundColor Yellow }
      ProcessBuildAndShow -Project $csproj.FullName -Tfm $winTfm -OutputSubDir 'windows-msix' -BuildArgs $buildArgs
      Show-OutputFiles (Join-Path $publishDir 'windows-msix') @('.msix', '.msixbundle', '.appx')
      Write-Host "`n✅ Build Windows MSIX hoàn tất." -ForegroundColor Green
  }
  '6' {
      Write-Host "`n☁  GitHub Actions — Trigger + Download" -ForegroundColor Cyan
      $packageFormatForCI = $Format
      if (-not $GitHub -and -not $NonInteractive -and -not $PSBoundParameters.ContainsKey('Format')) {
          Write-Host "  [1] APK  [2] AAB" -ForegroundColor Cyan
          $p = Read-Host "👉 Định dạng cho GitHub Actions (Enter = APK)"
          $packageFormatForCI = if ($p -eq '2') { 'aab' } else { 'apk' }
      } elseif (-not $packageFormatForCI) {
          $packageFormatForCI = 'apk'
      }
      Invoke-GitHubBuild -PackageFormat $packageFormatForCI
      Write-Host "`n🎉 Quá trình GitHub Actions hoàn tất." -ForegroundColor Green
      exit 0
  }
  default {
      Write-Host "❌ Lựa chọn không hợp lệ: '$selectedOption'." -ForegroundColor Red
      exit 1
  }
}

# End of main flow
Write-Host "`nBbuild hoàn tất." -ForegroundColor Green