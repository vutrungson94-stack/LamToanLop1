#!/usr/bin/env pwsh

# ==============================================================================
# SCRIPT: git-sync.ps1
# MỤC TIÊU: Tự động hóa quy trình Pull -> Build -> Commit -> Push
# HỖ TRỢ: Chạy trên mọi máy (Cá nhân & Công ty không có quyền Admin)
# ==============================================================================

# 0. Cấu hình SSH Di động (Giải quyết vấn đề máy công ty khóa quyền Admin/Service)
# Tự tìm file ssh_id nằm cùng thư mục với script
$sshKeyPath = Join-Path $PSScriptRoot "ssh_id"
if (Test-Path $sshKeyPath) {
    # Ép Git dùng file key này trực tiếp, không cần bật dịch vụ ssh-agent của Windows
    $env:GIT_SSH_COMMAND = "ssh -i `"$sshKeyPath`" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"
}

Write-Host "`n==============================" -ForegroundColor Cyan
Write-Host "  Git Tự Động Sync – Build – Push  " -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan

# 1. Tự động nhận diện Framework từ file .csproj
$projectFile = Get-ChildItem -Filter *.csproj | Select-Object -First 1
$androidFramework = ""

if ($projectFile) {
    try {
        [xml]$projectXml = Get-Content $projectFile.FullName -ErrorAction SilentlyContinue
        # Tìm trong danh sách TargetFrameworks (số nhiều)
        $androidFramework = ($projectXml.Project.PropertyGroup.TargetFrameworks -split ';' | Select-String -Pattern "net9.0-android")
        
        # Nếu không thấy (có thể dùng số ít TargetFramework)
        if (-not $androidFramework) {
            $androidFramework = $projectXml.Project.PropertyGroup.TargetFramework | Select-String -Pattern "net9.0-android"
        }
    } catch {
        Write-Host "⚠️ Lỗi đọc file .csproj, sử dụng giá trị mặc định." -ForegroundColor Yellow
    }
}

# Nếu không nhận diện được bản net9, mặc định về net9.0-android
if ($androidFramework) {
    Write-Host "🔍 Đã tự động nhận diện Framework: $androidFramework" -ForegroundColor Green
} else {
    $androidFramework = "net9.0-android" 
    Write-Host "⚠️ Không tự nhận diện được, sử dụng mặc định: $androidFramework" -ForegroundColor Yellow
}

# 2. Kiểm tra môi trường Git
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Lỗi: Git chưa được cài đặt hoặc chưa có trong PATH." -ForegroundColor Red
    exit 1
}

git rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Lỗi: Thư mục hiện tại không phải là Git repository." -ForegroundColor Red
    exit 1
}

# 3. Xử lý Pull code (Chỉ pull khi repo đang sạch để tránh conflict tự động)
$statusBefore = git status --porcelain
if (-not $statusBefore) {
    Write-Host "🔄 Repo sạch – đang pull code mới nhất từ GitHub..." -ForegroundColor Magenta
    git pull --rebase origin main
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Pull thất bại – vui lòng kiểm tra conflict thủ công!" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "✏️ Phát hiện có thay đổi chưa commit – bỏ qua bước pull để tránh conflict." -ForegroundColor Gray
}

# 4. Kiểm tra thay đổi sau khi sửa code
$status = git status --porcelain
if (-not $status) {
    Write-Host "✅ Không có thay đổi nào cần đồng bộ." -ForegroundColor Green
    exit 0
}

Write-Host "📂 Các file đã thay đổi:" -ForegroundColor Yellow
Write-Host $status

# 5. Chặn các file rác (bin/obj) lọt vào commit
$forbidden = $status | Select-String -Pattern "bin/|obj/"
if ($forbidden) {
    Write-Host "❌ Lỗi: Phát hiện file trong bin/ hoặc obj/ chưa được ignore. Commit bị chặn!" -ForegroundColor Red
    exit 1
}

# 6. Build thử nghiệm trước khi Push
Write-Host "`n🔧 Đang build kiểm tra lỗi ($androidFramework)..." -ForegroundColor Cyan
if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    dotnet build -f $androidFramework
    if ($LASTEXITCODE -ne 0) {
        $answer = Read-Host "⚠️ Build thất bại. Bạn có muốn BỎ QUA lỗi để tiếp tục Push không? (y/n)"
        if ($answer -ne "y") {
            Write-Host "⏹️ Đã dừng script theo yêu cầu của bạn." -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "✅ Build thành công. Sẵn sàng Push." -ForegroundColor Green
    }
} else {
    Write-Host "⚠️ Không tìm thấy dotnet SDK – bỏ qua bước build." -ForegroundColor Yellow
}

# 7. Thực hiện Commit
$commitMsg = Read-Host "`n✏️ Nhập nội dung commit (Nhấn Enter để tự sinh tên)"
if ([string]::IsNullOrWhiteSpace($commitMsg)) {
    $commitMsg = "Auto sync " + (Get-Date -Format "yyyy-MM-dd HH:mm")
}

git add .
git commit -m "$commitMsg"
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Commit thất bại." -ForegroundColor Red
    exit 1
}

# 8. Thực hiện Push
Write-Host "🚀 Đang push code lên GitHub..." -ForegroundColor Cyan
git push origin main
if ($LASTEXITCODE -ne 0) {
    $answer = Read-Host "⚠️ Push thường thất bại. Bạn có muốn dùng Force-with-lease không? (y/n)"
    if ($answer -eq "y") {
        git push origin main --force-with-lease
    } else {
        Write-Host "⏹️ Huỷ bỏ thao tác Push." -ForegroundColor Red
        exit 1
    }
}

Write-Host "`n✅ Sync – Build – Push THÀNH CÔNG 🎉" -ForegroundColor Green