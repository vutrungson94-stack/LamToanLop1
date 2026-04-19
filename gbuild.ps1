#!/usr/bin/env pwsh

# ==============================================================================
# build.ps1 — Build cục bộ (local-publish/) + GitHub Actions (gh, apk-output/)
# Đồng bộ Git: git-sync.ps1
# Dòng lệnh: .\build.ps1 -GitHub [-PackageFormat apk|aab] [-NonInteractive]
# ==============================================================================

[CmdletBinding(DefaultParameterSetName = 'Menu')]
param(
    [Parameter(ParameterSetName = 'Ci')]
    [switch]$GitHub,
    [Parameter(ParameterSetName = 'Ci')]
    [ValidateSet('apk', 'aab')]
    [string]$PackageFormat,
    [Parameter(ParameterSetName = 'Ci')]
    [switch]$NonInteractive
)

$sshKeyPath = Join-Path $PSScriptRoot "ssh_id"
if (Test-Path $sshKeyPath) {
    $env:GIT_SSH_COMMAND = "ssh -i `"$sshKeyPath`" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"
}

function Get-CsprojTfms([string]$projPath) {
    [xml]$x = Get-Content -LiteralPath $projPath
    $list = [System.Collections.Generic.List[string]]::new()
    foreach ($pg in @($x.Project.PropertyGroup)) {
        if ($null -ne $pg.TargetFrameworks) {
            foreach ($tfmNode in @($pg.TargetFrameworks)) {
                $blob = if ($tfmNode -is [System.Xml.XmlElement]) { $tfmNode.InnerText.Trim() } else { ([string]$tfmNode).Trim() }
                if (-not $blob) { continue }
                foreach ($p in ($blob -split ';')) {
                    $t = $p.Trim()
                    if (-not $t) { continue }
                    if ($t -match '^\$\(') { continue }
                    foreach ($piece in ($t -split '\s+', [System.StringSplitOptions]::RemoveEmptyEntries)) {
                        if ($piece -match '^\$\(') { continue }
                        [void]$list.Add($piece)
                    }
                }
            }
        }
        if ($null -ne $pg.TargetFramework) {
            foreach ($tfNode in @($pg.TargetFramework)) {
                $one = if ($tfNode -is [System.Xml.XmlElement]) { $tfNode.InnerText.Trim() } else { ([string]$tfNode).Trim() }
                if (-not $one -or $one -match '^\$\(') { continue }
                foreach ($piece in ($one -split '\s+', [System.StringSplitOptions]::RemoveEmptyEntries)) {
                    [void]$list.Add($piece)
                }
            }
        }
    }
    return ,@($list | Select-Object -Unique)
}

function Get-AndroidTfmMoniker {
    param([string[]]$Tfms)
    foreach ($raw in @($Tfms)) {
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        $m = [regex]::Match($raw, 'net[0-9]+\.[0-9]+-android[0-9.]*')
        if ($m.Success) { return $m.Value }
    }
    return $null
}

function Get-IosTfmMoniker {
    param([string[]]$Tfms)
    foreach ($raw in @($Tfms)) {
        if ([string]::IsNullOrWhiteSpace($raw) -or $raw -match 'maccatalyst') { continue }
        $m = [regex]::Match($raw, 'net[0-9]+\.[0-9]+-ios[0-9.]*')
        if ($m.Success) { return $m.Value }
    }
    return $null
}

function Get-MacCatalystTfmMoniker {
    param([string[]]$Tfms)
    foreach ($raw in @($Tfms)) {
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        $m = [regex]::Match($raw, 'net[0-9]+\.[0-9]+-maccatalyst[0-9.]*')
        if ($m.Success) { return $m.Value }
    }
    return $null
}

function Get-MauiAppCsproj {
    $all = Get-ChildItem -Path . -Recurse -Filter *.csproj -File | Where-Object {
        $_.FullName -notmatch '[\\/](obj|bin|packages|node_modules)[\\/]'
    } | Sort-Object FullName
    foreach ($c in $all) {
        if ($c.Name -match '\.Tests\.') { continue }
        $raw = Get-Content -LiteralPath $c.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $raw) { continue }
        if ($raw -match '<UseMaui>\s*true\s*</UseMaui>') { return $c }
    }
    foreach ($c in $all) {
        if ($c.Name -match '\.Tests\.') { continue }
        $tfms = Get-CsprojTfms $c.FullName
        if ($tfms | Where-Object { $_ -match 'android|ios|maccatalyst|windows' }) { return $c }
    }
    return (Get-ChildItem -Path . -Recurse -Filter *.csproj -File | Where-Object {
        $_.FullName -notmatch '[\\/](obj|bin)[\\/]'
    } | Select-Object -First 1)
}

function Invoke-GitHubActionsBuild {
    param(
        [string]$PackageFormat
    )

    if ($env:GITHUB_TOKEN -or $env:GH_TOKEN) {
        $env:GITHUB_TOKEN = $null
        $env:GH_TOKEN = $null
    }

    $gh = ""
    if ($IsWindows) {
        $ghExe = Join-Path $PSScriptRoot "gh.exe"
        $gh = if (Test-Path $ghExe) { $ghExe } elseif (Get-Command gh -ErrorAction SilentlyContinue) { "gh" } else { $null }
    } else {
        $gh = if (Get-Command gh -ErrorAction SilentlyContinue) { "gh" } else { $null }
    }
    if (-not $gh) {
        Write-Host "❌ Cần GitHub CLI (gh). Cài: https://cli.github.com/" -ForegroundColor Red
        exit 1
    }

    & $gh auth status *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Chưa đăng nhập gh. Chạy: gh auth login --scopes workflow" -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ gh đã xác thực." -ForegroundColor Gray

    $currentBranch = "main"
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $branch = git branch --show-current 2>$null
        if (-not [string]::IsNullOrWhiteSpace($branch)) { $currentBranch = $branch }
    }

    Write-Host "🔍 Đang quét workflow..." -ForegroundColor Cyan
    try {
        $workflowsJson = & $gh workflow list --json id,name,state
        $workflows = $workflowsJson | ConvertFrom-Json
        $activeWorkflows = @($workflows | Where-Object { $_.state -eq "active" })
    } catch {
        Write-Host "❌ Không lấy được danh sách workflow." -ForegroundColor Red
        exit 1
    }
    if ($activeWorkflows.Count -eq 0) {
        Write-Host "❌ Không có workflow active." -ForegroundColor Red
        exit 1
    }

    $priorityWorkflows = @($activeWorkflows | Where-Object { $_.name -match "Build|Android" })
    if ($priorityWorkflows.Count -eq 1) {
        $selected = $priorityWorkflows[0]
        Write-Host "✅ Workflow: $($selected.name)" -ForegroundColor Green
    } else {
        Write-Host "`n📋 Workflow:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $activeWorkflows.Count; $i++) {
            Write-Host "  [$i] $($activeWorkflows[$i].name)"
        }
        $choice = Read-Host "`n👉 Số workflow"
        if ($choice -notmatch '^\d+$' -or [int]$choice -lt 0 -or [int]$choice -ge $activeWorkflows.Count) {
            Write-Host "❌ Số không hợp lệ." -ForegroundColor Red
            exit 1
        }
        $selected = $activeWorkflows[[int]$choice]
    }

    Write-Host "`n🚀 Kích hoạt build [$currentBranch] (package_format=$PackageFormat)..." -ForegroundColor Cyan
    $lastRunId = (& $gh run list --workflow $selected.id --limit 1 --json databaseId | ConvertFrom-Json).databaseId
    & $gh workflow run $selected.id --ref $currentBranch -f "package_format=$PackageFormat"
    if ($LASTEXITCODE -ne 0) { & $gh workflow run $selected.id --ref $currentBranch }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Không kích hoạt được workflow (cần workflow_dispatch?)." -ForegroundColor Red
        exit 1
    }

    $newRunId = $null
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 2
        $currentRunId = (& $gh run list --workflow $selected.id --limit 1 --json databaseId | ConvertFrom-Json).databaseId
        if ($currentRunId -ne $lastRunId -and $null -ne $currentRunId) {
            $newRunId = $currentRunId
            break
        }
    }
    if ($newRunId) {
        Write-Host "🎯 Run ID: $newRunId — đang theo dõi..." -ForegroundColor Green
        & $gh run watch $newRunId --exit-status
    } else {
        Write-Host "⚠️ Theo dõi run gần nhất..." -ForegroundColor Yellow
        & $gh run watch --exit-status
    }

    $dir = "apk-output"
    if (Test-Path $dir) { Remove-Item -Path "$dir\*" -Recurse -Force -ErrorAction SilentlyContinue }
    else { New-Item -ItemType Directory -Path $dir | Out-Null }

    Write-Host "`n📦 Tải artifact..." -ForegroundColor Cyan
    if ($newRunId) { & $gh run download $newRunId --dir $dir }
    else { & $gh run download --dir $dir }

    Get-ChildItem -Path $dir -Recurse -File -Include *.apk, *.aab | Move-Item -Destination $dir -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $dir -Directory | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "`n🔎 File trong $dir :" -ForegroundColor Cyan
    Get-ChildItem -Path $dir -File | Where-Object { $_.Extension -match 'apk|aab' } | ForEach-Object {
        $t = if ($_.Extension -eq ".aab") { "AAB" } else { "APK" }
        Write-Host "  $t : $($_.Name)" -ForegroundColor Green
    }
    Write-Host "`n🎉 GitHub Actions xong." -ForegroundColor Green
    if ($IsWindows) { explorer.exe $((Resolve-Path $dir).Path) }
}

