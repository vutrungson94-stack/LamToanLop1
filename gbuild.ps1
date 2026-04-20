#!/usr/bin/env pwsh
# ==============================================================================
#  gbuild.ps1  — Build MAUI cục bộ + kích hoạt GitHub Actions
#  Drop vào bất kỳ project MAUI nào, chạy được ngay.
#
#  Dùng lệnh:
#    .\gbuild.ps1                          # menu tương tác
#    .\gbuild.ps1 -GitHub                  # kích hoạt GH Actions + download
#    .\gbuild.ps1 -GitHub -Format aab      # GH Actions, chọn AAB
#    .\gbuild.ps1 -GitHub -NonInteractive  # dùng trong pipe/CI
# ==============================================================================

[CmdletBinding(DefaultParameterSetName = 'Menu')]
param(
    [Parameter(ParameterSetName = 'CI')] [switch]$GitHub,
    [Parameter(ParameterSetName = 'CI')] [ValidateSet('apk','aab')] [string]$Format,
    [Parameter(ParameterSetName = 'CI')] [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ===============================
# TÌM PROJECT
# ===============================

$csproj =
Get-ChildItem $PSScriptRoot -Filter *.csproj -Recurse |
Select-Object -First 1

if (-not $csproj) {

    Write-Host "❌ Không tìm thấy .csproj" -ForegroundColor Red
    exit 1
}

Write-Host "📄 Project: $($csproj.Name)"

# ===============================
# ĐỌC TARGET FRAMEWORK
# ===============================

[xml]$projXml =
Get-Content $csproj.FullName

$tfm =
$projXml.Project.PropertyGroup.TargetFramework

if (-not $tfm) {

    $tfm =
    $projXml.Project.PropertyGroup.TargetFrameworks
}

Write-Host "🎯 TargetFramework: $tfm"

# ===============================
# XÁC ĐỊNH SDK MAJOR
# ===============================

if ($tfm -match "net10") {

    $requiredMajor = "10."

}
elseif ($tfm -match "net9") {

    $requiredMajor = "9."

}
elseif ($tfm -match "net8") {

    $requiredMajor = "8."

}
else {

    Write-Host "❌ Không xác định được SDK từ $tfm"
    exit 1
}

Write-Host "🔎 Cần SDK major: $requiredMajor"

# ===============================
# TÌM SDK LOCAL
# ===============================

$sdkRoot =
Join-Path $PSScriptRoot ".sdk"

if (-not (Test-Path $sdkRoot)) {

    Write-Host "❌ Không có thư mục .sdk"
    exit 1
}

$sdkFolders =
Get-ChildItem $sdkRoot -Directory |
Where-Object {
    $_.Name.StartsWith($requiredMajor)
} |
Sort-Object Name -Descending

if (-not $sdkFolders) {

    Write-Host "❌ Không có SDK phù hợp: $requiredMajor"
    exit 1
}

$selectedSdk =
$sdkFolders[0]

Write-Host "✅ Dùng SDK: $($selectedSdk.Name)"

# ===============================
# SET DOTNET PATH
# ===============================

$dotnetRoot =
$selectedSdk.FullName

$dotnetExe =
Join-Path $dotnetRoot "dotnet.exe"

if (-not (Test-Path $dotnetExe)) {

    Write-Host "❌ Không tìm thấy dotnet.exe"
    exit 1
}

$env:DOTNET_ROOT =
$dotnetRoot

$env:PATH =
"$dotnetRoot;" +
"$dotnetRoot\tools;" +
$env:PATH

# --- ĐỘNG HÓA SDK (Tái sinh global.json) ---
$gJson = Join-Path $PSScriptRoot "global.json"

#Nếu đã có global.json → xóa
if (Test-Path $gJson) {
    Remove-Item $gJson -Force 
}

#Tạo global.json mới
$config = @{
    sdk = @{
        version = $selectedSdk.Name
        rollForward = "latestMajor"
        allowPrerelease = $true
    }
}

$config |
    ConvertTo-Json -Depth 3 |
    Out-File $gJson -Encoding utf8

Write-Host "✅ Đã tạo global.json với SDK $($selectedSdk.Name)" -ForegroundColor Green
# --------------------------------------------

# ── SSH key tuỳ chọn ────────────────────────────────────────────────────────
$sshKeyPath = Join-Path $PSScriptRoot 'ssh_id'
if (Test-Path $sshKeyPath) {
    $env:GIT_SSH_COMMAND = "ssh -i `"$sshKeyPath`" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"
}

# ════════════════════════════════════════════════════════════════════════════
# HELPERS — TFM
# ════════════════════════════════════════════════════════════════════════════
function Get-CsprojTfms {
    param([string]$ProjPath)
    [xml]$xml = Get-Content -LiteralPath $ProjPath
    $list = New-Object System.Collections.Generic.List[string]
    
    foreach ($pg in $xml.Project.PropertyGroup) {
        # Dùng câu lệnh if thay vì gán dấu phẩy để tránh tạo mảng lỗi
        if ($pg.TargetFramework) { [void]$list.Add($pg.TargetFramework.Trim()) }
        if ($pg.TargetFrameworks) { 
            foreach($t in ($pg.TargetFrameworks -split ';')) { [void]$list.Add($t.Trim()) }
        }
    }
    return ,($list | Select-Object -Unique)
}

function Select-Tfm {
    param(
        [Parameter(Mandatory=$true)] [string[]]$tfms,
        [Parameter(Mandatory=$true)] [string]$pattern
    )
    foreach ($t in $tfms) {
        if ($t -match $pattern) { return $t }
    }
    return $null
}

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
        if ($tfms | Where-Object { $_ -match 'android|ios|maccatalyst|windows' }) { return $c }
    }
    return ($all | Select-Object -First 1)
}

# ════════════════════════════════════════════════════════════════════════════
# HELPER — Phát hiện keystore Android cục bộ
# ════════════════════════════════════════════════════════════════════════════
function Find-AndroidKeystore([string]$searchRoot) {
    # Ưu tiên signing.properties cạnh .csproj
    $propsFile = Join-Path $searchRoot 'signing.properties'
    if (Test-Path $propsFile) {
        $props = @{}
        Get-Content $propsFile | ForEach-Object {
            if ($_ -match '^\s*([^#=]+?)\s*=\s*(.+)$') { $props[$matches[1].Trim()] = $matches[2].Trim() }
        }
        $ksPath = $props['storeFile']
        if ($ksPath -and -not [IO.Path]::IsPathRooted($ksPath)) {
            $ksPath = Join-Path $searchRoot $ksPath
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

    # Tìm .keystore / .jks trong project (ngoài bin/obj)
    $ksFile = Get-ChildItem $searchRoot -Recurse -File |
        Where-Object { $_.Extension -in '.keystore','.jks' -and $_.FullName -notmatch '[\\/](obj|bin)[\\/]' } |
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
        $sp = Read-Host "🔑 Store password (Enter để bỏ qua ký)"
        if ([string]::IsNullOrWhiteSpace($sp)) { return $null }
        $ks.StorePass = $sp
    }
    if (-not $ks.KeyAlias) {
        $ka = Read-Host "🔑 Key alias"
        $ks.KeyAlias = if ([string]::IsNullOrWhiteSpace($ka)) { 'key0' } else { $ka }
    }
    if (-not $ks.KeyPass) {
        $kp = Read-Host "🔑 Key password (Enter = giống store password)"
        $ks.KeyPass = if ([string]::IsNullOrWhiteSpace($kp)) { $ks.StorePass } else { $kp }
    }
    return $ks
}

# ════════════════════════════════════════════════════════════════════════════
# HELPER — Build cục bộ
# ════════════════════════════════════════════════════════════════════════════
function Invoke-LocalBuild {
    param(
        [string]   $CsprojPath,
        [string]   $Tfm,
        [string]   $OutputDir,
        [string[]] $ExtraArgs = @()
    )

    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    Write-Host "`n⏳ dotnet publish → $OutputDir" -ForegroundColor Gray

    # Thêm biến môi trường nội bộ để ép roll forward
    $env:DOTNET_ROLL_FORWARD = "LatestMajor"

    $allArgs = @('publish', $CsprojPath,
        '-c', 'Release',
        '-f', $Tfm,
        '-o', $OutputDir,
        '--roll-forward', 'LatestMajor',
        '--nologo') + $ExtraArgs

    & dotnet @allArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Build thất bại (exit $LASTEXITCODE)" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

function Show-OutputFiles([string]$dir, [string[]]$extensions) {
    $files = Get-ChildItem $dir -File | Where-Object { $_.Extension -in $extensions }
    if (-not $files) {
        Write-Warning "⚠️ Không tìm thấy file output trong $dir"
        return
    }
    Write-Host "`n📂 Output ($dir):" -ForegroundColor Cyan
    foreach ($f in $files) {
        $label = if ($f.Name -match '-Signed|release') { '🔏 SIGNED' } else { '📦 unsigned' }
        Write-Host "  $label  $($f.Name)  [$([math]::Round($f.Length/1MB,2)) MB]" -ForegroundColor Green
    }
    if ($IsWindows) { explorer.exe ((Resolve-Path $dir).Path) }
}

# ════════════════════════════════════════════════════════════════════════════
# GITHUB ACTIONS — kích hoạt workflow + theo dõi + download
# ════════════════════════════════════════════════════════════════════════════
function Invoke-GitHubBuild([string]$PackageFormat) {
    # Vô hiệu token môi trường để dùng gh auth
    $env:GITHUB_TOKEN = $null; $env:GH_TOKEN = $null

    # Tìm gh CLI
    $gh = $null
    if ($IsWindows) {
        $ghExe = Join-Path $PSScriptRoot 'gh.exe'
        $gh    = if (Test-Path $ghExe) { $ghExe } elseif (Get-Command gh -EA SilentlyContinue) { 'gh' } else { $null }
    } else {
        $gh = if (Get-Command gh -EA SilentlyContinue) { 'gh' } else { $null }
    }
    if (-not $gh) {
        Write-Host "❌ GitHub CLI (gh) chưa cài. Tải: https://cli.github.com/" -ForegroundColor Red; exit 1
    }

    & $gh auth status *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Chưa đăng nhập gh. Chạy: gh auth login --scopes workflow" -ForegroundColor Red; exit 1
    }

    $currentBranch = if (Get-Command git -EA SilentlyContinue) { git branch --show-current 2>$null } else { $null }
    if (-not $currentBranch) { $currentBranch = 'main' }

    # Chọn workflow
    $allWf = @(& $gh workflow list --json id,name,state | ConvertFrom-Json | Where-Object state -eq 'active')
    if ($allWf.Count -eq 0) { Write-Host "❌ Không có workflow active." -ForegroundColor Red; exit 1 }

    $priority = @($allWf | Where-Object { $_.name -match 'Build|MAUI|Android' })
    if ($priority.Count -eq 1) {
        $selected = $priority[0]
        Write-Host "✅ Workflow: $($selected.name)" -ForegroundColor Green
    } else {
        Write-Host "`n📋 Danh sách workflow:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $allWf.Count; $i++) {
            Write-Host "  [$i] $($allWf[$i].name)"
        }
        $c = Read-Host "`n👉 Số thứ tự"
        if ($c -notmatch '^\d+$' -or [int]$c -lt 0 -or [int]$c -ge $allWf.Count) {
            Write-Host "❌ Lựa chọn không hợp lệ." -ForegroundColor Red; exit 1
        }
        $selected = $allWf[[int]$c]
    }

    # Ghi nhớ run cũ rồi trigger
    $lastId = (& $gh run list --workflow $selected.id --limit 1 --json databaseId | ConvertFrom-Json).databaseId
    & $gh workflow run $selected.id --ref $currentBranch -f "package_format=$PackageFormat" 2>$null
    if ($LASTEXITCODE -ne 0) { & $gh workflow run $selected.id --ref $currentBranch }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Không kích hoạt được workflow." -ForegroundColor Red; exit 1
    }
    Write-Host "`n🚀 Đã kích hoạt | branch=$currentBranch format=$PackageFormat" -ForegroundColor Cyan

    # Đợi run mới xuất hiện
    $newId = $null
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep 2
        $cur = (& $gh run list --workflow $selected.id --limit 1 --json databaseId | ConvertFrom-Json).databaseId
        if ($cur -ne $lastId -and $null -ne $cur) { $newId = $cur; break }
    }

    if ($newId) {
        Write-Host "🎯 Run ID: $newId — đang theo dõi…" -ForegroundColor Green
        & $gh run watch $newId --exit-status
    } else {
        Write-Host "⚠️ Theo dõi run gần nhất…" -ForegroundColor Yellow
        & $gh run watch --exit-status
    }

    # Download artifact
    $outDir = 'apk-output'
    if (Test-Path $outDir) { Remove-Item "$outDir\*" -Recurse -Force -EA SilentlyContinue }
    else { New-Item -ItemType Directory $outDir | Out-Null }

    Write-Host "`n📦 Tải artifact…" -ForegroundColor Cyan
    if ($newId) { & $gh run download $newId --dir $outDir }
    else { & $gh run download --dir $outDir }

    # Flatten — đưa tất cả apk/aab lên root của $outDir
    Get-ChildItem $outDir -Recurse -File -Include *.apk,*.aab |
        Move-Item -Destination $outDir -Force -EA SilentlyContinue
    Get-ChildItem $outDir -Directory | Remove-Item -Recurse -Force -EA SilentlyContinue

    Write-Host "`n📂 Kết quả ($outDir):" -ForegroundColor Cyan
    Get-ChildItem $outDir -File | Where-Object { $_.Extension -in '.apk','.aab' } | ForEach-Object {
        $label = if ($_.Name -match '-Signed|release') { '🔏 SIGNED' } else { '📦 unsigned' }
        Write-Host "  $label  $($_.Name)  [$([math]::Round($_.Length/1MB,2)) MB]" -ForegroundColor Green
    }
    Write-Host "`n🎉 GitHub Actions hoàn tất." -ForegroundColor Green
    if ($IsWindows) { explorer.exe ((Resolve-Path $outDir).Path) }
}

