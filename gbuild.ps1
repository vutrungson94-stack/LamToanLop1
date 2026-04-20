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

# ── SSH key tuỳ chọn ────────────────────────────────────────────────────────
$sshKeyPath = Join-Path $PSScriptRoot 'ssh_id'
if (Test-Path $sshKeyPath) {
    $env:GIT_SSH_COMMAND = "ssh -i `"$sshKeyPath`" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"
}

# ════════════════════════════════════════════════════════════════════════════
# HELPERS — TFM
# ════════════════════════════════════════════════════════════════════════════
function Get-CsprojTfms([string]$projPath) {
    [xml]$x = Get-Content -LiteralPath $projPath
    $list = [System.Collections.Generic.List[string]]::new()
    foreach ($pg in @($x.Project.PropertyGroup)) {
        if ($null -eq $pg) { continue }
        # Tránh lỗi StrictMode bằng cách duyệt ChildNodes thay vì gọi property động
        foreach ($node in @($pg.ChildNodes)) {
            if ($node.Name -eq 'TargetFrameworks' -or $node.Name -eq 'TargetFramework') {
                $blob = $node.InnerText.Trim()
                foreach ($p in ($blob -split ';')) {
                    $t = $p.Trim()
                    if (-not $t -or $t -match '^\$\(') { continue }
                    foreach ($piece in ($t -split '\s+')) {
                        if ($piece -and $piece -notmatch '^\$\(') { [void]$list.Add($piece) }
                    }
                }
            }
        }
    }
    return ,@($list | Select-Object -Unique)
}

function Pick-Tfm([string[]]$tfms, [string]$pattern) {
    foreach ($t in $tfms) {
        $m = [regex]::Match($t, $pattern)
        if ($m.Success) { return $m.Value }
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

function Prompt-SigningInfo([hashtable]$ks) {
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

    $allArgs = @('publish', $CsprojPath,
        '-c', 'Release',
        '-f', $Tfm,
        '-o', $OutputDir,
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
$androidTfm = Pick-Tfm $tfms 'net[0-9]+\.[0-9]+-android[0-9.]*'
$iosTfm     = Pick-Tfm $tfms 'net[0-9]+\.[0-9]+-ios[0-9.]*'
$macTfm     = Pick-Tfm $tfms 'net[0-9]+\.[0-9]+-maccatalyst[0-9.]*'
$winTfm     = Pick-Tfm $tfms 'net[0-9]+\.[0-9]+-windows[0-9.]*'
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
            $ksInfo = Prompt-SigningInfo $ksInfo
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
        Invoke-LocalBuild $csprojFile.FullName $iosTfm $outDir
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