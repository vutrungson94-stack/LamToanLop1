#!/usr/bin/env pwsh

# ==============================================================================
# SCRIPT: git-build.ps1 (VIP PRO VERSION)
# MỤC TIÊU: Auto CI Build Tool cho MAUI Android (Khớp chuẩn Enterprise)
# TÍNH NĂNG: Tracking Job ID chính xác 100%, Auto-Branch, Flatten Artifacts, AAB Support
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
# 1. Locate GitHub CLI & Môi trường Git
# ==========================================================
$ghExe = Join-Path $PSScriptRoot "gh.exe"
$gh = if (Test-Path $ghExe) { $ghExe } elseif (Get-Command gh -ErrorAction SilentlyContinue) { "gh" } else { $null }

if (-not $gh) {
    Write-Host "❌ Lỗi: Không tìm thấy GitHub CLI (gh.exe hoặc gh)" -ForegroundColor Red
    exit 1
}

& $gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Lỗi: Chưa đăng nhập GitHub CLI" -ForegroundColor Red
    Write-Host "👉 Chạy lệnh: gh auth login --scopes workflow" -ForegroundColor Yellow
    exit 1
}

# Tự động lấy tên nhánh hiện tại để kích hoạt đúng nhánh trên GitHub
$currentBranch = "main"
if (Get-Command git -ErrorAction SilentlyContinue) {
    $branch = git branch --show-current 2>$null
    if (-not [string]::IsNullOrWhiteSpace($branch)) { $currentBranch = $branch }
}
Write-Host "🌿 Kích hoạt Build trên nhánh: [$currentBranch]" -ForegroundColor Green

# ==========================================================
# 2. Tự động dò tìm Workflow
# ==========================================================
Write-Host "🔍 Đang dò tìm workflow hỗ trợ dispatch..." -ForegroundColor Cyan

try {
    $workflows = & $gh workflow list --json name,id,state,hasWorkflowDispatch | ConvertFrom-Json
    $dispatchable = $workflows | Where-Object { $_.hasWorkflowDispatch -eq $true -and $_.state -eq "active" }
} catch {
    Write-Host "❌ Lỗi: Không thể lấy danh sách workflow từ GitHub." -ForegroundColor Red
    exit 1
}

if (-not $dispatchable -or $dispatchable.Count -eq 0) {
    Write-Host "❌ Không tìm thấy workflow nào có 'workflow_dispatch'." -ForegroundColor Red
    exit 1
}

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
# 3. Kích hoạt Workflow & Bắt chính xác Run ID mới
# ==========================================================
Write-Host "`n🚀 Đang kích hoạt workflow: $($selected.name)..." -ForegroundColor Cyan

# Lấy ID của lần chạy gần nhất TRƯỚC KHI trigger
$lastRunId = (& $gh run list --workflow $selected.id --limit 1 --json databaseId | ConvertFrom-Json).databaseId

# Trigger workflow với đúng nhánh hiện tại
& $gh workflow run $selected.id --ref $currentBranch
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Không trigger được workflow." -ForegroundColor Red
    exit 1
}

Write-Host "⏳ Đang quét GitHub để bắt ID tiến trình mới..." -ForegroundColor Gray
$newRunId = $null

# Vòng lặp quét liên tục (tối đa 15 lần ~ 30 giây) để tìm ID mới
for ($i = 0; $i -lt 15; $i++) {
    Start-Sleep -Seconds 2
    $currentRunId = (& $gh run list --workflow $selected.id --limit 1 --json databaseId | ConvertFrom-Json).databaseId
    
    if ($currentRunId -ne $lastRunId -and $currentRunId -ne $null) {
        $newRunId = $currentRunId
        break
    }
}

if (-not $newRunId) {
    Write-Host "⚠️ Không bắt được tín hiệu tiến trình mới, chuyển sang chế độ theo dõi mặc định." -ForegroundColor Yellow
    & $gh run watch --exit-status
} else {
    Write-Host "🎯 Đã bắt được tiến trình mới (ID: $newRunId). Bắt đầu theo dõi!" -ForegroundColor Green
    & $gh run watch $newRunId --exit-status
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n❌ Build thất bại! Vui lòng kiểm tra log trên GitHub." -ForegroundColor Red
    exit 1
}

# ==========================================================
# 4. Tải và Xử lý Artifacts (Sạch sẽ & Gọn gàng)
# ==========================================================
$dir = "apk-output"

if (Test-Path $dir) {
    Write-Host "`n🧹 Đang dọn dẹp thư mục chứa bản build cũ..." -ForegroundColor Gray
    Remove-Item -Path "$dir\*" -Recurse -Force -ErrorAction SilentlyContinue
} else {
    New-Item -ItemType Directory -Path $dir | Out-Null
}

Write-Host "📦 Đang tải file Release (APK/AAB) về máy..." -ForegroundColor Cyan
& $gh run download --dir $dir

# [PRO UPGRADE]: Đưa tất cả file .apk và .aab ra ngoài thư mục gốc, xóa các thư mục con rác do GitHub tạo ra
Get-ChildItem -Path $dir -Recurse -File -Include *.apk,*.aab | Move-Item -Destination $dir -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path $dir -Directory | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# ==========================================================
# 5. Kiểm tra File & Chữ ký Keystore
# ==========================================================
function Test-ApkSigned {
    param ([string]$ApkPath)
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ApkPath)
        $isSigned = $false
        foreach ($entry in $zip.Entries) {
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

$files = Get-ChildItem -Path $dir -Filter *.* | Where-Object { $_.Extension -match '\.apk|\.aab' }
$unsignedFound = $false

if ($files.Count -eq 0) {
    Write-Host "⚠️ Lỗi: Không tìm thấy file .apk hoặc .aab nào trong dữ liệu tải về!" -ForegroundColor Yellow
} else {
    Write-Host "`n🔎 Phân tích File Cài đặt & Chữ ký:" -ForegroundColor Cyan
    foreach ($f in $files) {
        if ($f.Extension -eq ".aab") {
            Write-Host "  ⭐ PLAY STORE : $($f.Name) (Android App Bundle)" -ForegroundColor Magenta
        }
        elseif (Test-ApkSigned $f.FullName) {
            Write-Host "  ✅ SIGNED     : $($f.Name)" -ForegroundColor Green
        } 
        else {
            Write-Host "  ⚠️ UNSIGNED   : $($f.Name)" -ForegroundColor Yellow
            $unsignedFound = $true
        }
    }
}

if ($unsignedFound) {
    Write-Host "`n🚫 CẢNH BÁO: Tồn tại APK chưa ký (Unsigned). Chỉ dùng để test trên máy ảo!" -ForegroundColor Red
}

# ==========================================================
# 6. Hoàn tất
# ==========================================================
Write-Host "`n🎉 QUÁ TRÌNH TẢI VỀ HOÀN TẤT!" -ForegroundColor Green
Write-Host "📂 File nằm tại: $((Resolve-Path $dir).Path)" -ForegroundColor Cyan

# Phát âm báo & Mở thư mục
Write-Host "`a" -NoNewline
if ($IsWindows) { explorer.exe $((Resolve-Path $dir).Path) }