# --- Chế độ dòng lệnh: chỉ CI ---
if ($GitHub) {
    Write-Host "`n=======================================" -ForegroundColor Cyan
    Write-Host " ☁️  GITHUB ACTIONS (gh)                " -ForegroundColor Cyan
    Write-Host "=======================================`n" -ForegroundColor Cyan

    $fmt = $PackageFormat
    if (-not $NonInteractive) {
        if (-not $PSBoundParameters.ContainsKey('PackageFormat')) {
            Write-Host "  [1] APK  [2] AAB" -ForegroundColor Cyan
            $p = Read-Host "👉 Chọn (Enter = 1)"
            if ([string]::IsNullOrWhiteSpace($p)) { $p = "1" }
            $fmt = if ($p -eq "2") { "aab" } else { "apk" }
        }
    } elseif (-not $PSBoundParameters.ContainsKey('PackageFormat')) {
        $fmt = "apk"
    }
    Invoke-GitHubActionsBuild -PackageFormat $fmt
    Write-Host "`a" -NoNewline
    exit 0
}

# --- Menu: build cục bộ hoặc CI ---
Write-Host "`n=======================================" -ForegroundColor Cyan
Write-Host " 🔨 BUILD — Local + GitHub Actions      " -ForegroundColor Cyan
Write-Host "=======================================`n" -ForegroundColor Cyan

