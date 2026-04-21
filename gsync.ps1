#!/usr/bin/env pwsh
# ==============================================================================
#  gsync.ps1  — Đồng bộ Git (pull / commit / push).  Không build.
#  Drop vào bất kỳ repo nào, chạy được ngay.
# ==============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── SSH key tuỳ chọn ─────────────────────────────────────────────────────────
$sshKeyPath = Join-Path $PSScriptRoot 'ssh_id'
if (Test-Path $sshKeyPath) {
    $env:GIT_SSH_COMMAND = "ssh -i `"$sshKeyPath`" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"
}

Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host " 🚀  GIT SYNC — VIP PRO                  " -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════╝`n" -ForegroundColor Cyan

# ════════════════════════════════════════════════════════════════════════════
# BƯỚC 0 — Kiểm tra git, repo, branch
# ════════════════════════════════════════════════════════════════════════════
if (-not (Get-Command git -EA SilentlyContinue)) {
    Write-Host "❌ Git chưa cài hoặc không có trong PATH." -ForegroundColor Red; exit 1
}

git rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Không phải Git repository." -ForegroundColor Red; exit 1
}

$branch = git branch --show-current 2>$null
if ([string]::IsNullOrWhiteSpace($branch)) { $branch = 'main' }
Write-Host "🌿 Nhánh: [$branch]" -ForegroundColor Green

# ════════════════════════════════════════════════════════════════════════════
# BƯỚC DỌN DẸP — Xử lý file lỗi và file quá lớn
# ════════════════════════════════════════════════════════════════════════════
Write-Host "🧹 Đang quét file rác và file >90MB..." -ForegroundColor Cyan

# Lấy danh sách file lỗi
$badFiles = @(
    & git ls-files --ignored --cached --exclude-standard
    & git ls-files --cached | ForEach-Object {
        if (Test-Path $_) {
            $f = Get-Item $_
            if (-not $f.PSIsContainer -and $f.Length -gt 90mb) { $_ }
        }
    }
) | Where-Object { $_ }

# Cách kiểm tra an toàn cho mọi phiên bản PowerShell
$badCount = ($badFiles | Measure-Object).Count

if ($badCount -gt 0) {
    Write-Host "⚠️  Phát hiện $badCount file cần gỡ khỏi Git Index." -ForegroundColor Yellow
    foreach ($file in $badFiles) {
        Write-Host "   -> Đang gỡ: $file" -ForegroundColor Gray
        & git rm --cached -r -f -q "$file" 2>$null
    }
    & git commit -m "fix: cleanup large files and sdk" -q
    Write-Host "✅ Đã dọn dẹp xong bộ nhớ đệm." -ForegroundColor Green
} else {
    Write-Host "✅ Repo sạch sẽ." -ForegroundColor Green
}

# ════════════════════════════════════════════════════════════════════════════
# BƯỚC 1 — Kiểm tra file nhạy cảm TRƯỚC KHI làm gì cả
# ════════════════════════════════════════════════════════════════════════════
$BLOCKED_PATTERNS = @(
    '\.keystore$', '\.jks$',             # Android keystore
    '\.p12$', '\.pfx$',                  # Apple / Windows cert
    '\.mobileprovision$',                # Apple provisioning
    '^ssh_id$', '^ssh_id\.pub$',         # SSH key cạnh script
    '\.env$', '\.env\.',                 # Env vars (trừ .example/.template)
    'signing\.properties$',              # Signing config cục bộ
    'keystore\.properties$',             # Keystore properties
    'local\.properties$',                # Android local config
    'gh\.exe$',                          # gh CLI binary
    'local-publish[\\/]', 'apk-output[\\/]', 'publish-output[\\/]'  # Build output
)

$ALLOWED_EXCEPTIONS = @(
    '\.env\.example$', '\.env\.template$', '\.env\.sample$'
)

