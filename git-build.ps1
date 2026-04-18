#!/usr/bin/env pwsh

# ==============================================================================
# SCRIPT: git-build.ps1 (ULTIMATE COMPATIBLE VIP PRO)
# MỤC TIÊU: Chạy được trên mọi phiên bản GitHub CLI (Kể cả bản cũ trên Codespaces)
# ==============================================================================

# 0. Cấu hình SSH
$sshKeyPath = Join-Path $PSScriptRoot "ssh_id"
if (Test-Path $sshKeyPath) {
    $env:GIT_SSH_COMMAND = "ssh -i `"$sshKeyPath`" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"
}

Write-Host "`n=======================================" -ForegroundColor Cyan
Write-Host " 🚀 gbuild – AUTO CI BUILD TOOL (PRO)  " -ForegroundColor Cyan
Write-Host "=======================================`n" -ForegroundColor Cyan

# ==========================================================
# 1. Locate GitHub CLI (Nhận diện thông minh)
# ==========================================================
$gh = ""
if ($IsWindows) {
    $ghExe = Join-Path $PSScriptRoot "gh.exe"
    $gh = if (Test-Path $ghExe) { $ghExe } elseif (Get-Command gh -ErrorAction SilentlyContinue) { "gh" } else { $null }
} else {
    $gh = if (Get-Command gh -ErrorAction SilentlyContinue) { "gh" } else { $null }
}

if (-not $gh) {
    Write-Host "❌ Lỗi: Không tìm thấy GitHub CLI (gh)" -ForegroundColor Red
    exit 1
}

# ==========================================================
# 2. Check Auth (Hỗ trợ Codespaces Token)
# ==========================================================
$isAuthenticated = $false
if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
    $isAuthenticated = $true 
} else {
    & $gh auth status *> $null
    if ($LASTEXITCODE -eq 0) { $isAuthenticated = $true }
}

if (-not $isAuthenticated) {
    Write-Host "❌ Lỗi: Chưa đăng nhập GitHub CLI" -ForegroundColor Red
    Write-Host "👉 Hãy chạy lệnh: gh auth login --scopes workflow" -ForegroundColor Yellow
    exit 1
}
Write-Host "✅ Xác thực thành công!" -ForegroundColor Gray

$currentBranch = "main"
if (Get-Command git -ErrorAction SilentlyContinue) {
    $branch = git branch --show-current 2>$null
    if (-not [string]::IsNullOrWhiteSpace($branch)) { $currentBranch = $branch }
}

# ==========================================================
# 3. Tự động dò tìm Workflow (Bản sửa lỗi 'Unknown JSON field')
# ==========================================================
Write-Host "🔍 Đang quét danh sách Workflow..." -ForegroundColor Cyan

try {
    # Chỉ lấy các trường cơ bản mà bản gh cũ cũng hiểu được
    $workflowsJson = & $gh workflow list --json id,name,state
    $workflows = $workflowsJson | ConvertFrom-Json
    # Chỉ lấy các Workflow đang hoạt động
    $activeWorkflows = $workflows | Where-Object { $_.state -eq "active" }
} catch {
    Write-Host "❌ Lỗi: Không thể lấy danh sách workflow từ GitHub." -ForegroundColor Red
    exit 1
}

if (-not $activeWorkflows -or $activeWorkflows.Count -eq 0) {
    Write-Host "❌ Không tìm thấy workflow nào đang hoạt động." -ForegroundColor Red
    exit 1
}

$selected = $null
# Ưu tiên tìm workflow có tên chứa chữ "Build" hoặc "Android"
$priorityWorkflows = $activeWorkflows | Where-Object { $_.name -match "Build|Android" }

if ($priorityWorkflows.Count -eq 1) {
    $selected = $priorityWorkflows[0]
    Write-Host "✅ Tự động chọn: $($selected.name)" -ForegroundColor Green
} else {
    Write-Host "`n📋 Danh sách Workflow khả dụng:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $activeWorkflows.Count; $i++) {
        Write-Host "  [$i] $($activeWorkflows[$i].name)"
    }
    $choice = Read-Host "`n👉 Nhập số để chọn Workflow muốn Build"
    $selected = $activeWorkflows[$choice]
}

# ==========================================================
# 4. Kích hoạt & Tracking Run ID
# ==========================================================
Write-Host "`n🚀 Đang kích hoạt tiến trình Build [$currentBranch]..." -ForegroundColor Cyan

$lastRunId = (& $gh run list --workflow $selected.id --limit 1 --json databaseId | ConvertFrom-Json).databaseId

& $gh workflow run $selected.id --ref $currentBranch
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Không thể kích hoạt. Hãy đảm bảo file .yml có 'workflow_dispatch'." -ForegroundColor Red
    exit 1
}

Write-Host "⏳ Đang đợi GitHub xác nhận tiến trình mới..." -ForegroundColor Gray
$newRunId = $null
for ($i = 0; $i -lt 15; $i++) {
    Start-Sleep -Seconds 2
    $currentRunId = (& $gh run list --workflow $selected.id --limit 1 --json databaseId | ConvertFrom-Json).databaseId
    if ($currentRunId -ne $lastRunId -and $currentRunId -ne $null) {
        $newRunId = $currentRunId
        break
    }
}

if ($newRunId) {
    Write-Host "🎯 Đã bắt được tiến trình (ID: $newRunId). Đang theo dõi..." -ForegroundColor Green
    & $gh run watch $newRunId --exit-status
} else {
    Write-Host "⚠️ Không bắt được ID mới kịp lúc, đang theo dõi tổng quát..." -ForegroundColor Yellow
    & $gh run watch --exit-status
}

# ==========================================================
# 5. Tải & Flatten Artifacts
# ==========================================================
$dir = "apk-output"
if (Test-Path $dir) { 
    Remove-Item -Path "$dir\*" -Recurse -Force -ErrorAction SilentlyContinue 
} else { 
    New-Item -ItemType Directory -Path $dir | Out-Null 
}

Write-Host "`n📦 Đang tải kết quả build về..." -ForegroundColor Cyan
& $gh run download --dir $dir

# Làm phẳng thư mục (Flatten)
Get-ChildItem -Path $dir -Recurse -File -Include *.apk,*.aab | Move-Item -Destination $dir -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path $dir -Directory | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# ==========================================================
# 6. Báo cáo cuối cùng
# ==========================================================
Write-Host "`n🔎 Tổng hợp file đã tải về:" -ForegroundColor Cyan
$files = Get-ChildItem -Path $dir -Filter *.* | Where-Object { $_.Extension -match 'apk|aab' }
foreach ($f in $files) {
    $type = if ($f.Extension -eq ".aab") { "⭐ PLAY STORE" } else { "📱 APK" }
    Write-Host "  $type : $($f.Name)" -ForegroundColor Green
}

Write-Host "`n🎉 HOÀN TẤT! Chúc mừng bạn!" -ForegroundColor Green
Write-Host "`a" -NoNewline
if ($IsWindows) { explorer.exe $((Resolve-Path $dir).Path) }