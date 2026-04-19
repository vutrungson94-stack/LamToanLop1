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

function Get-XmlSdkText {
    param($Node)
    if ($null -eq $Node) { return '' }
    if ($Node -is [string]) { return $Node.Trim() }
    if ($Node -is [System.Xml.XmlElement]) { return $Node.InnerText.Trim() }
    # Một thẻ trùng tên → PS trả về mảng; KHÔNG được [string]@(...) (gây "net10.0-android TargetFrameworks")
    if ($Node -is [System.Array] -or ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string])) {
        $first = @($Node) | Select-Object -First 1
        if ($first -is [System.Xml.XmlElement]) { return $first.InnerText.Trim() }
        return ([string]$first).Trim()
    }
    return ([string]$Node).Trim()
}

function Get-CsprojTfms([string]$projPath) {
    [xml]$x = Get-Content -LiteralPath $projPath
    $list = [System.Collections.Generic.List[string]]::new()
    foreach ($pg in @($x.Project.PropertyGroup)) {
        # Cùng một PropertyGroup có thể có NHIỀU <TargetFrameworks> — phải lặp từng XmlElement
        if ($null -ne $pg.TargetFrameworks) {
            foreach ($tfmNode in @($pg.TargetFrameworks)) {
                $blob = if ($tfmNode -is [System.Xml.XmlElement]) { $tfmNode.InnerText.Trim() } else { ([string]$tfmNode).Trim() }
                if (-not $blob) { continue }
                foreach ($p in ($blob -split ';')) {
                    $t = $p.Trim()
                    if (-not $t) { continue }
                    if ($t -match '^\$\(') { continue }
                    # Một đoạn có thể vô tình ghép 2 TFM bằng khoảng trắng
                    foreach ($piece in ($t -split '\s+', [System.StringSplitOptions]::RemoveEmptyEntries)) {
                        if ($piece -match '^\$\(') { continue }
                        [void]$list.Add($piece)
                    }
                }
            }
        }
        if ($null -ne $pg.TargetFramework) {
            foreach ($tfNode in @($pg.TargetFramework)) {
                $one = if ($tfNode -is [System.Xml.XmlElement]) { $tfNode.InnerText.Trim() } else { ([string]$tfNode).Trim() }
                if (-not $one -or $one -match '^\$\(') { continue }
                foreach ($piece in ($one -split '\s+', [System.StringSplitOptions]::RemoveEmptyEntries)) {
                    [void]$list.Add($piece)
                }
            }
        }
    }
    return ,@($list | Select-Object -Unique)
}

function Get-AndroidTfmMoniker {
    param([string[]]$Tfms)
    foreach ($raw in @($Tfms)) {
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        $m = [regex]::Match($raw, 'net[0-9]+\.[0-9]+-android[0-9.]*')
        if ($m.Success) { return $m.Value }
    }
    return $null
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

function Invoke-SyncLocalPublishMenu {
    param(
        [System.IO.FileInfo]$ProjectFile,
        [string[]]$Tfms
    )
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        Write-Host "⚠️ Không có dotnet SDK — bỏ qua xuất bản cục bộ." -ForegroundColor Yellow
        return
    }
    if (-not $ProjectFile) {
        Write-Host "⚠️ Không tìm thấy .csproj phù hợp — bỏ qua xuất bản cục bộ." -ForegroundColor Yellow
        return
    }

    $androidTfm = Get-AndroidTfmMoniker $Tfms
    $iosTfm = [string](Get-XmlSdkText ($Tfms | Where-Object { $_ -match 'net[0-9.]+-ios' -and $_ -notmatch 'maccatalyst' } | Select-Object -First 1))
    $macTf = [string](Get-XmlSdkText ($Tfms | Where-Object { $_ -match 'maccatalyst' } | Select-Object -First 1))
    $isMac = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)

    Write-Host "`n📦 Xuất bản cục bộ — CHỈ lưu trên máy (thư mục local-publish/, không đẩy GitHub):" -ForegroundColor Cyan
    Write-Host "  [0] Không xuất"
    Write-Host "  [1] Android — APK"
    Write-Host "  [2] Android — AAB (Google Play)"
    if ($iosTfm) {
        if ($isMac) { Write-Host "  [3] iOS — $iosTfm" }
        else { Write-Host "  [3] iOS — (chỉ trên macOS + Xcode)" -ForegroundColor DarkGray }
    }
    if ($macTf) {
        if ($isMac) { Write-Host "  [4] Mac Catalyst — $macTf" }
        else { Write-Host "  [4] Mac Catalyst — (chỉ trên macOS)" -ForegroundColor DarkGray }
    }
    $pick = Read-Host "👉 Chọn (Enter = 0)"
    if ([string]::IsNullOrWhiteSpace($pick)) { $pick = "0" }

    $root = Join-Path $PSScriptRoot "local-publish"
    switch ($pick) {
        "0" { return }
        "1" {
            if ([string]::IsNullOrWhiteSpace($androidTfm)) {
                Write-Host "❌ Project không có TFM Android." -ForegroundColor Red
                return
            }
            $out = Join-Path $root "android-apk"
            New-Item -ItemType Directory -Path $out -Force | Out-Null
            Write-Host "⏳ Đang xuất APK → $out ..." -ForegroundColor Gray
            dotnet publish $ProjectFile.FullName -c Release -f $androidTfm -p:AndroidPackageFormat=apk -o $out --nologo
            if ($LASTEXITCODE -eq 0) { Write-Host "✅ Hoàn tất APK." -ForegroundColor Green }
        }
        "2" {
            if ([string]::IsNullOrWhiteSpace($androidTfm)) {
                Write-Host "❌ Project không có TFM Android." -ForegroundColor Red
                return
            }
            $out = Join-Path $root "android-aab"
            New-Item -ItemType Directory -Path $out -Force | Out-Null
            Write-Host "⏳ Đang xuất AAB → $out ..." -ForegroundColor Gray
            dotnet publish $ProjectFile.FullName -c Release -f $androidTfm -p:AndroidPackageFormat=aab -o $out --nologo
            if ($LASTEXITCODE -eq 0) { Write-Host "✅ Hoàn tất AAB." -ForegroundColor Green }
        }
        "3" {
            if (-not $iosTfm) { Write-Host "❌ Không có TFM iOS trong project." -ForegroundColor Red; return }
            if (-not $isMac) {
                Write-Host "❌ Build iOS cần chạy script trên macOS." -ForegroundColor Red
                return
            }
            $out = Join-Path $root "ios"
            New-Item -ItemType Directory -Path $out -Force | Out-Null
            Write-Host "⏳ Đang publish iOS → $out ..." -ForegroundColor Gray
            dotnet publish $ProjectFile.FullName -c Release -f $iosTfm -p:TargetFrameworks=$iosTfm -o $out --nologo
            if ($LASTEXITCODE -eq 0) { Write-Host "✅ Hoàn tất iOS." -ForegroundColor Green }
        }
        "4" {
            if (-not $macTf) { Write-Host "❌ Không có TFM Mac Catalyst." -ForegroundColor Red; return }
            if (-not $isMac) {
                Write-Host "❌ Build Mac Catalyst cần chạy trên macOS." -ForegroundColor Red
                return
            }
            $out = Join-Path $root "maccatalyst"
            New-Item -ItemType Directory -Path $out -Force | Out-Null
            Write-Host "⏳ Đang publish Mac Catalyst → $out ..." -ForegroundColor Gray
            dotnet publish $ProjectFile.FullName -c Release -f $macTf -p:TargetFrameworks=$macTf -o $out --nologo
            if ($LASTEXITCODE -eq 0) { Write-Host "✅ Hoàn tất Mac Catalyst." -ForegroundColor Green }
        }
        default { Write-Host "❌ Lựa chọn không hợp lệ." -ForegroundColor Red }
    }
}

