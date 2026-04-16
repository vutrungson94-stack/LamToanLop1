Write-Host "=============================="
Write-Host "  Git Tự Động Sync – Build – Push  "
Write-Host "=============================="

# 1. Kiểm tra Git
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Git chưa được cài hoặc chưa có trong PATH"
    exit 1
}

# 2. Kiểm tra Git repository
git rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Thư mục hiện tại không phải Git repository"
    exit 1
}

# 3. Kiểm tra trạng thái ban đầu
$statusBefore = git status --porcelain

# 4. CHỈ pull khi repo sạch (lần đầu mở VS Code / chưa sửa gì)
if (-not $statusBefore) {
    Write-Host "🔄 Repo sạch – đang pull code mới nhất..."
    git pull --rebase origin main
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Pull thất bại – vui lòng kiểm tra conflict!"
        exit 1
    }
} else {
    Write-Host "✏️ Phát hiện đang sửa code local – bỏ qua pull"
}

# 5. Kiểm tra lại thay đổi
$status = git status --porcelain
if (-not $status) {
    Write-Host "✅ Không có thay đổi – repo đã đồng bộ."
    exit 0
}

# 6. Hiển thị các file thay đổi
Write-Host "📂 Các file đã thay đổi:"
$status

# 7. CHẶN build artifacts lọt commit
$forbidden = $status | Select-String -Pattern "bin/|obj/"
if ($forbidden) {
    Write-Host "❌ Phát hiện bin/ hoặc obj/. Commit bị chặn!"
    exit 1
}

# 8. BUILD TRƯỚC KHI COMMIT (nếu có dotnet)
Write-Host "🔧 Kiểm tra môi trường build..."

if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    Write-Host "🔧 Đang build MAUI (Android)..."
    dotnet build -f $androidFramework
    if ($LASTEXITCODE -ne 0) {
        $answer = Read-Host "⚠️ Build thất bại. Có bỏ qua build để tiếp tục commit/push không? (y/n)"
        if ($answer -ne "y") {
            Write-Host "⏹️ Dừng script theo yêu cầu"
            exit 1
        }
        Write-Host "⚠️ Bỏ qua bước build theo yêu cầu người dùng"
    } else {
        Write-Host "✅ Build thành công"
    }
} else {
    Write-Host "⚠️ Không tìm thấy dotnet SDK – bỏ qua bước build"
}

# 9. Nhập commit message (hoặc tự sinh)
$commitMsg = Read-Host "✏️ Nhập nội dung commit (Enter để tự sinh)"
if ([string]::IsNullOrWhiteSpace($commitMsg)) {
    $commitMsg = "Auto commit " + (Get-Date -Format "yyyy-MM-dd HH:mm")
}

# 10. Commit
git add .
git commit -m "$commitMsg"
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Commit thất bại"
    exit 1
}

# 11. Push
Write-Host "🚀 Đang push code lên GitHub..."
git push origin main
if ($LASTEXITCODE -ne 0) {
    $answer = Read-Host "⚠️ Push thường thất bại. Có force-with-lease không? (y/n)"
    if ($answer -eq "y") {
        git push origin main --force-with-lease
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Force push thất bại"
            exit 1
        }
    } else {
        Write-Host "⏹️ Huỷ force push – kết thúc script"
        exit 1
    }
}

Write-Host "✅ Sync – Build – Push THÀNH CÔNG 🎉"