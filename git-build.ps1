#!/usr/bin/env pwsh

Write-Host "`n=============================="
Write-Host "   gbuild – Auto CI Build Tool"
Write-Host "==============================`n"

# ==========================================================
# 1. Locate GitHub CLI
# ==========================================================
$ghExe = Join-Path $PSScriptRoot "gh.exe"

if (Test-Path $ghExe) {
    $gh = $ghExe
}
elseif (Get-Command gh -ErrorAction SilentlyContinue) {
    $gh = "gh"
}
else {
    Write-Host "❌ Không tìm thấy GitHub CLI (gh.exe / gh)" -ForegroundColor Red
    exit 1
}

# ==========================================================
# 2. Check GitHub auth
# ==========================================================
& $gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Chưa đăng nhập GitHub CLI" -ForegroundColor Red
    Write-Host "👉 Chạy: gh auth login" -ForegroundColor Yellow
    exit 1
}

# ==========================================================
# 3. Auto-detect workflow
# ==========================================================
Write-Host "🔍 Dò workflow có workflow_dispatch..." -ForegroundColor Cyan
$workflows = & $gh workflow list --json name,id,path,state | ConvertFrom-Json
$dispatchable = @()

foreach ($wf in $workflows) {
    try {
        $content = & $gh api repos/{owner}/{repo}/contents/$($wf.path) | ConvertFrom-Json
        $yaml = [System.Text.Encoding]::UTF8.GetString(
            [System.Convert]::FromBase64String($content.content)
        )
        if ($yaml -match "workflow_dispatch") {
            $dispatchable += $wf
        }
    } catch {}
}

if ($dispatchable.Count -eq 0) {
    Write-Host "❌ Không tìm thấy workflow nào có workflow_dispatch" -ForegroundColor Red
    exit 1
}

$selected = if ($dispatchable.Count -eq 1) {
    $dispatchable[0]
} else {
    for ($i = 0; $i -lt $dispatchable.Count; $i++) {
        Write-Host "[$i] $($dispatchable[$i].name)"
    }
    $choice = Read-Host "👉 Chọn workflow"
    $dispatchable[$choice]
}

Write-Host "✅ Dùng workflow: $($selected.name)" -ForegroundColor Green

# ==========================================================
# 4. Trigger CI
# ==========================================================
& $gh workflow run $selected.id
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Không trigger được workflow" -ForegroundColor Red
    exit 1
}

# ==========================================================
# 5. Watch CI
# ==========================================================
Write-Host "⏳ Đang chờ CI..." -ForegroundColor Yellow
& $gh run watch --exit-status
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ CI thất bại" -ForegroundColor Red
    exit 1
}

# ==========================================================
# 6. Download artifacts
# ==========================================================
$dir = "apk-output"
if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir | Out-Null
}

Write-Host "📦 Đang tải APK / AAB..." -ForegroundColor Cyan
& $gh run download --dir $dir

# ==========================================================
# 7. Detect signed / unsigned APK
# ==========================================================
function Test-ApkSigned {
    param ([string]$ApkPath)
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ApkPath)
        foreach ($e in $zip.Entries) {
            if ($e.FullName -match "^META-INF/.*\.RSA$") {
                $zip.Dispose()
                return $true
            }
        }
        $zip.Dispose()
        return $false
    } catch { return $false }
}

$apks = Get-ChildItem $dir -Recurse -Filter *.apk
$unsignedFound = $false

Write-Host "`n🔎 Kiểm tra chữ ký APK:" -ForegroundColor Cyan
foreach ($apk in $apks) {
    if (Test-ApkSigned $apk.FullName) {
        Write-Host " ✅ SIGNED   : $($apk.Name)" -ForegroundColor Green
    }
    else {
        Write-Host " ⚠️ UNSIGNED : $($apk.Name)" -ForegroundColor Yellow
        $unsignedFound = $true
    }
}

if ($unsignedFound) {
    Write-Host "`n🚫 CẢNH BÁO: APK unsigned – KHÔNG ĐƯỢC UPLOAD PLAY" -ForegroundColor Red
}

Write-Host "`n✅ BUILD HOÀN TẤT"
Write-Host "📂 File nằm tại: $((Resolve-Path $dir).Path)" -ForegroundColor Cyan

if ($IsWindows) {
    explorer.exe $dir
}