#!/usr/bin/env pwsh

# ==============================================================================
# SCRIPT: git-build.ps1
# MỤC TIÊU: Kích hoạt GitHub Actions build APK và tải về máy
# HỖ TRỢ: Chạy trên mọi máy (Cá nhân & Công ty) - Tự thích ứng Windows/Linux
# ==============================================================================

# 0. Cấu hình SSH Di động (Giúp GitHub CLI xác thực nếu cần)
$sshKeyPath = Join-Path $PSScriptRoot "ssh_id"
if (Test-Path $sshKeyPath) {
    $env:GIT_SSH_COMMAND = "ssh -i `"$sshKeyPath`" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"
}

# 1. Xác định GitHub CLI (ưu tiên gh.exe cùng thư mục script)
$ghExePath = Join-Path $PSScriptRoot "gh.exe"

if (Test-Path $ghExePath) {
    $gh = $ghExePath
}
elseif (Get-Command gh -ErrorAction SilentlyContinue) {
    $gh = "gh"
}
else {
    Write-Host "❌ Không tìm thấy GitHub CLI (gh.exe hoặc gh)." -ForegroundColor Red
    Write-Host "👉 Hãy đặt gh.exe cùng thư mục với git-build.ps1" -ForegroundColor Yellow
    exit 1
}

Write-Host "`n==============================" -ForegroundColor Cyan
Write-Host "   Kích Hoạt Build APK Từ Xa   " -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan

# 2. Kiểm tra trạng thái đăng nhập GitHub CLI
& $gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Lỗi: Bạn chưa đăng nhập GitHub CLI hoặc Token hết hạn." -ForegroundColor Red
    Write-Host "👉 Hãy chạy lệnh: gh auth login" -ForegroundColor Yellow
    exit 1
}

# 3. Kích hoạt Workflow trên GitHub
Write-Host "🚀 Đang gửi lệnh build sang GitHub Actions..." -ForegroundColor Cyan
& $gh workflow run "Build MAUI Android APK"

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Không thể khởi động build. Kiểm tra tên Workflow trong file .yml của bạn." -ForegroundColor Red
    exit 1
}

# 4. Theo dõi tiến trình build
Write-Host "⏳ Đang đợi build hoàn tất (thường mất vài phút)..." -ForegroundColor Yellow
Write-Host "☕ Bạn có thể pha một tách cafe, script sẽ tự báo khi xong." -ForegroundColor Gray
& $gh run watch --exit-status

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Build trên GitHub Actions thất bại! Vui lòng kiểm tra log trên web GitHub." -ForegroundColor Red
    exit 1
}

# 5. Tải file APK về máy
Write-Host "`n📂 Build xong! Đang tải file APK về thư mục 'apk-output'..." -ForegroundColor Green

# Tạo thư mục output nếu chưa có
if (-not (Test-Path "apk-output")) { New-Item -ItemType Directory -Path "apk-output" | Out-Null }

& $gh run download --name android-apk --dir apk-output

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Tải APK thành công rực rỡ! Kiểm tra tại: $(Get-Location)/apk-output" -ForegroundColor Green
    
    # Mở thư mục chứa APK (chỉ áp dụng cho Windows)
    if ($gh -eq "gh.exe") { explorer.exe "apk-output" }
} else {
    Write-Host "❌ Lỗi khi tải file APK xuống máy." -ForegroundColor Red
}