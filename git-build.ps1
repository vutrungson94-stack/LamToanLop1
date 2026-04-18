#!/usr/bin/env pwsh

# ==============================================================================
# SCRIPT: git-build.ps1 (ULTIMATE CROSS-PLATFORM VIP PRO)
# MỤC TIÊU: Auto CI Build Tool cho MAUI Android
# HỖ TRỢ: Windows, Linux, GitHub Codespaces
# ==============================================================================

# 0. Cấu hình SSH Di động (Vượt rào proxy/máy công ty)
$sshKeyPath = Join-Path $PSScriptRoot "ssh_id"
if (Test-Path $sshKeyPath) {
    $env:GIT_SSH_COMMAND = "ssh -i `"$sshKeyPath`" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"
}

Write-Host "`n=======================================" -ForegroundColor Cyan
Write-Host " 🚀 gbuild – AUTO CI BUILD TOOL (PRO)  " -ForegroundColor Cyan
Write-Host "=======================================`n" -ForegroundColor Cyan

# ==========================================================
# 1. Locate GitHub CLI (Thông minh: Nhận diện OS)
# ==========================================================
$gh = ""
if ($IsWindows) {
    $ghExe = Join-Path $PSScriptRoot "gh.exe"
    $gh = if (Test-Path $ghExe) { $ghExe } elseif (Get-Command gh -ErrorAction SilentlyContinue) { "gh" } else { $null }
} else {
    # Trên Linux/Codespaces, chỉ dùng lệnh hệ thống 'gh'
    $gh = if (Get-Command gh -ErrorAction SilentlyContinue) { "gh" } else { $null }
}

if (-not $gh) {
    Write-Host "❌ Lỗi: Không tìm thấy GitHub CLI (gh)" -ForegroundColor Red
    Write-Host "👉 Vui lòng cài đặt gh cli hoặc bỏ file gh.exe vào thư mục này (nếu dùng Windows)." -ForegroundColor Yellow
    exit 1
}

# ==========================================================
# 2. Check Auth (Hỗ trợ Codespaces Token)
# ==========================================================
$isAuthenticated = $false
if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
    # Codespaces thường có sẵn Token này, chúng ta tận dụng luôn
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

# Tự động lấy tên nhánh hiện tại
$currentBranch = "main"
if (Get-Command git -ErrorAction SilentlyContinue) {
    $branch = git branch --show-current 2>$null
    if (-not [string]::IsNullOrWhiteSpace($branch)) { $currentBranch = $branch }
}
Write-Host "🌿 Nhánh mục tiêu: [$currentBranch]" -ForegroundColor Green

# ==========================================================
# 3. Tự động dò tìm Workflow
# ==========================================================
Write-Host "🔍 Đang quét danh sách Workflow..." -ForegroundColor Cyan

try {
    $workflows = & $gh workflow list --json name,id,state,hasWorkflowDispatch | ConvertFrom-Json
    $dispatchable = $workflows | Where-Object { $_.hasWorkflowDispatch -eq $true -and $_.state -eq "active" }
} catch {
    Write-Host "❌ Lỗi: Không thể kết nối tới GitHub API." -ForegroundColor Red
    exit 1
}

if (-not $dispatchable) {
    Write-Host "❌ Không tìm thấy workflow nào có 'workflow_dispatch' đang bật." -ForegroundColor Red
    exit 1
}

$selected = $null
if ($dispatchable.Count -eq 1) {
    $selected = $dispatchable[0]
    Write-Host "✅ Đã chọn: $($selected.name)" -ForegroundColor Green
} else {
    Write-Host "`n📋 Danh sách Workflow:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $dispatchable.Count; $i++) {
        Write-Host "  [$i] $($dispatchable[$i].name)"
    }
    $choice = Read-Host "`n👉 Nhập số để chọn"
    $selected = $dispatchable[$choice]
}

# ==========================================================
# 4. Kích hoạt & Tracking Run ID (Chống Race Condition)
# ==========================================================
Write-Host "`n🚀 Đang kích hoạt tiến trình Build trên GitHub..." -ForegroundColor Cyan

# Lấy ID bản build gần nhất để làm mốc so sánh
$lastRunId = (& $gh run list --workflow $selected.id --limit 1 --json databaseId | ConvertFrom-Json).databaseId

& $gh workflow run $selected.id --ref $currentBranch
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Kích hoạt thất bại." -ForegroundColor Red
    exit 1
}

# Vòng lặp chờ ID mới xuất hiện
Write-Host "⏳ Đang bắt tín hiệu từ máy chủ GitHub..." -ForegroundColor Gray
$newRunId = $null
for ($i = 0; $i -lt 10; $i++) {
    Start-Sleep -Seconds 2
    $currentRunId = (& $gh run list --workflow $selected.id --limit 1 --json databaseId | ConvertFrom-Json).databaseId
    if ($currentRunId -ne $lastRunId -and $currentRunId -ne $null) {
        $newRunId = $currentRunId
        break
    }
}

if ($newRunId) {
    Write-Host "🎯 Đã bắt được tiến trình mới (ID: $newRunId). Bắt đầu theo dõi..." -ForegroundColor Green
    & $gh run watch $newRunId --exit-status
} else {
    Write-Host "⚠️ Không bắt được ID mới, đang dùng chế độ theo dõi tổng quát..." -ForegroundColor Yellow
    & $gh run watch --exit-status
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n❌ Build thất bại! Hãy kiểm tra lại code hoặc file .yml" -ForegroundColor Red
    exit 1
}

# ==========================================================
# 5. Tải & Flatten Artifacts (Làm đẹp thư mục)
# ==========================================================
$dir = "apk-output"
if (Test-Path $dir) { 
    Remove-Item -Path "$dir\*" -Recurse -Force -ErrorAction SilentlyContinue 
} else { 
    New-Item -ItemType Directory -Path $dir | Out-Null 
}

Write-Host "`n📦 Đang tải APK/AAB về máy..." -ForegroundColor Cyan
& $gh run download --dir $dir

# Di chuyển file ra thư mục gốc (Flatten)
Get-ChildItem -Path $dir -Recurse -File -Include *.apk,*.aab | Move-Item -Destination $dir -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path $dir -Directory | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# ==========================================================
# 6. Kiểm tra & Báo cáo
# ==========================================================
function Test-ApkSigned {
    param ([string]$path)
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($path)
        $signed = $false
        foreach ($e in $zip.Entries) { if ($e.FullName -match "^META-INF/.*\.(RSA|DSA|SF)$") { $signed = $true; break } }
        $zip.Dispose(); return $signed
    } catch { return $false }
}

$files = Get-ChildItem -Path $dir -Filter *.* | Where-Object { $_.Extension -match 'apk|aab' }
Write-Host "`n🔎 Kết quả thu được:" -ForegroundColor Cyan
foreach ($f in $files) {
    if ($f.Extension -eq ".aab") { Write-Host "  ⭐ GOOGLE PLAY : $($f.Name)" -ForegroundColor Magenta }
    elseif (Test-ApkSigned $f.FullName) { Write-Host "  ✅ ĐÃ KÝ (SIGNED): $($f.Name)" -ForegroundColor Green }
    else { Write-Host "  ⚠️ CHƯA KÝ (UNSIGNED): $($f.Name)" -ForegroundColor Yellow }
}

Write-Host "`n🎉 HOÀN TẤT! File đã sẵn sàng tại: $dir" -ForegroundColor Green
Write-Host "`a" -NoNewline # Phát tiếng bíp

if ($IsWindows) { explorer.exe $((Resolve-Path $dir).Path) }