function Unstage-BuildArtifacts {
    $staged = @(git diff --cached --name-only --diff-filter=ACM 2>$null)
    foreach ($line in $staged) {
        if (-not $line) { continue }
        if ($line -match '\.(apk|aab|ipa)$|\.app[/\\]') {
            git reset HEAD -- $line 2>$null
            Write-Host "⚠️ Đã gỡ khỏi commit (chỉ lưu máy): $line" -ForegroundColor DarkYellow
        }
    }
}

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

# Project / TFMs (build kiểm tra + menu xuất bản cục bộ)
$projectFile = Get-MauiAndroidCsproj
if (-not $projectFile) {
    $projectFile = Get-ChildItem -Path . -Recurse -Filter *.csproj -File |
        Where-Object { $_.FullName -notmatch '[\\/](obj|bin)[\\/]' } |
        Select-Object -First 1
}
$tfmsAll = @()
if ($projectFile) {
    try { $tfmsAll = @(Get-CsprojTfms $projectFile.FullName) } catch {}
}

# ==========================================================
# 3. Kiểm tra thay đổi & Chặn rác
# ==========================================================
$status = git status --porcelain
if (-not $status) {
    Write-Host "✅ Không có thay đổi nào mới để commit / Push." -ForegroundColor Green
    $onlyLocal = Read-Host "📦 Chỉ xuất bản cục bộ (APK / AAB / Apple) lưu trên máy? (y/N)"
    if ($onlyLocal -match '^[yY]') {
        Invoke-SyncLocalPublishMenu -ProjectFile $projectFile -Tfms $tfmsAll
    }
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

$buildTarget = ""
if ($projectFile) {
    $buildTarget = Get-AndroidTfmMoniker $tfmsAll
    if ($buildTarget) {
        Write-Host "📱 Phát hiện MAUI / Android Target: $buildTarget" -ForegroundColor Gray
    } else {
        Write-Host "💻 Project .NET (không dùng -f android)." -ForegroundColor Gray
    }
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
        dotnet build $projectFile.FullName -f ([string]$buildTarget) -v q --nologo
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
# 5b. Xuất bản cục bộ (tuỳ chọn) — chỉ thư mục local-publish/, không đẩy GitHub
# ==========================================================
if ($env:CODESPACES -ne "true") {
    $doLocal = Read-Host "`n📦 Xuất bản cục bộ (APK/AAB/Apple) chỉ lưu máy trước khi commit? (y/N)"
    if ($doLocal -match '^[yY]') {
        Invoke-SyncLocalPublishMenu -ProjectFile $projectFile -Tfms $tfmsAll
    }
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
Unstage-BuildArtifacts
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