# ════════════════════════════════════════════════════════════════════════════
# ENTRY POINT — Mode CI (flag -GitHub)
# ════════════════════════════════════════════════════════════════════════════
if ($GitHub) {
    Write-Host "`n╔═══════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host " ☁  GITHUB ACTIONS BUILD                 " -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════╝`n" -ForegroundColor Cyan

    $fmt = $Format
    if (-not $NonInteractive -and -not $PSBoundParameters.ContainsKey('Format')) {
        Write-Host "  [1] APK  [2] AAB" -ForegroundColor Cyan
        $p = Read-Host "👉 Chọn định dạng (Enter = APK)"
        $fmt = if ($p -eq '2') { 'aab' } else { 'apk' }
    } elseif (-not $PSBoundParameters.ContainsKey('Format')) {
        $fmt = 'apk'
    }

    Invoke-GitHubBuild -PackageFormat $fmt
    Write-Host "`a" -NoNewline
    exit 0
}

# ════════════════════════════════════════════════════════════════════════════
# ENTRY POINT — Menu tương tác
# ════════════════════════════════════════════════════════════════════════════
Write-Host "`n╔═══════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host " 🔨  MAUI BUILD TOOL — VIP PRO           " -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════╝`n" -ForegroundColor Cyan

$isMac = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::OSX)
$isWin = $IsWindows

