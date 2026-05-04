#!/usr/bin/env pwsh
# ==============================================================================
#  gsync.ps1 — Đồng bộ Git thông minh (Pull / Commit / Push)
#  Tính năng nổi bật:
#   - So sánh chính xác local vs remote
#   - Hỏi trước khi pull/commit/push
#   - Phát hiện & chặn file nhạy cảm
#   - Gợi ý commit message thông minh
# ==============================================================================
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── SSH key tuỳ chọn ─────────────────────────────────────────────────────────
$sshKeyPath = Join-Path $PSScriptRoot 'ssh_id'
if (Test-Path $sshKeyPath) {
    $env:GIT_SSH_COMMAND = "ssh -i `"$sshKeyPath`" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"
}

Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host " 🚀 GIT SYNC — VIP PRO (NÂNG CẤP)" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════╝`n" -ForegroundColor Cyan

# ==============================================================================
# BƯỚC 0 — Kiểm tra môi trường
# ==============================================================================
if (-not (Get-Command git -EA SilentlyContinue)) {
    Write-Host "❌ Git chưa cài hoặc không có trong PATH." -ForegroundColor Red; exit 1
}
git rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Thư mục hiện tại không phải là Git repository." -ForegroundColor Red; exit 1
}

$branch = git branch --show-current 2>$null
if ([string]::IsNullOrWhiteSpace($branch)) { $branch = 'main' }
Write-Host "🌿 Nhánh hiện tại: [$branch]" -ForegroundColor Green

# ==============================================================================
# BƯỚC 1 — Lấy thông tin từ remote
# ==============================================================================
Write-Host "📡 Đang kiểm tra thay đổi từ remote..." -ForegroundColor Cyan
git fetch origin $branch 2>$null | Out-Null

$localCommit  = git rev-parse HEAD 2>$null
$remoteCommit = git rev-parse origin/$branch 2>$null

$hasLocalChanges  = $false
$hasRemoteChanges = $false

if ($localCommit -and $remoteCommit) {
    if ($localCommit -ne $remoteCommit) {
        # Kiểm tra xem có thay đổi trên remote không
        $aheadBehind = git rev-list --left-right --count HEAD...origin/$branch 2>$null
        if ($aheadBehind) {
            $counts = $aheadBehind -split '\s+'
            $commitsAhead  = [int]$counts[0] # Local ahead of remote
            $commitsBehind = [int]$counts[1] # Local behind remote
            
            if ($commitsBehind -gt 0) { $hasRemoteChanges = $true }
            if ($commitsAhead -gt 0)  { $hasLocalChanges  = $true }
        }
    }
} else {
    # Trường hợp mới clone hoặc chưa có commit
    if ($remoteCommit) { $hasRemoteChanges = $true }
}

# ==============================================================================
# BƯỚC 2 — Xử lý thay đổi từ REMOTE
# ==============================================================================
if ($hasRemoteChanges) {
    Write-Host "`n🔔 Phát hiện $($commitsBehind) commit mới trên remote!" -ForegroundColor Yellow
    
    # Kiểm tra working tree có sạch không
    $statusBefore = @(git status --porcelain 2>$null)
    if ($statusBefore.Count -eq 0) {
        # Working tree sạch -> hỏi pull
        $pull = Read-Host "👉 Bạn có muốn PULL code mới về không? (y/n) [Mặc định: y]"
        if ([string]::IsNullOrWhiteSpace($pull) -or $pull.ToLower() -eq 'y') {
            Write-Host "🔄 Đang pull code từ remote..." -ForegroundColor Magenta
            git pull origin $branch
            if ($LASTEXITCODE -ne 0) {
                Write-Host "❌ Pull thất bại — hãy giải quyết xung đột rồi chạy lại." -ForegroundColor Red; exit 1
            }
            Write-Host "✅ Pull thành công!" -ForegroundColor Green
        } else {
            Write-Host "⏭️ Đã bỏ qua PULL." -ForegroundColor Gray
        }
    } else {
        # Có thay đổi cục bộ -> cảnh báo
        Write-Host "`n⚠️  Working tree có thay đổi cục bộ!" -ForegroundColor Yellow
        Write-Host "   → Bạn nên commit/stash trước khi pull để tránh mất code." -ForegroundColor DarkGray
        $pullAnyway = Read-Host "👉 Vẫn muốn PULL (có thể gây conflict)? (y/n)"
        if ($pullAnyway -eq 'y') {
            git pull origin $branch
            if ($LASTEXITCODE -ne 0) {
                Write-Host "❌ Pull thất bại — hãy giải quyết xung đột rồi chạy lại." -ForegroundColor Red; exit 1
            }
            Write-Host "✅ Pull thành công!" -ForegroundColor Green
        }
    }
} else {
    Write-Host "✅ Remote không có thay đổi mới." -ForegroundColor Green
}

