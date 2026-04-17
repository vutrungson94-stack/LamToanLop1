#!/usr/bin/env pwsh

# ==============================================================================
# SCRIPT: git-build.ps1 (PRO VERSION)
# MỤC TIÊU: Auto CI Build Tool cho MAUI Android
# ==============================================================================

# 0. Cấu hình SSH Di động (Vượt rào máy công ty)
$sshKeyPath = Join-Path $PSScriptRoot "ssh_id"
if (Test-Path $sshKeyPath) {
    $env:GIT_SSH_COMMAND = "ssh -i `"$sshKeyPath`" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"
}

Write-Host "`n==============================" -ForegroundColor Cyan
Write-Host "   gbuild – Auto CI Build Tool (PRO)   " -ForegroundColor Cyan
Write-Host "==============================`n" -ForegroundColor Cyan

# ==========================================================
# 1. Locate GitHub CLI (Hỗ trợ đa nền tảng)
# ==========================================================
$ghExe = Join-Path $PSScriptRoot "gh.exe"
$gh = if (Test-Path $ghExe) { $ghExe } elseif (Get-Command gh -ErrorAction SilentlyContinue) { "gh" } else { $null }

if (-not $gh) {
    Write-Host "❌ Lỗi: Không tìm thấy GitHub CLI (gh.exe hoặc gh)" -ForegroundColor Red
    exit 1
}

# ==========================================================
# 2. Check GitHub authentication
# ==========================================================
& $gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Lỗi: Chưa đăng nhập GitHub CLI" -ForegroundColor Red
    Write-Host "👉 Hãy chạy: gh auth login --scopes workflow" -ForegroundColor Yellow
    exit 1
}

# ==========================================================
# 3. Tự động dò tìm Workflow (Chỉ lấy loại chạy thủ công)
# ==========================================================
Write-Host "🔍 Đang dò tìm workflow hỗ trợ dispatch..." -ForegroundColor Cyan

# Thêm try-catch để bẫy lỗi mạng hoặc lỗi JSON
try {
    $workflows = & $gh workflow list --json name,id,state,hasWorkflowDispatch | ConvertFrom-Json
    $dispatchable = $workflows | Where-Object { $_.hasWorkflowDispatch -eq $true -and $_.state -eq "active" }
} catch {
    Write-Host "❌ Lỗi: Không thể lấy danh sách workflow từ GitHub." -ForegroundColor Red
    exit 1
}

if (-not $dispatchable -or $dispatchable.Count -eq 0) {
    Write-Host "❌ Không tìm thấy workflow nào có 'workflow_dispatch' đang hoạt động." -ForegroundColor Red
    exit 1
}

# ==========================================================
# 4. Lựa chọn Workflow
# ==========================================================
if ($dispatchable.Count -eq 1) {
    $selected = $dispatchable[0]
    Write-Host "✅ Tự động chọn workflow: $($selected.name)" -ForegroundColor Green
} else {
    Write-Host "`n📋 Có nhiều workflow. Vui lòng chọn:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $dispatchable.Count; $i++) {
        Write-Host "  [$i] $($dispatchable[$i].name)"
    }

    $choice = Read-Host "`n👉 Nhập số workflow muốn chạy"
    if (-not ($choice -as [int] -ne $null) -or $choice -lt 0 -or $choice -ge $dispatchable.Count) {
        Write-Host "❌ Lựa chọn không hợp lệ!" -ForegroundColor Red
        exit 1
    }
    $selected = $dispatchable[$choice]
}

# ==========================================================
# 5. Kích hoạt Workflow & Xử lý "Race Condition"
# ==========================================================
Write-Host "`n🚀 Đang kích hoạt workflow: $($selected.name)..." -ForegroundColor Cyan
& $gh workflow run $selected.id

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Không trigger được workflow. Hãy kiểm tra lại file YML." -ForegroundColor Red
    exit 1
}

# [PRO UPGRADE]: Đợi GitHub khởi tạo tiến trình để tránh Watch nhầm build cũ
Write-Host "⏳ Đợi GitHub khởi tạo tiến trình (5s)..." -ForegroundColor Gray
Start-Sleep -Seconds 5

# ==========================================================
# 6. Theo dõi tiến trình CI
# ==========================================================
Write-Host "👁️ Đang theo dõi tiến trình build (Bấm Ctrl+C để thoát theo dõi)..." -ForegroundColor Yellow
& $gh run watch --exit-status

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Build thất bại! Vui lòng kiểm tra log trên GitHub." -ForegroundColor Red
    exit 1
}

# ==========================================================
# 7. Dọn dẹp & Tải Artifacts
# ==========================================================
$dir = "apk-output"

# [PRO UPGRADE]: Xóa sạch thư mục cũ để không bị lẫn lộn file
if (Test-Path $dir) {
    Write-Host "🧹 Đang dọn dẹp thư mục chứa bản build cũ..." -ForegroundColor Gray
    Remove-Item -Path "$dir\*" -Recurse -Force -ErrorAction SilentlyContinue
} else {
    New-Item -ItemType Directory -Path $dir | Out-Null
}

Write-Host "📦 Đang tải file APK/AAB về máy..." -ForegroundColor Cyan
& $gh run download --dir $dir

# ==========================================================
# 8. Kiểm tra Chữ ký APK (Nâng cao)
# ==========================================================
function Test-ApkSigned {
    param ([string]$ApkPath)
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ApkPath)
        $isSigned = $false

        foreach ($entry in $zip.Entries) {
            # [PRO UPGRADE]: Kiểm tra cả RSA, DSA và SF (bao quát các chuẩn chữ ký cũ và mới)
            if ($entry.FullName -match "^META-INF/.*\.(RSA|DSA|SF)$") {
                $isSigned = $true
                break
            }
        }
        $zip.Dispose()
        return $isSigned
    } catch {
        return $false
    }
}

$apks = Get-ChildItem -Path $dir -Recurse -Filter *.apk
$unsignedFound = $false

if ($apks.Count -eq 0) {
    Write-Host "⚠️ Không tìm thấy file .apk nào trong dữ liệu tải về!" -ForegroundColor Yellow
} else {
    Write-Host "`n🔎 Đang kiểm tra chữ ký bảo mật (Keystore):" -ForegroundColor Cyan
    foreach ($apk in $apks) {
        if (Test-ApkSigned $apk.FullName) {
            Write-Host "  ✅ SIGNED   : $($apk.Name)" -ForegroundColor Green
        } else {
            Write-Host "  ⚠️ UNSIGNED : $($apk.Name)" -ForegroundColor Yellow
            $unsignedFound = $true
        }
    }
}

if ($unsignedFound) {
    Write-Host "`n🚫 CẢNH BÁO: Phát hiện APK chưa ký (Unsigned). File này không thể upload lên Google Play!" -ForegroundColor Red
}

# ==========================================================
# 9. Hoàn tất & Mở thư mục
# ==========================================================
Write-Host "`n🎉 BUILD VÀ TẢI VỀ HOÀN TẤT!" -ForegroundColor Green
Write-Host "📂 Đường dẫn: $((Resolve-Path $dir).Path)" -ForegroundColor Cyan

# [PRO UPGRADE]: Phát âm thanh báo hiệu hoàn thành
Write-Host "`a" -NoNewline

if ($IsWindows) {
    explorer.exe $dir
}