Write-Host "=============================="
Write-Host "  Git Tự Động Sync & Push  "
Write-Host "=============================="

# 1. Kiểm tra Git
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Git chưa được cài hoặc chưa có trong PATH"
    exit 1
}

# 2. Kiểm tra có phải Git repo không
git rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Thư mục hiện tại không phải là Git repository"
    exit 1
}

# 3. Pull code mới nhất (rebase an toàn)
Write-Host "🔄 Đang pull code mới nhất (rebase)..."
git pull --rebase origin main
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Pull thất bại. Vui lòng kiểm tra conflict!"
    exit 1
}

# 4. Kiểm tra có thay đổi không
$status = git status --porcelain
if (-not $status) {
    Write-Host "✅ Không có thay đổi. Repository đã được đồng bộ."
    exit 0
}

# 5. Hiển thị danh sách file thay đổi
Write-Host "📂 Các file đã thay đổi:"
$status

# 6. Nhập commit message
$commitMsg = Read-Host "✏️ Nhập nội dung commit"
if ([string]::IsNullOrWhiteSpace($commitMsg)) {
    Write-Host "❌ Commit message không được để trống"
    exit 1
}

# 7. Commit
git add .
git commit -m "$commitMsg"
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Commit thất bại"
    exit 1
}

# 8. Push
Write-Host "🚀 Đang push code lên GitHub..."
git push origin main
if ($LASTEXITCODE -ne 0) {
    Write-Host "⚠️ Push thông thường thất bại. Thử force-with-lease..."
    git push origin main --force-with-lease
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Push thất bại hoàn toàn"
        exit 1
    }
}

Write-Host "✅ Sync & Push thành công 🎉"