# ==============================================================================
# BƯỚC 3 — Dọn dẹp file rác & file lớn
# ==============================================================================
Write-Host "`n🧹 Đang quét file rác và file >90MB..." -ForegroundColor Cyan
$badFiles = @(
    & git ls-files --ignored --cached --exclude-standard
    & git ls-files --cached | ForEach-Object {
        if (Test-Path $_) {
            $f = Get-Item $_
            if (-not $f.PSIsContainer -and $f.Length -gt 90mb) { $_ }
        }
    }
) | Where-Object { $_ }

# Ép luôn là mảng để tránh lỗi khi chỉ có 1 file hoặc không file nào
$badFiles = @($badFiles)

if ($badFiles.Count -gt 0) {
    Write-Host "⚠️  Phát hiện $($badFiles.Count) file cần gỡ khỏi Git Index." -ForegroundColor Yellow
    foreach ($file in $badFiles) {
        Write-Host "   -> Đang gỡ: $file" -ForegroundColor Gray
        & git rm --cached -r -f -q "$file" 2>$null
    }
    & git commit -m "fix: cleanup large files and sdk" -q
    Write-Host "✅ Đã dọn dẹp xong bộ nhớ đệm." -ForegroundColor Green
} else {
    Write-Host "✅ Repo sạch sẽ." -ForegroundColor Green
}

# ==============================================================================
# BƯỚC 4 — Kiểm tra file nhạy cảm
# ==============================================================================
$BLOCKED_PATTERNS = @(
    '.keystore$', '.jks$',             # Android keystore
    '.p12$', '.pfx$',                  # Apple / Windows cert
    '.mobileprovision$',                # Apple provisioning
    '^ssh_id$', '^ssh_id.pub$',         # SSH key cạnh script
    '.env$', '.env.',                 # Env vars (trừ .example/.template)
    'signing.properties$',              # Signing config cục bộ
    'keystore.properties$',             # Keystore properties
    'local.properties$',                # Android local config
    'gh.exe$',                          # gh CLI binary
    'local-publish[\/]', 'apk-output[\/]', 'publish-output[\/]'  # Build output
)

function Test-SensitiveFile([string]$path) {
    $ALLOWED_EXCEPTIONS = @('.env.example$', '.env.template$', '.env.sample$')
    foreach ($allow in $ALLOWED_EXCEPTIONS) {
        if ($path -match $allow) { return $false }
    }
    foreach ($pat in $BLOCKED_PATTERNS) {
        if ($path -match $pat) { return $true }
    }
    return $false
}

# ==============================================================================
# BƯỚC 5 — Kiểm tra có gì để COMMIT không
# ==============================================================================
$status = @(git status --porcelain 2>$null)
if ($status.Count -eq 0) {
    Write-Host "`n✅ Không có gì mới để commit / push." -ForegroundColor Green
    exit 0
}

Write-Host "`n📂 Thay đổi phát hiện:" -ForegroundColor Yellow
$blocked = @()
foreach ($line in $status) {
    if (-not $line) { continue }
    $filePath = $line.Substring(3).Trim().Trim('"')
    
    if (Test-SensitiveFile $filePath) {
        $blocked += $filePath
        Write-Host "  🚫 $filePath" -ForegroundColor Red
    } else {
        $statusCode = $line.Substring(0,2).Trim()
        $color = switch -Regex ($statusCode) {
            '^A' { 'Green' }
            '^M' { 'Cyan' }
            '^D' { 'Red' }
            '^R' { 'Yellow' }
            default { 'Gray' }
        }
        Write-Host "  [$statusCode] $filePath" -ForegroundColor $color
    }
}