Write-Host "📦 Chọn:" -ForegroundColor Cyan
Write-Host "  [0] Thoát"
Write-Host "  [1] Android — APK (máy này → local-publish/)"
Write-Host "  [2] Android — AAB (máy này → local-publish/)"
Write-Host "  [3] iOS (macOS + Xcode)"
Write-Host "  [4] Mac Catalyst (macOS)"
Write-Host "  [5] GitHub Actions — chạy workflow & tải về apk-output/"

$pick = Read-Host "`n👉 Chọn (Enter = 0)"
if ([string]::IsNullOrWhiteSpace($pick)) { $pick = "0" }

if ($pick -eq "0") {
    Write-Host "Đã thoát." -ForegroundColor Gray
    exit 0
}

if ($pick -eq "5") {
    Write-Host "`n  [1] APK  [2] AAB (input workflow)" -ForegroundColor Cyan
    $p = Read-Host "👉 Định dạng gửi Actions (Enter = 1)"
    if ([string]::IsNullOrWhiteSpace($p)) { $p = "1" }
    $fmt = if ($p -eq "2") { "aab" } else { "apk" }
    Invoke-GitHubActionsBuild -PackageFormat $fmt
    Write-Host "`a" -NoNewline
    exit 0
}

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Cần dotnet SDK (mục 1–4)." -ForegroundColor Red
    exit 1
}

