#!/usr/bin/env pwsh

# ==============================================================================
# SCRIPT: git-sync.ps1 (VIP PRO VERSION)
# MỤC TIÊU: Tự động hóa Sync -> Build Test -> Push an toàn
# TÍNH NĂNG: Hỗ trợ SSH, Auto-Branch, Nhận diện Codespaces, Silent Build
# ==============================================================================

# 0. Cấu hình SSH Di động (Vượt rào máy công ty)
$sshKeyPath = Join-Path $PSScriptRoot "ssh_id"
if (Test-Path $sshKeyPath) {
    $env:GIT_SSH_COMMAND = "ssh -i `"$sshKeyPath`" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"
}

Write-Host "`n=======================================" -ForegroundColor Cyan
Write-Host " 🚀 GIT SYNC PRO – AUTO BUILD & PUSH " -ForegroundColor Cyan
Write-Host "=======================================`n" -ForegroundColor Cyan

# ==========================================================
# 1. Kiểm tra môi trường Git & Nhận diện Nhánh
# ==========================================================
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Lỗi: Git chưa được cài đặt hoặc chưa có trong PATH." -ForegroundColor Red
    exit 1
}

git rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Lỗi: Thư mục hiện tại không phải là Git repository." -ForegroundColor Red
    exit 1
}

# [PRO UPGRADE]: Tự động lấy tên nhánh hiện tại
$currentBranch = git branch --show-current
if ([string]::IsNullOrWhiteSpace($currentBranch)) {
    $currentBranch = "main" # Fallback an toàn
}
Write-Host "🌿 Đang làm việc trên nhánh: [$currentBranch]" -ForegroundColor Green

# ==========================================================
# 2. Xử lý Pull Code thông minh
# ==========================================================
$statusBefore = git status --porcelain
if (-not $statusBefore) {
    Write-Host "🔄 Repo sạch – Đang đồng bộ code mới nhất từ GitHub..." -ForegroundColor Magenta
    git pull --rebase origin $currentBranch
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Pull thất bại – Có conflict, vui lòng giải quyết thủ công!" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "✏️ Phát hiện thay đổi cục bộ – Tạm bỏ qua Pull để bảo vệ code của bạn." -ForegroundColor DarkGray
}

# ==========================================================
# 3. Kiểm tra thay đổi & Chặn rác
# ==========================================================
$status = git status --porcelain
if (-not $status) {
    Write-Host "✅ Không có thay đổi nào mới để Push. Đi pha cafe thôi!" -ForegroundColor Green
    exit 0
}

Write-Host "`n📂 Các file đã sửa đổi:" -ForegroundColor Yellow
$status | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

# Chặn file rác (hỗ trợ cả đường dẫn Windows \ và Unix /)
if ($status -match 'bin[/\\]|obj[/\\]') {
    Write-Host "`n❌ CẢNH BÁO: Phát hiện thư mục bin/ hoặc obj/ lọt vào Git!" -ForegroundColor Red
    Write-Host "👉 Hãy thêm 'bin/' và 'obj/' vào file .gitignore trước khi tiếp tục." -ForegroundColor Yellow
    exit 1
}

# ==========================================================
# 4. Nhận diện Framework & Môi trường Build
# ==========================================================
Write-Host "`n🔍 Đang kiểm tra môi trường Build..." -ForegroundColor Cyan

function Get-CsprojTfms([string]$projPath) {
    [xml]$x = Get-Content -LiteralPath $projPath
    $list = [System.Collections.Generic.List[string]]::new()
    foreach ($pg in $x.Project.PropertyGroup) {
        if ($pg.TargetFrameworks) {
            foreach ($p in ($pg.TargetFrameworks -split ';')) {
                $t = $p.Trim()
                if ($t) { [void]$list.Add($t) }
            }
        }
        if ($pg.TargetFramework) { [void]$list.Add($pg.TargetFramework.Trim()) }
    }
    return ,@($list | Select-Object -Unique)
}

function Get-MauiAndroidCsproj {
    $all = Get-ChildItem -Path . -Recurse -Filter *.csproj -File | Where-Object {
        $_.FullName -notmatch '[\\/](obj|bin|packages|node_modules)[\\/]'
    } | Sort-Object FullName
    foreach ($c in $all) {
        if ($c.Name -match '\.Tests\.') { continue }
        $raw = Get-Content -LiteralPath $c.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $raw) { continue }
        $tfms = Get-CsprojTfms $c.FullName
        if (-not ($tfms | Where-Object { $_ -match 'android' })) { continue }
        if ($raw -match '<UseMaui>\s*true\s*</UseMaui>' -or $raw -match 'net[0-9.]+-android') { return $c }
    }
    foreach ($c in $all) {
        if ($c.Name -match '\.Tests\.') { continue }
        $tfms = Get-CsprojTfms $c.FullName
        if ($tfms | Where-Object { $_ -match 'android' }) { return $c }
    }
    return $null
}