# Chặn nếu có file nhạy cảm
if ($blocked.Count -gt 0) {
    Write-Host "`n🚫 DỪNG LẠI — $($blocked.Count) file nhạy cảm sẽ bị commit:" -ForegroundColor Red
    $blocked | ForEach-Object { Write-Host " $_" -ForegroundColor Red }
    Write-Host "`n💡 Thêm vào .gitignore rồi chạy lại:" -ForegroundColor Yellow
    $blocked | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkYellow }
    exit 1
}

# ==============================================================================
# BƯỚC 6 — Hỏi và thực hiện COMMIT
# ==============================================================================
$doCommit = Read-Host "`n👉 Bạn có muốn COMMIT những thay đổi này không? (y/n) [Mặc định: y]"
if ([string]::IsNullOrWhiteSpace($doCommit) -or $doCommit.ToLower() -eq 'y') {
    git add .
    
    # Loại bỏ artifact build
    $staged = @(git diff --cached --name-only 2>$null)
    foreach ($f in $staged) {
        if ($f -match '\.(apk|aab|ipa|msix|appx)$' -or
            $f -match '(local-publish|apk-output|publish-output)[\/]') {
            git reset HEAD -- $f 2>$null
            Write-Host "⚠️  Gỡ artifact khỏi commit: $f" -ForegroundColor DarkYellow
        }
    }
    
    # Gợi ý commit message
    $stagedFinal = @(git diff --cached --name-only 2>$null)
    if (-not $stagedFinal) {
        Write-Host "✅ Không còn gì để commit sau khi lọc artifact." -ForegroundColor Green
        exit 0
    }
    
    $hasCsproj    = @($stagedFinal | Where-Object { $_ -match '\.csproj$' })
    $hasWorkflow  = @($stagedFinal | Where-Object { $_ -match '\.github[\/]workflows' -or $_ -match '\.yml$' })
    $hasResources = @($stagedFinal | Where-Object { $_ -match '\.(png|jpg|svg|resx|strings)$' })
    $hasCode      = @($stagedFinal | Where-Object { $_ -match '\.(cs|xaml|razor)$' })

    $suggestion = if ($hasWorkflow.Count -gt 0)   { "ci: cập nhật workflow CI/CD" }
              elseif ($hasCsproj.Count -gt 0)   { "build: cập nhật cấu hình project" }
              elseif ($hasResources.Count -gt 0){ "res: cập nhật tài nguyên" }
              elseif ($hasCode.Count -gt 0)     { "feat: cập nhật $($hasCode.Count) file code" }
              else                              { "chore: cập nhật lúc $(Get-Date -Format 'HH:mm dd/MM/yyyy')" }

    Write-Host "`n💬 Gợi ý:`"$suggestion`"" -ForegroundColor DarkGray
    $msg = Read-Host "✍️  Commit message (Enter = dùng gợi ý)"
    if ([string]::IsNullOrWhiteSpace($msg)) { $msg = $suggestion }
    
    git commit -m "$msg"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Commit thất bại." -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ Commit thành công!" -ForegroundColor Green
}

# ==============================================================================
# BƯỚC 7 — Hỏi và thực hiện PUSH
# ==============================================================================
$doPush = Read-Host "`n👉 Bạn có muốn PUSH lên remote không? (y/n) [Mặc định: y]"
if ([string]::IsNullOrWhiteSpace($doPush) -or $doPush.ToLower() -eq 'y') {
    Write-Host "`n🚀 Đang PUSH lên origin $branch ..." -ForegroundColor Cyan
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
    Write-Host "`n🎉 Đồng bộ hoàn tất!" -ForegroundColor Green
} else {
    Write-Host "`n⏭️ Đã bỏ qua PUSH." -ForegroundColor Gray
}

Write-Host "`a" -NoNewline