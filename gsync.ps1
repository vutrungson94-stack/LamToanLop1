#!/usr/bin/env pwsh
# ==============================================================================
#  gsync.ps1  — Đồng bộ Git (pull / commit / push). Không build.
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

# ======================================================================
# BƯỚC 0 — Kiểm tra git, repo, branch
# ======================================================================
if (-not (Get-Command git -EA SilentlyContinue)) {
    Write-Host "❌ Git chưa cài hoặc không có trong PATH." -ForegroundColor Red
    exit 1
}

git rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Thư mục hiện tại không phải là Git repository." -ForegroundColor Red
    exit 1
}

$branch = git branch --show-current 2>$null
if ([string]::IsNullOrWhiteSpace($branch)) { $branch = 'main' }
Write-Host "🌿 Nhánh: [$branch]" -ForegroundColor Green

# ======================================================================
# BƯỚC DỌN DẸP — Xử lý file lỗi và file quá lớn
# ======================================================================
Write-Host "🧹 Đang quét file rác và file >90 MB…" -ForegroundColor Cyan

$badFiles = @(
    & git ls-files --ignored --cached --exclude-standard
    & git ls-files --cached | ForEach-Object {
        if (Test-Path $_) {
            $item = Get-Item $_
            if (-not $item.PSIsContainer -and $item.Length -gt 90MB) { $_ }
        }
    }
) | Where-Object { $_ }

$badCount = ($badFiles | Measure-Object).Count

if ($badCount -gt 0) {
    Write-Host "⚠️  Phát hiện $badCount file/đối tượng lớn cần gỡ khỏi Git index." -ForegroundColor Yellow
    foreach ($file in $badFiles) {
        Write-Host "   → Gỡ: $file" -ForegroundColor Gray
        & git rm --cached -r -f -q "$file" 2>$null
    }
    & git commit -m "fix: cleanup large files and sdk" -q
    Write-Host "✅ Đã dọn dẹp xong." -ForegroundColor Green
} else {
    Write-Host "✅ Repo sạch sẽ." -ForegroundColor Green
}

# ======================================================================
# BƯỚC 1 — Kiểm tra file nhạy cảm trước khi làm gì
# ======================================================================
# ---- Định nghĩa pattern nhạy cảm ---------------------------------------
$BLOCKED_PATTERNS = @(
    '\.keystore$', '\.jks$',              # Android keystore
    '\.p12$', '\.pfx$',                   # Certs Windows/Apple
    '\.mobileprovision$',                 # Apple provisioning
    '^ssh_id$', '^ssh_id\.pub$',          # SSH key bên cạnh script
    '\.env$', '\.env\.',                  # Env files (trừ .example/.template/.sample)
    'signing\.properties$',               # Android signing
    'keystore\.properties$',              # Android keystore properties
    'local\.properties$',                 # Android local config
    'gh\.exe$',                          # GitHub CLI binary
    'local-publish[\\/]', 'apk-output[\\/]', 'publish-output[\\/]'
)
$ALLOWED_EXCEPTIONS = @(
    '\.env\.example$', '\.env\.template$', '\.env\.sample$'
)

$blocked  = @()
$warnings = @()

function Test-SensitiveFile([string]$path) {
    foreach ($allow in $ALLOWED_EXCEPTIONS) { if ($path -match $allow) { return $false } }
    foreach ($pat in $BLOCKED_PATTERNS) { if ($path -match $pat) { return $true } }
    return $false
}

# ======================================================================
# BƯỚC 2 — Kiểm tra .gitignore có tồn tại không
# ======================================================================
$gitignorePath = Join-Path (git rev-parse --show-toplevel) '.gitignore'
if (-not (Test-Path $gitignorePath)) {
    Write-Host "⚠️  .gitignore chưa có — sẽ tạo file rỗng để ghi entry." -ForegroundColor Yellow
    New-Item -ItemType File -Path $gitignorePath | Out-Null
}

# ======================================================================
# BƯỚC 3 — Hỏi và thực hiện git pull
# ======================================================================
$askPull = Read-Host "`n📥 Bạn có muốn PULL (kéo code) từ nhánh $branch không? (y/n) [Mặc định: y]"
if ([string]::IsNullOrWhiteSpace($askPull) -or $askPull.ToLower() -eq 'y') {
    $statusBefore = @(git status --porcelain 2>$null)
    if (-not $statusBefore) {
        Write-Host "🔄 Working tree sạch — thực hiện git pull --rebase…" -ForegroundColor Magenta
        git pull --rebase origin $branch
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Pull thất bại — hãy giải quyết xung đột rồi chạy lại." -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "✏️  Có thay đổi cục bộ — bỏ qua pull tự động để tránh mất code." -ForegroundColor DarkGray
    }
} else {
    Write-Host "⏭️ Đã bỏ qua bước PULL." -ForegroundColor Gray
}

# ======================================================================
# BƯỚC 4 — Kiểm tra có gì để commit không
# ======================================================================
$status = @(git status --porcelain 2>$null)
if (-not $status) {
    Write-Host "✅ Không có gì mới để commit / push." -ForegroundColor Green
    exit 0
}

# ======================================================================
# BƯỚC 5 — Hiển thị thay đổi, chặn file nhạy cảm, và tự xử lý
# ======================================================================
Write-Host "`n📂 Thay đổi:" -ForegroundColor Yellow

$blocked  = @()
$warnings = @()

