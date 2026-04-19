#!/usr/bin/env pwsh

# ==============================================================================
# git-sync.ps1 — CHỈ đồng bộ Git (pull / commit / push). Không build.
# Build (máy + GitHub Actions): build.ps1 | Đồng bộ Git: script này
# ==============================================================================

# 0. Cấu hình SSH (tùy chọn)
$sshKeyPath = Join-Path $PSScriptRoot "ssh_id"
if (Test-Path $sshKeyPath) {
    $env:GIT_SSH_COMMAND = "ssh -i `"$sshKeyPath`" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"
}

Write-Host "`n=======================================" -ForegroundColor Cyan
Write-Host " 🚀 GIT SYNC — CHỈ ĐỒNG BỘ REPO       " -ForegroundColor Cyan
Write-Host "=======================================`n" -ForegroundColor Cyan

function Unstage-BuildArtifacts {
    $staged = @(git diff --cached --name-only --diff-filter=ACM 2>$null)
    foreach ($line in $staged) {
        if (-not $line) { continue }
        if ($line -match '\.(apk|aab|ipa)$|\.app[/\\]') {
            git reset HEAD -- $line 2>$null
            Write-Host "⚠️ Đã gỡ khỏi commit (artifact chỉ lưu máy): $line" -ForegroundColor DarkYellow
        }
    }
}

# ==========================================================
# 1. Git & nhánh
# ==========================================================
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Lỗi: Git chưa được cài đặt hoặc chưa có trong PATH." -ForegroundColor Red
    exit 1
}

git rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Thư mục hiện tại không phải Git repository." -ForegroundColor Red
    exit 1
}

$currentBranch = git branch --show-current
if ([string]::IsNullOrWhiteSpace($currentBranch)) {
    $currentBranch = "main"
}
Write-Host "🌿 Nhánh: [$currentBranch]" -ForegroundColor Green

# ==========================================================
# 2. Pull
# ==========================================================
$statusBefore = git status --porcelain
if (-not $statusBefore) {
    Write-Host "🔄 Repo sạch — git pull --rebase..." -ForegroundColor Magenta
    git pull --rebase origin $currentBranch
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Pull thất bại — xử lý conflict rồi chạy lại." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "✏️ Có thay đổi cục bộ — bỏ qua pull để giữ code của bạn." -ForegroundColor DarkGray
}

# ==========================================================
# 3. Thay đổi cần commit
# ==========================================================
$status = git status --porcelain
if (-not $status) {
    Write-Host "`n✅ Không có gì để commit / push." -ForegroundColor Green
    exit 0
}

Write-Host "`n📂 Thay đổi:" -ForegroundColor Yellow
$status | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

if ($status -match 'bin[/\\]|obj[/\\]') {
    Write-Host "`n❌ Có bin/ hoặc obj/ trong thay đổi — kiểm tra .gitignore." -ForegroundColor Red
    exit 1
}

# ==========================================================
# 4. Commit & push
# ==========================================================
Write-Host "`n✍️ Commit..." -ForegroundColor Cyan
$commitMsg = Read-Host "👉 Nội dung (Enter = giờ hệ thống)"
if ([string]::IsNullOrWhiteSpace($commitMsg)) {
    $commitMsg = "Cập nhật lúc " + (Get-Date -Format "HH:mm dd/MM/yyyy")
}

git add .
Unstage-BuildArtifacts
git commit -m "$commitMsg" | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Commit thất bại." -ForegroundColor Red
    exit 1
}

Write-Host "`n🚀 git push origin $currentBranch ..." -ForegroundColor Cyan
git push origin $currentBranch

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n⚠️ Push bị từ chối." -ForegroundColor Yellow
    $answer = Read-Host "👉 Force-with-lease? (y/n)"
    if ($answer -eq "y") {
        git push origin $currentBranch --force-with-lease
    } else {
        exit 1
    }
}

Write-Host "`n🎉 Đồng bộ xong." -ForegroundColor Green
Write-Host "`a" -NoNewline
