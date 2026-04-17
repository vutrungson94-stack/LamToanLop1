#!/usr/bin/env pwsh

Write-Host "`n=============================="
Write-Host "   gbuild – Auto CI Build Tool"
Write-Host "==============================`n"

# ==========================================================
# 1. Locate GitHub CLI (ưu tiên gh.exe cùng thư mục)
# ==========================================================
$ghExe = Join-Path $PSScriptRoot "gh.exe"

if (Test-Path $ghExe) {
    $gh = $ghExe
}
elseif (Get-Command gh -ErrorAction SilentlyContinue) {
    $gh = "gh"
}
else {
    Write-Host "❌ Không tìm thấy GitHub CLI (gh.exe hoặc gh)" -ForegroundColor Red
    exit 1
}

# ==========================================================
# 2. Check GitHub authentication
# ==========================================================
& $gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Chưa đăng nhập GitHub CLI" -ForegroundColor Red
    Write-Host "👉 Chạy: gh auth login" -ForegroundColor Yellow
    exit 1
}

# ==========================================================
# 3. Auto-detect workflow with workflow_dispatch (SAFE)
# ==========================================================
Write-Host "🔍 Dò workflow có workflow_dispatch..." -ForegroundColor Cyan

$workflows = & $gh workflow list --json name,id,state,hasWorkflowDispatch | ConvertFrom-Json
$dispatchable = $workflows | Where-Object { $_.hasWorkflowDispatch -eq $true }

if (-not $dispatchable -or $dispatchable.Count -eq 0) {
    Write-Host "❌ Không tìm thấy workflow nào có workflow_dispatch" -ForegroundColor Red
    Write-Host "👉 Kiểm tra lại file build.yml có dòng 'workflow_dispatch:' hay không" -ForegroundColor Yellow
    exit 1
}

# ==========================================================
# 4. Select workflow (nếu nhiều hơn 1)
# ==========================================================
if ($dispatchable.Count -eq 1) {
    $selected = $dispatchable[0]
    Write-Host "✅ Tự chọn workflow: $($selected.name)" -ForegroundColor Green
}
else {
    Write-Host "`nCó nhiều workflow có thể chạy:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $dispatchable.Count; $i++) {
        Write-Host " [$i] $($dispatchable[$i].name)"
    }

    $choice = Read-Host "👉 Nhập số workflow muốn chạy"
    if (-not ($choice -as [int]) -or $choice -ge $dispatchable.Count) {
        Write-Host "❌ Lựa chọn không hợp lệ" -ForegroundColor Red
        exit 1
    }

    $selected = $dispatchable[$choice]
}

# ==========================================================
# 5. Trigger workflow
# ==========================================================
Write-Host "`n🚀 Trigger workflow: $($selected.name)" -ForegroundColor Cyan
& $gh workflow run $selected.id

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Không trigger được workflow" -ForegroundColor Red
    exit 1
}

# ==========================================================
# 6. Watch CI run
# ==========================================================
Write-Host "⏳ Đang chờ CI chạy xong..." -ForegroundColor Yellow
& $gh run watch --exit-status

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ CI thất bại – kiểm tra log trên GitHub" -ForegroundColor Red
    exit 1
}

# ==========================================================
# 7. Download artifacts
# ==========================================================
$dir = "apk-output"
if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir | Out-Null
}

Write-Host "📦 Đang tải artifact (APK / AAB)..." -ForegroundColor Cyan
& $gh run download --dir $dir

# ==========================================================
# 8. Detect APK signed / unsigned
# ==========================================================
function Test-ApkSigned {
    param ([string]$ApkPath)

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ApkPath)

        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -match "^META-INF/.*\.RSA$") {
                $zip.Dispose()
                return $true
            }
        }

        $zip.Dispose()
        return $false
    }
    catch {
        return $false
    }
}

$apks = Get-ChildItem $dir -Recurse -Filter *.apk
$unsignedFound = $false

if ($apks.Count -eq 0) {
    Write-Host "⚠️ Không tìm thấy APK nào trong artifact" -ForegroundColor Yellow
}
else {
    Write-Host "`n🔎 Kiểm tra chữ ký APK:" -ForegroundColor Cyan
    foreach ($apk in $apks) {
        if (Test-ApkSigned $apk.FullName) {
            Write-Host " ✅ SIGNED   : $($apk.Name)" -ForegroundColor Green
        }
        else {
            Write-Host " ⚠️ UNSIGNED : $($apk.Name)" -ForegroundColor Yellow
            $unsignedFound = $true
        }
    }
}

if ($unsignedFound) {
    Write-Host "`n🚫 CẢNH BÁO: APK unsigned – KHÔNG ĐƯỢC UPLOAD PLAY" -ForegroundColor Red
}

# ==========================================================
# 9. Finish
# ==========================================================
Write-Host "`n✅ BUILD HOÀN TẤT"
Write-Host "📂 File nằm tại: $((Resolve-Path $dir).Path)" -ForegroundColor Cyan

if ($IsWindows) {
    explorer.exe $dir
}