foreach ($line in $status) {
    if (-not $line) { continue }

    $filePath   = $line.Substring(3).Trim().Trim('"')
    $statusCode = $line.Substring(0,2).Trim()

    if ($filePath -match '(^|[\\/])(bin|obj)([\\/]|$)') {
        $warnings += $filePath
    }

    if (Test-SensitiveFile $filePath) {
        $blocked += $filePath
        Write-Host "  🚫 [$statusCode] $filePath" -ForegroundColor Red
    } else {
        $color = switch -Regex ($statusCode) {
            '^A' { 'Green'  }
            '^M' { 'Cyan'   }
            '^D' { 'Red'    }
            '^R' { 'Yellow' }
            default { 'Gray' }
        }
        Write-Host "  [$statusCode] $filePath" -ForegroundColor $color
    }
}

if ($warnings.Count -gt 0) {
    Write-Host "`n⚠️  Cảnh báo: Có file trong bin/ hoặc obj/ — kiểm tra .gitignore!" -ForegroundColor Yellow
    $warnings | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkYellow }
    $continue = Read-Host "👉 Tiếp tục? (y/n)"
    if ($continue -ne 'y') { Write-Host "Đã hủy." -ForegroundColor Gray; exit 0 }
}

if ($blocked.Count -gt 0) {
    Write-Host "`n🚫 DỪNG LẠI — $($blocked.Count) file nhạy cảm sẽ bị commit:" -ForegroundColor Red
    foreach ($f in $blocked) { Write-Host "   $f" -ForegroundColor Gray }

    foreach ($f in $blocked) {
        & git rm --cached -r -f -- "$f" 2>$null
    }

    foreach ($f in $blocked) {
        $pattern = if ($f -match '[\\/]+$') { $f } else { "$f" }
        $escapedPattern = [regex]::Escape($pattern).TrimEnd('\')
        $already = Select-String -Path $gitignorePath -Pattern "^$escapedPattern$" -Quiet
        if (-not $already) {
            Add-Content -Path $gitignorePath -Value $pattern
            Write-Host "✅ Đã thêm '$pattern' vào .gitignore" -ForegroundColor Green
        }
    }

    Write-Host "🔄 Thực hiện lại 'git add .' để staging các file an toàn…" -ForegroundColor Cyan
    git add .
} else {
    git add .
}

# ======================================================================
# BƯỚC 6 — Loại bỏ artifact build (phòng thủ thứ 2)
# ======================================================================
$stagedFinal = @(git diff --cached --name-only 2>$null)

if (-not $stagedFinal) {
    Write-Host "✅ Không còn gì để commit sau khi xử lý file nhạy cảm." -ForegroundColor Green
    exit 0
}

foreach ($f in $stagedFinal) {
    if (-not $f) { continue }
    if ($f -match '\.(apk|aab|ipa|msix|appx)$' -or $f -match '(local-publish|apk-output|publish-output)[\\/]') {
        git reset HEAD -- "$f" 2>$null
        Write-Host "⚠️  Gỡ artifact build khỏi commit: $f" -ForegroundColor DarkYellow
    }
}

# ======================================================================
# BƯỚC 7 — Tạo commit message thông minh
# ======================================================================
$stagedFinal = @(git diff --cached --name-only 2>$null)
if (-not $stagedFinal) {
    Write-Host "✅ Không còn gì để commit sau khi lọc artifact." -ForegroundColor Green
    exit 0
}

$hasCsproj    = $stagedFinal | Where-Object { $_ -match '\.csproj$' }
$hasWorkflow  = $stagedFinal | Where-Object { $_ -match '\.github[\\/]workflows' -or $_ -match '\.yml$' }
$hasResources = $stagedFinal | Where-Object { $_ -match '\.(png|jpg|svg|resx|strings)$' }
$hasCode      = $stagedFinal | Where-Object { $_ -match '\.(cs|xaml|razor)$' }

$suggestion = if ($hasWorkflow)   { "ci: cập nhật workflow CI/CD" }
            elseif ($hasCsproj)   { "build: cập nhật cấu hình project" }
            elseif ($hasResources){ "res: cập nhật tài nguyên" }
            elseif ($hasCode) { 
                $count = if ($hasCode -is [System.Collections.ICollection]) { $hasCode.Count } else { 1 }
                "feat: cập nhật $count file code" 
            }
            else                  { "chore: cập nhật lúc $(Get-Date -Format 'HH:mm dd/MM/yyyy')" }

Write-Host "`n💬 Gợi ý: `"$suggestion`"" -ForegroundColor DarkGray
$msg = Read-Host "✍️  Commit message (Enter = dùng gợi ý)"
if ([string]::IsNullOrWhiteSpace($msg)) { $msg = $suggestion }

git commit -m "$msg"
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Commit thất bại." -ForegroundColor Red
    exit 1
}

# ======================================================================
# BƯỚC 8 — Mặc định git push
# ======================================================================
Write-Host "`n🚀 Đang tự động PUSH lên origin $branch …" -ForegroundColor Cyan
git push origin $branch

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n⚠️  Push bị từ chối (có thể remote đã có commit mới)." -ForegroundColor Yellow

    $ans = Read-Host "👉 Thử pull --rebase rồi push lại? (y/n)"
    if ($ans -eq 'y') {
        git pull --rebase origin $branch
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Rebase thất bại — giải quyết conflict rồi chạy lại." -ForegroundColor Red
            exit 1
        }
        git push origin $branch
        if ($LASTEXITCODE -ne 0) {
            $force = Read-Host "❓ Vẫn lỗi — force‑with‑lease? (y/n)"
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

Write-Host "`n🎉 Hoàn tất!" -ForegroundColor Green
Write-Host "`a" -NoNewline