function Test-SensitiveFile([string]$path) {
    foreach ($allow in $ALLOWED_EXCEPTIONS) {
        if ($path -match $allow) { return $false }
    }
    foreach ($pat in $BLOCKED_PATTERNS) {
        if ($path -match $pat) { return $true }
    }
    return $false
}

# ════════════════════════════════════════════════════════════════════════════
# BƯỚC 2 — Kiểm tra .gitignore có đầy đủ không
# ════════════════════════════════════════════════════════════════════════════
$gitignorePath = Join-Path (git rev-parse --show-toplevel) '.gitignore'
if (-not (Test-Path $gitignorePath)) {
    Write-Host "⚠️  .gitignore chưa có — nhớ tạo để tránh commit nhầm file!" -ForegroundColor Yellow
}

# ════════════════════════════════════════════════════════════════════════════
# BƯỚC 3 — git pull (nếu working tree sạch)
# ════════════════════════════════════════════════════════════════════════════
$statusBefore = @(git status --porcelain 2>$null)
if (-not $statusBefore) {
    Write-Host "🔄 Working tree sạch — git pull --rebase…" -ForegroundColor Magenta
    git pull --rebase origin $branch
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Pull thất bại — giải quyết conflict rồi chạy lại." -ForegroundColor Red; exit 1
    }
} else {
    Write-Host "✏️  Có thay đổi cục bộ — bỏ qua pull." -ForegroundColor DarkGray
}

# ════════════════════════════════════════════════════════════════════════════
# BƯỚC 4 — Kiểm tra có gì để commit không
# ════════════════════════════════════════════════════════════════════════════
$status = @(git status --porcelain 2>$null)
if (-not $status) {
    Write-Host "✅ Không có gì để commit / push." -ForegroundColor Green; exit 0
}

# ════════════════════════════════════════════════════════════════════════════
# BƯỚC 5 — Hiển thị thay đổi + chặn file nguy hiểm
# ════════════════════════════════════════════════════════════════════════════
Write-Host "`n📂 Thay đổi:" -ForegroundColor Yellow
$blocked = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

foreach ($line in $status) {
    if (-not $line) { continue }
    $filePath = $line.Substring(3).Trim().Trim('"')
    $statusCode = $line.Substring(0,2).Trim()

    # Kiểm tra bin/obj
    if ($filePath -match '(^|[\\/])(bin|obj)([\\/]|$)') {
        [void]$warnings.Add($filePath)
    }

    # Kiểm tra file nhạy cảm
    if (Test-SensitiveFile $filePath) {
        [void]$blocked.Add($filePath)
        Write-Host "  🚫 [$statusCode] $filePath" -ForegroundColor Red
    } else {
        $color = switch -Regex ($statusCode) {
            '^A'  { 'Green'  }
            '^M'  { 'Cyan'   }
            '^D'  { 'Red'    }
            '^R'  { 'Yellow' }
            default { 'Gray' }
        }
        Write-Host "  [$statusCode] $filePath" -ForegroundColor $color
    }
}

# Cảnh báo bin/obj (không chặn, chỉ nhắc)
if ($warnings.Count -gt 0) {
    Write-Host "`n⚠️  Cảnh báo: Có file trong bin/ hoặc obj/ — kiểm tra .gitignore!" -ForegroundColor Yellow
    $warnings | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkYellow }
    $cont = Read-Host "👉 Tiếp tục? (y/n)"
    if ($cont -ne 'y') { Write-Host "Đã huỷ." -ForegroundColor Gray; exit 0 }
}

# Chặn hard nếu có file nhạy cảm
if ($blocked.Count -gt 0) {
    Write-Host "`n🚫 DỪNG LẠI — $($blocked.Count) file nhạy cảm sẽ bị commit:" -ForegroundColor Red
    $blocked | ForEach-Object { Write-Host "   $_" -ForegroundColor Red }
    Write-Host "`n💡 Thêm vào .gitignore rồi chạy lại:" -ForegroundColor Yellow
    $blocked | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkYellow }
    exit 1
}