Write-Host "  [0] Thoát"
Write-Host "  [1] Android — APK  (local)"
Write-Host "  [2] Android — AAB  (local)"
if ($isMac) {
    Write-Host "  [3] iOS            (macOS + Xcode)"
    Write-Host "  [4] Mac Catalyst   (macOS)"
}
if ($isWin) {
    Write-Host "  [5] Windows MSIX   (local)"
}
Write-Host "  [6] ☁  GitHub Actions — build + download"

$pick = Read-Host "`n👉 Chọn (Enter = 0)"
if ([string]::IsNullOrWhiteSpace($pick)) { $pick = '0' }

if ($pick -eq '0') { Write-Host 'Đã thoát.' -ForegroundColor Gray; exit 0 }

if ($pick -eq '6') {
    Write-Host "`n  [1] APK  [2] AAB" -ForegroundColor Cyan
    $p = Read-Host "👉 Định dạng (Enter = APK)"
    Invoke-GitHubBuild -PackageFormat (if ($p -eq '2') { 'aab' } else { 'apk' })
    Write-Host "`a" -NoNewline; exit 0
}

# ── Cần dotnet SDK cho build cục bộ ─────────────────────────────────────────
if (-not (Get-Command dotnet -EA SilentlyContinue)) {
    Write-Host "❌ dotnet SDK chưa cài." -ForegroundColor Red; exit 1
}