$projectFile = Get-MauiAndroidCsproj
if (-not $projectFile) {
    $projectFile = Get-ChildItem -Path . -Recurse -Filter *.csproj -File |
        Where-Object { $_.FullName -notmatch '[\\/](obj|bin)[\\/]' } |
        Select-Object -First 1
}

$buildTarget = ""
if ($projectFile) {
    try {
        $tfms = Get-CsprojTfms $projectFile.FullName
        $foundTfm = $tfms | Where-Object { $_ -match 'android' } | Select-Object -First 1
        if ($foundTfm) {
            $buildTarget = $foundTfm.Trim()
            Write-Host "📱 Phát hiện MAUI / Android Target: $buildTarget" -ForegroundColor Gray
        } else {
            Write-Host "💻 Project .NET (không dùng -f android)." -ForegroundColor Gray
        }
    } catch {}
}

# ==========================================================
# 5. Build Kiểm thử (Có nhận diện Codespaces)
# ==========================================================
if ($env:CODESPACES -eq "true") {
    # Đang chạy trên GitHub Web Codespaces -> Bỏ qua Build cục bộ
    Write-Host "☁️  Môi trường: Codespaces (Thiếu Android SDK cục bộ)." -ForegroundColor Yellow
    Write-Host "👉 Tự động bỏ qua Build Test. Việc Build sẽ giao cho GitHub Actions!" -ForegroundColor Green
}
elseif (Get-Command dotnet -ErrorAction SilentlyContinue) {
    if (-not $projectFile) {
        Write-Host "⚠️ Không tìm thấy .csproj – Bỏ qua build kiểm tra." -ForegroundColor DarkGray
    } else {
    Write-Host "💻 Môi trường: Local. Đang build kiểm tra cú pháp..." -ForegroundColor Cyan
    if ([string]::IsNullOrWhiteSpace($buildTarget)) {
        dotnet build $projectFile.FullName -v q --nologo
    } else {
        dotnet build $projectFile.FullName -f $buildTarget -v q --nologo
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Host "`n❌ LỖI CODE: Quá trình Build thất bại!" -ForegroundColor Red
        $answer = Read-Host "⚠️ Bạn có muốn BỎ QUA lỗi và cứ thế Push lên không? (y/n)"
        if ($answer -ne "y") {
            Write-Host "⏹️ Đã dừng script để bạn sửa code." -ForegroundColor DarkGray
            exit 1
        }
    } else {
        Write-Host "✅ Code chuẩn Không có lỗi cú pháp!" -ForegroundColor Green
    }
    }
} else {
    Write-Host "⚠️ Không tìm thấy .NET SDK cục bộ – Bỏ qua bước Build test." -ForegroundColor DarkGray
}

# ==========================================================
# 6. Commit an toàn
# ==========================================================
Write-Host "`n✍️  Đóng gói Commit..." -ForegroundColor Cyan
$commitMsg = Read-Host "👉 Nhập nội dung cập nhật (Nhấn Enter để dùng giờ hệ thống)"
if ([string]::IsNullOrWhiteSpace($commitMsg)) {
    $commitMsg = "Cập nhật lúc " + (Get-Date -Format "HH:mm dd/MM/yyyy")
}

git add .
git commit -m "$commitMsg" | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Đóng gói (Commit) thất bại." -ForegroundColor Red
    exit 1
}

# ==========================================================
# 7. Push Code
# ==========================================================
Write-Host "`n🚀 Đang phóng code lên GitHub ($currentBranch)..." -ForegroundColor Cyan
git push origin $currentBranch

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n⚠️ GitHub từ chối nhận code (Thường do xung đột lịch sử)." -ForegroundColor Yellow
    $answer = Read-Host "👉 Bạn có muốn ép đẩy (Force-with-lease) không? (y/n)"
    if ($answer -eq "y") {
        Write-Host "🔥 Đang ép đẩy dữ liệu..." -ForegroundColor DarkGray
        git push origin $currentBranch --force-with-lease
    } else {
        Write-Host "⏹️ Huỷ thao tác Push. Bạn hãy kiểm tra lại git log." -ForegroundColor Red
        exit 1
    }
}

# ==========================================================
# 8. Hoàn tất
# ==========================================================
Write-Host "`n🎉 ĐỒNG BỘ THÀNH CÔNG!" -ForegroundColor Green
# Phát âm thanh ting ting
Write-Host "`a" -NoNewline