# ════════════════════════════════════════════════════════════════════════════
# BƯỚC 6 — git add + loại artifact build
# ════════════════════════════════════════════════════════════════════════════
git add .

# Gỡ artifact build ra khỏi staging (phòng thủ thứ 2 ngoài .gitignore)
$staged = @(git diff --cached --name-only 2>$null)
foreach ($f in $staged) {
    if (-not $f) { continue }
    if ($f -match '\.(apk|aab|ipa|msix|appx)$' -or
        $f -match '(local-publish|apk-output|publish-output)[\\/]') {
        git reset HEAD -- $f 2>$null
        Write-Host "⚠️  Gỡ artifact khỏi commit: $f" -ForegroundColor DarkYellow
    }
}

# ════════════════════════════════════════════════════════════════════════════
# BƯỚC 7 — Tạo commit message thông minh
# ════════════════════════════════════════════════════════════════════════════
# Đề xuất message dựa trên file thay đổi
$stagedFinal  = @(git diff --cached --name-only 2>$null)
$hasCsproj    = $stagedFinal | Where-Object { $_ -match '\.csproj$' }
$hasWorkflow  = $stagedFinal | Where-Object { $_ -match '\.github[\\/]workflows' -or $_ -match '\.yml$' }
$hasResources = $stagedFinal | Where-Object { $_ -match '\.(png|jpg|svg|resx|strings)$' }
$hasCode      = $stagedFinal | Where-Object { $_ -match '\.(cs|xaml|razor)$' }

$suggestion = if ($hasWorkflow)  { "ci: cập nhật workflow CI/CD" }
            elseif ($hasCsproj)  { "build: cập nhật cấu hình project" }
            elseif ($hasResources){ "res: cập nhật tài nguyên" }
            elseif ($hasCode)    { "feat: cập nhật $($hasCode.Count) file code" }
            else                 { "chore: cập nhật lúc " + (Get-Date -Format 'HH:mm dd/MM/yyyy') }

Write-Host "`n💬 Gợi ý: `"$suggestion`"" -ForegroundColor DarkGray
$msg = Read-Host "✍️  Commit message (Enter = dùng gợi ý)"
if ([string]::IsNullOrWhiteSpace($msg)) { $msg = $suggestion }

# Kiểm tra còn gì staged không
$diffCheck = @(git diff --cached --name-only 2>$null)
if ($diffCheck.Count -eq 0) {
    Write-Host "✅ Không có gì staged để commit (có thể đã bị .gitignore lọc hết)." -ForegroundColor Green
    exit 0
}

git commit -m "$msg"
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Commit thất bại." -ForegroundColor Red; exit 1
}

# ════════════════════════════════════════════════════════════════════════════
# BƯỚC 8 — git push
# ════════════════════════════════════════════════════════════════════════════
Write-Host "`n🚀 git push origin $branch …" -ForegroundColor Cyan
git push origin $branch

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n⚠️  Push bị từ chối (có thể remote đã có commit mới)." -ForegroundColor Yellow

    $ans = Read-Host "👉 Thử pull --rebase rồi push lại? (y/n)"
    if ($ans -eq 'y') {
        git pull --rebase origin $branch
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Rebase thất bại — giải quyết conflict rồi chạy lại." -ForegroundColor Red; exit 1
        }
        git push origin $branch
        if ($LASTEXITCODE -ne 0) {
            $force = Read-Host "❓ Vẫn lỗi — force-with-lease? (y/n)"
            if ($force -eq 'y') { git push origin $branch --force-with-lease }
            else { exit 1 }
        }
    } else {
        exit 1
    }
}

# ── Thống kê ─────────────────────────────────────────────────────────────────
Write-Host "`n📊 Diff stat:" -ForegroundColor DarkGray
git diff HEAD~1 --stat 2>$null | Write-Host -ForegroundColor DarkGray

Write-Host "`n🎉 Đồng bộ xong!" -ForegroundColor Green
Write-Host "`a" -NoNewline