$csprojFile = Get-MauiCsproj
if (-not $csprojFile) {
    Write-Host "❌ Không tìm thấy .csproj MAUI." -ForegroundColor Red; exit 1
}

$tfms       = @(Get-CsprojTfms $csprojFile.FullName)
$androidTfm = Select-Tfm -Tfms $tfms -pattern '-android'
$iosTfm     = Select-Tfm -Tfms $tfms -pattern '-ios'
$macTfm     = Select-Tfm -Tfms $tfms -pattern '-maccatalyst'
$winTfm     = Select-Tfm -Tfms $tfms -pattern '-windows'
$root       = Join-Path $PSScriptRoot 'local-publish'

Write-Host "`n📄 $($csprojFile.Name)  [TFMs: $($tfms -join ', ')]" -ForegroundColor DarkGray

switch ($pick) {
    { $_ -in '1','2' } {
        if (-not $androidTfm) { Write-Host "❌ Không có TFM Android." -ForegroundColor Red; exit 1 }
        $fmt    = if ($pick -eq '2') { 'aab' } else { 'apk' }
        $outDir = Join-Path $root "android-$fmt"

        # Phát hiện keystore cục bộ
        $ksInfo = Find-AndroidKeystore (Split-Path $csprojFile.FullName)
        $signingArgs = @("-p:AndroidPackageFormat=$fmt")

        if ($ksInfo) {
            $ksInfo = Read-SigningInfo $ksInfo
        }
        if ($ksInfo -and $ksInfo.StorePass) {
            Write-Host "🔏 Build với keystore ký → chỉ xuất file đã ký" -ForegroundColor Green
            $signingArgs += @(
                "-p:AndroidSigningKeyStore=$($ksInfo.KeystorePath)",
                "-p:AndroidSigningStorePass=$($ksInfo.StorePass)",
                "-p:AndroidSigningKeyAlias=$($ksInfo.KeyAlias)",
                "-p:AndroidSigningKeyPass=$($ksInfo.KeyPass)"
            )
        } else {
            Write-Host "⚠️  Không có keystore → build unsigned" -ForegroundColor Yellow
        }

        Invoke-LocalBuild $csprojFile.FullName $androidTfm $outDir $signingArgs
        Write-Host "✅ Xong $($fmt.ToUpper())" -ForegroundColor Green
        Show-OutputFiles $outDir @('.apk','.aab')
    }
    '3' {
        if (-not $iosTfm)  { Write-Host "❌ Không có TFM iOS." -ForegroundColor Red; exit 1 }
        if (-not $isMac)   { Write-Host "❌ Cần macOS + Xcode." -ForegroundColor Red; exit 1 }
        $outDir = Join-Path $root 'ios'

        # Thêm biến môi trường bắt buộc để tạo file .ipa cho App Store
        $iosArgs = @('-r', 'ios-arm64', '-p:ArchiveOnBuild=true')
        
        Write-Host "⚠️  Lưu ý: Để build được file .ipa, macOS của bạn phải cài sẵn Apple Certificate và Provisioning Profile hợp lệ trong Keychain." -ForegroundColor Yellow

        Invoke-LocalBuild $csprojFile.FullName $iosTfm $outDir $iosArgs
        Write-Host "✅ Xong iOS." -ForegroundColor Green
        Show-OutputFiles $outDir @('.ipa','.app')
    }
    '4' {
        if (-not $macTfm)  { Write-Host "❌ Không có TFM Mac Catalyst." -ForegroundColor Red; exit 1 }
        if (-not $isMac)   { Write-Host "❌ Cần macOS." -ForegroundColor Red; exit 1 }
        $outDir = Join-Path $root 'maccatalyst'
        Invoke-LocalBuild $csprojFile.FullName $macTfm $outDir
        Write-Host "✅ Xong Mac Catalyst." -ForegroundColor Green
        Show-OutputFiles $outDir @('.pkg','.dmg','.app')
    }
    '5' {
        if (-not $winTfm)  { Write-Host "❌ Không có TFM Windows." -ForegroundColor Red; exit 1 }
        if (-not $isWin)   { Write-Host "❌ Cần Windows." -ForegroundColor Red; exit 1 }
        $outDir = Join-Path $root 'windows'
        $winArgs = @('-p:WindowsPackageType=MSIX', '-p:GenerateAppxPackageOnBuild=true')

        # Phát hiện PFX cert Windows
        $pfxFile = Get-ChildItem (Split-Path $csprojFile.FullName) -Recurse -Filter *.pfx -File |
            Where-Object { $_.FullName -notmatch '[\\/](obj|bin)[\\/]' } | Select-Object -First 1
        if ($pfxFile) {
            $pfxPass = Read-Host "🔑 PFX password ($($pfxFile.Name), Enter để bỏ qua)"
            if (-not [string]::IsNullOrWhiteSpace($pfxPass)) {
                Write-Host "🔏 Build với PFX cert → SIGNED MSIX" -ForegroundColor Green
                $winArgs += @("-p:PackageCertificateKeyFile=$($pfxFile.FullName)", "-p:PackageCertificatePassword=$pfxPass")
            } else {
                Write-Host "⚠️  Bỏ qua ký → UNSIGNED MSIX" -ForegroundColor Yellow
            }
        }

        Invoke-LocalBuild $csprojFile.FullName $winTfm $outDir $winArgs
        Write-Host "✅ Xong Windows MSIX." -ForegroundColor Green
        Show-OutputFiles $outDir @('.msix','.msixbundle','.appx')
    }
    default {
        Write-Host "❌ Lựa chọn không hợp lệ." -ForegroundColor Red; exit 1
    }
}

Write-Host "`a" -NoNewline