$projectFile = Get-MauiAppCsproj
if (-not $projectFile) {
    Write-Host "❌ Không tìm thấy .csproj." -ForegroundColor Red
    exit 1
}

$tfms = @(Get-CsprojTfms $projectFile.FullName)
$androidTfm = Get-AndroidTfmMoniker $tfms
$iosTfm = Get-IosTfmMoniker $tfms
$macTf = Get-MacCatalystTfmMoniker $tfms
$isMac = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)

Write-Host "`n📄 $($projectFile.Name) | TFM: $($tfms -join ', ')" -ForegroundColor Gray

$root = Join-Path $PSScriptRoot "local-publish"

switch ($pick) {
    "1" {
        if (-not $androidTfm) { Write-Host "❌ Không có TFM Android." -ForegroundColor Red; exit 1 }
        $out = Join-Path $root "android-apk"
        New-Item -ItemType Directory -Path $out -Force | Out-Null
        Write-Host "⏳ APK → $out ..." -ForegroundColor Gray
        dotnet publish $projectFile.FullName -c Release -f $androidTfm -p:AndroidPackageFormat=apk -o $out --nologo
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        Write-Host "✅ Xong APK." -ForegroundColor Green
    }
    "2" {
        if (-not $androidTfm) { Write-Host "❌ Không có TFM Android." -ForegroundColor Red; exit 1 }
        $out = Join-Path $root "android-aab"
        New-Item -ItemType Directory -Path $out -Force | Out-Null
        Write-Host "⏳ AAB → $out ..." -ForegroundColor Gray
        dotnet publish $projectFile.FullName -c Release -f $androidTfm -p:AndroidPackageFormat=aab -o $out --nologo
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        Write-Host "✅ Xong AAB." -ForegroundColor Green
    }
    "3" {
        if (-not $iosTfm) { Write-Host "❌ Không có TFM iOS trong .csproj." -ForegroundColor Red; exit 1 }
        if (-not $isMac) { Write-Host "❌ Cần macOS + Xcode." -ForegroundColor Red; exit 1 }
        $out = Join-Path $root "ios"
        New-Item -ItemType Directory -Path $out -Force | Out-Null
        dotnet publish $projectFile.FullName -c Release -f $iosTfm -p:TargetFrameworks=$iosTfm -o $out --nologo
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        Write-Host "✅ Xong iOS." -ForegroundColor Green
    }
    "4" {
        if (-not $macTf) { Write-Host "❌ Không có Mac Catalyst." -ForegroundColor Red; exit 1 }
        if (-not $isMac) { Write-Host "❌ Cần macOS." -ForegroundColor Red; exit 1 }
        $out = Join-Path $root "maccatalyst"
        New-Item -ItemType Directory -Path $out -Force | Out-Null
        dotnet publish $projectFile.FullName -c Release -f $macTf -p:TargetFrameworks=$macTf -o $out --nologo
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        Write-Host "✅ Xong Mac Catalyst." -ForegroundColor Green
    }
    default {
        Write-Host "❌ Lựa chọn không hợp lệ." -ForegroundColor Red
        exit 1
    }
}

if ($IsWindows) {
    $open = Join-Path $root (switch ($pick) { "1" { "android-apk" } "2" { "android-aab" } "3" { "ios" } "4" { "maccatalyst" } })
    if (Test-Path $open) { explorer.exe $((Resolve-Path $open).Path) }
}

Write-Host "`a" -NoNewline
