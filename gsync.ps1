#!/usr/bin/env pwsh
# ==============================================================================
# gsync.ps1 — Git Sync VIP PRO  |  config-driven · đa nền tảng · an toàn
# Hỗ trợ: MAUI · Blazor · ASP.NET · Angular · React · Vue · Python · Go · Java
# Chạy được: Windows · Linux · macOS  |  PowerShell 5.1+ / pwsh 7+
# ==============================================================================
# CÁCH DÙNG:
#   ./gsync.ps1                       – Chạy bình thường (có hỏi)
#   ./gsync.ps1 -Yes                  – Tự động "có" mọi câu hỏi (CI/CD)
#   ./gsync.ps1 -No                   – Tự động "không" mọi câu hỏi (dry-run)
#   ./gsync.ps1 -NonInteractive       – Dùng Default của từng prompt, không hỏi
#   ./gsync.ps1 -ConfigPath ./my.json – Chỉ định config khác
# ==============================================================================
[CmdletBinding()]
param(
    [switch]$NonInteractive,
    [switch]$Yes,
    [switch]$No,
    [string]$ConfigPath = (Join-Path $PSScriptRoot ".gitignore.config.json")
)

Set-StrictMode -Version Latest
# ✅ FIX 1: 'Stop' không ảnh hưởng native git (chỉ ảnh hưởng cmdlet), nhưng lại làm
#    crash script nếu cmdlet như Add-Content / New-Item gặp lỗi quyền truy cập.
#    Dùng 'Continue' để xử lý lỗi có kiểm soát qua $LASTEXITCODE và try/catch tường minh.
$ErrorActionPreference = 'Continue'
$Global:StartTime      = Get-Date

# ── Cross-platform ─────────────────────────────────────────────────────────────
$SEP = [IO.Path]::DirectorySeparatorChar

# ── Màu sắc ───────────────────────────────────────────────────────────────────
$C_Header = "Magenta"; $C_Info = "Cyan"; $C_Warn = "Yellow"
$C_Err    = "Red";     $C_Succ = "Green"; $C_Gray = "DarkGray"

# ==============================================================================
# HÀM UI
# ==============================================================================
function Get-ConsoleWidth {
    try {
        $w = (Get-Host).UI.RawUI.WindowSize.Width
        if ($w -and $w -gt 20) { return $w }
    } catch { }
    if ($env:COLUMNS -and [int]::TryParse($env:COLUMNS, [ref]$null)) { return [int]$env:COLUMNS }
    return 80
}

function Draw-Header {
    Write-Host @"
`n╔══════════════════════════════════════════════════════════════════════╗
║           GIT SYNC VIP PRO — Đồng bộ thông minh & an toàn           ║
╚══════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor $C_Header
}

function Write-StepTitle([string]$Title, [string]$Color = "Cyan") {
    $w       = Get-ConsoleWidth
    $padding = [Math]::Max(0, $w - $Title.Length - 12)
    Write-Host "`n── [ $Title ] $('─' * $padding)" -ForegroundColor $Color
}

function Write-SubLog([string]$Label, [string]$Value, [string]$Color = "White") {
    Write-Host "  $Label" -NoNewline -ForegroundColor $C_Gray
    Write-Host (": $Value") -ForegroundColor $Color
}

function Confirm-YesNo {
    param([string]$Question, [string]$Default = "y")
    if ($No)             { return $false }
    # ✅ FIX 2: Logic gốc `($Default -eq "y") -or $Default -eq "n"` LUÔN = $true
    #    vì mọi $Default đều là "y" hoặc "n" → -Yes luôn accept kể cả prompt nguy hiểm Default="n".
    #    Hành vi đúng: -Yes = "đồng ý tất cả" → return $true vô điều kiện.
    if ($Yes)            { return $true }
    if ($NonInteractive) { return ($Default -eq "y") }
    $suffix = if ($Default -eq "y") { "(y/n) [Mặc định: y]" } else { "(y/n) [Mặc định: n]" }
    $ans = Read-Host "$Question $suffix"
    if ([string]::IsNullOrWhiteSpace($ans)) { return ($Default -eq "y") }
    return ($ans.Trim().ToLowerInvariant() -eq "y")
}

# ==============================================================================
# CONFIG — TỰ ĐỘNG TẠO MẶC ĐỊNH NẾU FILE KHÔNG TỒN TẠI
# ==============================================================================
function Get-DefaultConfig {
    # JSON inline — không phụ thuộc file bên ngoài, dùng được offline
    $json = @'
{
  "_readme": "gsync config. Chỉnh sửa thoải mái. Xem: https://github.com/bạn/gsync",
  "git": {
    "remoteName":               "origin",
    "defaultBranchFallback":    "main",
    "pullConflictPolicy":       "ask",
    "stashWhenWorkingTreeDirty": true
  },
  "gitignore": {
    "enabled": true,
    "rulesToAdd": [
      "# === SECURITY ===",
      "ssh_id", "ssh_id.pub",
      "*.pfx", "*.p12", "*.key", "*.pem", "*.keystore", "*.jks",
      ".env", ".env.*", "!.env.example", "!.env.template", "!.env.sample",
      "secrets.json",
      "appsettings.*.json", "!appsettings.Development.json",
      "signing.properties", "keystore.properties",
      "google-services.json", "GoogleService-Info.plist",
      "# === .NET / MAUI ===",
      "bin/", "obj/", "publish/", ".sdk/", ".sdkcache.json", "*.user",
      "local.properties",
      "# === NODE / WEB ===",
      "node_modules/", "dist/", ".next/", ".nuxt/", ".output/",
      "# === PYTHON ===",
      "__pycache__/", "*.pyc", ".venv/", "venv/",
      "# === IDE & OS ===",
      ".vs/", ".vscode/", ".idea/",
      "*.log", ".DS_Store", "Thumbs.db", "desktop.ini",
      "# === BUILD ARTIFACTS ===",
      "*.apk", "*.aab", "*.ipa", "*.msix", "*.appx",
      "local-publish/", "apk-output/", "publish-output/"
    ]
  },
  "sensitive": {
    "enabled": true,
    "allowedPatterns": [
      "\\.env\\.example$", "\\.env\\.template$", "\\.env\\.sample$"
    ],
    "blockedPatterns": [
      "\\.keystore$", "\\.jks$", "\\.p12$", "\\.pfx$", "\\.mobileprovision$",
      "^ssh_id$", "^ssh_id\\.pub$",
      "(^|[\\\\/])\\.env$", "(^|[\\\\/])\\.env\\.",
      "signing\\.properties$", "keystore\\.properties$",
      "local\\.properties$",
      "google-services\\.json$", "GoogleService-Info\\.plist$",
      "secrets\\.json$",
      "(local-publish|apk-output|publish-output)[\\\\/]"
    ]
  },
  "junkCleanup": {
    "enabled": true,
    "patterns":           [ "*.tmp", "*.bak", "Thumbs.db", "desktop.ini" ],
    "restrictToDirs":     [ "." ],
    "confirmBeforeDelete": false
  },
  "largeFiles": {
    "enabled":     true,
    "excludeDirs": [ ".git", "node_modules", ".sdk", ".venv", "venv" ]
  },
  "artifactUnstage": {
    "enabled":       true,
    "patterns":      [ "\\.(apk|aab|ipa|msix|appx|nupkg|snupkg)$" ],
    "extraPatterns": [ "(local-publish|apk-output|publish-output)[\\\\/]" ]
  },
  "ui": {
    "largeFileThresholdMB": 90
  }
}
'@
    return ($json | ConvertFrom-Json)
}

function Load-Config([string]$path) {
    if (-not (Test-Path $path)) {
        Write-Host "  ℹ️  Không tìm thấy '$($path | Split-Path -Leaf)'" -ForegroundColor $C_Info
        Write-Host "     → Đang tạo config mặc định đa năng..." -ForegroundColor $C_Gray
        $defaultCfg = Get-DefaultConfig
        try {
            $outPath = (Join-Path (Get-Location).Path ($path | Split-Path -Leaf))
            $jsonOut = $defaultCfg | ConvertTo-Json -Depth 10
            # Ghi UTF-8 không BOM — tương thích mọi editor và OS
            [System.IO.File]::WriteAllText($outPath, $jsonOut,
                [System.Text.UTF8Encoding]::new($false))
            Write-SubLog "Config" "Đã tạo '$outPath' — hãy kiểm tra và chỉnh sửa nếu cần" $C_Succ
        } catch {
            Write-Host "  ⚠️  Không thể ghi config ra đĩa: $($_.Exception.Message)" -ForegroundColor $C_Warn
            Write-Host "     → Dùng config in-memory cho lần này." -ForegroundColor $C_Gray
        }
        return $defaultCfg
    }

    try {
        # Đọc UTF-8 không BOM — tránh ConvertFrom-Json lỗi BOM trên PS 5.1
        $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        return ($raw | ConvertFrom-Json)
    } catch {
        Write-Host "❌ Lỗi parse '$path': $($_.Exception.Message)" -ForegroundColor $C_Err
        Write-Host "   → Kiểm tra JSON syntax (dùng jsonlint.com hoặc VS Code)." -ForegroundColor $C_Warn
        exit 1
    }
}

# ==============================================================================
# SSH KEY
# ==============================================================================
function Try-SetupSshKey {
    $sshKeyPath = Join-Path $PSScriptRoot 'ssh_id'
    if (-not (Test-Path $sshKeyPath)) { return }
    $resolved  = (Resolve-Path $sshKeyPath).Path
    $escaped   = $resolved -replace '"', '\"'
    $env:GIT_SSH_COMMAND = "ssh -i `"$escaped`" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"
    Write-SubLog "SSH Key" "Đã nạp ($resolved)" $C_Succ
}

# ==============================================================================
# MAIN
# ==============================================================================
$cfg = Load-Config $ConfigPath
Draw-Header
Try-SetupSshKey

# Tắt git pager — tránh block terminal khi output dài (git log, git diff...)
$env:GIT_PAGER = 'cat'
$env:PAGER     = 'cat'

# ──────────────────────────────────────────────────────────────────────────────
# BƯỚC 0 – KIỂM TRA MÔI TRƯỜNG
# ──────────────────────────────────────────────────────────────────────────────
Write-StepTitle "KIỂM TRA MÔI TRƯỜNG"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Git chưa cài hoặc không có trong PATH." -ForegroundColor $C_Err; exit 1
}

$null = & git rev-parse --is-inside-work-tree 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Thư mục hiện tại không phải Git repository." -ForegroundColor $C_Err; exit 1
}

# Xử lý file lock (index.lock) nếu có để tránh treo script
$lockFile = Join-Path (Get-Location) ".git/index.lock"
if (Test-Path $lockFile) {
  Write-Host "⚠️  Phát hiện file index.lock đang chặn Git. Đang xử lý..." -ForegroundColor $C_Warn
  Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
  if (Test-Path $lockFile) {
      Write-Host "❌ Không thể giải phóng Git lock. Hãy đóng IDE rồi thử lại." -ForegroundColor $C_Err
      exit 1
  }
  Write-Host "✅ Đã giải phóng Git lock thành công." -ForegroundColor $C_Succ
}

# Xác định nhánh — hỗ trợ git cũ (<2.22) và detached HEAD
$localBranch = (& git branch --show-current 2>$null)
if ([string]::IsNullOrWhiteSpace($localBranch)) {
    $localBranch = (& git rev-parse --abbrev-ref HEAD 2>$null)
}
if ([string]::IsNullOrWhiteSpace($localBranch) -or $localBranch -eq 'HEAD') {
    # ✅ FIX 3: File gốc silently fallback về defaultBranchFallback khi detached HEAD
    #    → Không cảnh báo, có thể push nhầm nhánh. Phải hỏi user.
    $fallback = [string]$cfg.git.defaultBranchFallback
    Write-Host "  ⚠️  Không xác định được nhánh (detached HEAD?)." -ForegroundColor $C_Warn
    if ($NonInteractive -or $Yes) {
        $localBranch = $fallback
        Write-SubLog "Nhánh" "Dùng fallback '$localBranch' (auto)" $C_Warn
    } else {
        $inp = Read-Host "   Nhập tên nhánh (Enter = $fallback)"
        $localBranch = if ([string]::IsNullOrWhiteSpace($inp)) { $fallback } else { $inp }
    }
}

$remoteName = [string]$cfg.git.remoteName

# ✅ FIX 4: `@{u}` KHÔNG được để bare — PowerShell parse là hashtable literal → syntax error.
#    Phải quote thành '@{u}' (single-quote) để truyền đúng cho git.
$upstreamRaw = (& git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null)
$upstreamRef = if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($upstreamRaw)) {
    $upstreamRaw
} else {
    "$remoteName/$localBranch"
}

$remoteBranchRef   = $upstreamRef
# Tách branch name phần sau remote/ (hỗ trợ tên có dấu / như feature/abc)
$remoteBranchShort = ($remoteBranchRef -split '/', 2)[-1]
if ([string]::IsNullOrWhiteSpace($remoteBranchShort)) { $remoteBranchShort = $localBranch }

# Kiểm tra remote branch tồn tại chưa (branch mới chưa push lần nào)
$null = & git rev-parse $remoteBranchRef 2>$null
$remoteExists = ($LASTEXITCODE -eq 0)

Write-SubLog "Nhánh local"     $localBranch      $C_Info
Write-SubLog "Remote tracking" $remoteBranchRef  $C_Gray
if (-not $remoteExists) {
    Write-SubLog "Remote branch" "Chưa tồn tại — sẽ tạo khi push" $C_Warn
}

# ──────────────────────────────────────────────────────────────────────────────
# BƯỚC 1 – .GITIGNORE & DỌN RÁC
# ──────────────────────────────────────────────────────────────────────────────
Write-StepTitle "BẢO VỆ & DỌN DẸP"

if ($cfg.gitignore.enabled -eq $true) {
    $ignoreFile = ".gitignore"
    if (-not (Test-Path $ignoreFile)) {
        New-Item -ItemType File -Path $ignoreFile -Force | Out-Null
        Write-SubLog ".gitignore" "Đã tạo mới" $C_Succ
    }
    $currentContent = @(Get-Content $ignoreFile -ErrorAction SilentlyContinue |
                        ForEach-Object { $_.TrimEnd() })
    $added = 0
    foreach ($p in $cfg.gitignore.rulesToAdd) {
        $pStr = [string]$p
        if (-not ($currentContent -contains $pStr)) {
            Add-Content $ignoreFile $pStr; $added++
        }
    }
    if ($added -gt 0) { Write-SubLog ".gitignore" "Đã thêm $added quy tắc" $C_Succ }
    else              { Write-SubLog ".gitignore" "Đã an toàn" $C_Gray }
}

if ($cfg.junkCleanup.enabled -eq $true) {
    $junkPatterns  = @($cfg.junkCleanup.patterns)
    $restrictDirs  = @($cfg.junkCleanup.restrictToDirs)
    $confirmBefore = [bool]$cfg.junkCleanup.confirmBeforeDelete
    $gitDirPat     = [regex]::Escape("${SEP}.git")

    # ✅ FIX 5: Tên biến `$matches` là AUTOMATIC VARIABLE của PowerShell (-match, -replace).
    #    Gán vào `$matches` override biến hệ thống → hành vi không đoán trước với StrictMode.
    #    Đổi sang `$junkFound`.
    $junkFound = @(
        foreach ($dir in $restrictDirs) {
            if (-not (Test-Path $dir)) { continue }
            foreach ($pat in $junkPatterns) {
                Get-ChildItem -Path $dir -Include $pat -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notmatch $gitDirPat }
            }
        }
    )
    $junkFound = @($junkFound | Sort-Object FullName -Unique)

    if ($junkFound.Count -gt 0) {
        if ($confirmBefore) {
            Write-Host "`n  ⚠️ PHÁT HIỆN FILE RÁC ($($junkFound.Count) file):" -ForegroundColor $C_Warn
            if (Confirm-YesNo "Bạn có muốn xóa không?" -Default "n") {
                $junkFound | Remove-Item -Force -ErrorAction SilentlyContinue
                Write-SubLog "File rác" "Đã xóa $($junkFound.Count) file" $C_Succ
            } else {
                Write-SubLog "File rác" "Đã hủy xóa" $C_Gray
            }
        } else {
            $junkFound | Remove-Item -Force -ErrorAction SilentlyContinue
            Write-SubLog "File rác" "Đã xóa $($junkFound.Count) file" $C_Succ
        }
    }
}

if ($cfg.largeFiles.enabled -eq $true) {
    $thresholdMB    = [double]$cfg.ui.largeFileThresholdMB
    $thresholdBytes = $thresholdMB * 1MB
    $excludeDirs    = @($cfg.largeFiles.excludeDirs)

    function Test-IsExcludedPath([string]$fullPath, [string[]]$dirs) {
        foreach ($d in $dirs) {
            # ✅ FIX 6: Gốc dùng `-like "*$d*"` → false-positive: "bin" khớp "cabin", "Robinhood"...
            #    Dùng regex boundary với path separator để chỉ khớp đúng thư mục.
            $escaped = [regex]::Escape($d)
            if ($fullPath -match "(^|[$([regex]::Escape($SEP))/])$escaped([$([regex]::Escape($SEP))/]|$)") {
                return $true
            }
        }
        return $false
    }

    # ✅ FIX 7: Thiếu @() wrapper — Where-Object trả về single FileInfo khi chỉ 1 kết quả,
    #    object đó không có .Count → crash với StrictMode. Bọc @() để đảm bảo luôn là array.
    $largeFiles = @(
        Get-ChildItem -Path . -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -gt $thresholdBytes -and -not (Test-IsExcludedPath $_.FullName $excludeDirs) }
    )

    if ($largeFiles.Count -gt 0) {
        Write-Host "`n  ⚠️ PHÁT HIỆN FILE LỚN (> $thresholdMB MB):" -ForegroundColor $C_Warn
        foreach ($f in ($largeFiles | Select-Object -First 25)) {
            Write-SubLog "(!) $($f.Name)" "$([Math]::Round($f.Length/1MB,2)) MB" $C_Warn
        }
        if ($largeFiles.Count -gt 25) {
            Write-Host "  ... và $($largeFiles.Count - 25) file nữa." -ForegroundColor $C_Gray
        }
        if (-not (Confirm-YesNo "Bạn có muốn tiếp tục?" -Default "n")) { exit 1 }
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# BƯỚC 2 – FETCH & AHEAD/BEHIND
# ──────────────────────────────────────────────────────────────────────────────
Write-StepTitle "PHÂN TÍCH THAY ĐỔI"
Write-SubLog "Remote" "Đang fetch..." $C_Gray

# ✅ FIX 8: File gốc không kiểm tra $LASTEXITCODE sau fetch → lỗi mạng bị nuốt im lặng.
$fetchOut  = & git --no-pager fetch $remoteName 2>&1
$fetchCode = $LASTEXITCODE
if ($fetchCode -ne 0) {
    Write-Host "❌ Không thể fetch từ remote (exitcode $fetchCode)." -ForegroundColor $C_Err
    Write-Host "   $fetchOut"                                        -ForegroundColor $C_Gray
    Write-Host "   → Kiểm tra mạng, URL remote, quyền truy cập."   -ForegroundColor $C_Warn
    exit 1
}

$localCommit  = (& git rev-parse HEAD 2>$null)
$remoteCommit = if ($remoteExists) { (& git rev-parse $remoteBranchRef 2>$null) } else { $null }

$commitsAhead  = 0
$commitsBehind = 0
if ($remoteExists -and $localCommit -and $remoteCommit -and ($localCommit -ne $remoteCommit)) {
    $aheadBehind = (& git rev-list --left-right --count "$localCommit...$remoteCommit" 2>$null)
    if ($aheadBehind -and $LASTEXITCODE -eq 0) {
        $parts = $aheadBehind -split '\s+'
        if ($parts.Count -ge 2) {
            $commitsAhead  = [int]$parts[0]
            $commitsBehind = [int]$parts[1]
        }
    }
}

Write-SubLog "Local ahead"   "$commitsAhead commit(s)"  $(if ($commitsAhead  -gt 0) { $C_Warn } else { $C_Succ })
Write-SubLog "Remote behind" "$commitsBehind commit(s)" $(if ($commitsBehind -gt 0) { $C_Warn } else { $C_Succ })

# ──────────────────────────────────────────────────────────────────────────────
# BƯỚC 3 – PULL (stash an toàn nếu working tree có thay đổi)
# ──────────────────────────────────────────────────────────────────────────────
$Script:StashName = $null   # theo dõi stash do gsync tạo ra

function Invoke-StashIfDirty {
    if ($cfg.git.stashWhenWorkingTreeDirty -ne $true) { return $false }
    $dirty = @(& git status --porcelain 2>$null)
    if ($dirty.Count -eq 0) { return $false }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $Script:StashName = "gsync-auto-$stamp"
    & git stash push -u -m $Script:StashName 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ⚠️ Không thể stash working tree — tiếp tục không stash." -ForegroundColor $C_Warn
        $Script:StashName = $null
        return $false
    }
    Write-SubLog "Stash" "Đã lưu thay đổi cục bộ ($($Script:StashName))" $C_Info
    return $true
}

function Invoke-PopStash {
    if (-not $Script:StashName) { return }
    # ✅ FIX 9: Gốc pop stash MỚI NHẤT → có thể pop nhầm stash CŨ của user → mất data.
    #    Tìm đúng stash theo tên gsync đã đặt, chỉ pop đúng stash đó.
    $stashLine = (& git stash list --format='%gd %s' 2>$null |
                  Where-Object { $_ -match [regex]::Escape($Script:StashName) } |
                  Select-Object -First 1)
    if (-not $stashLine) {
        Write-Host "  ⚠️ Không tìm thấy stash '$($Script:StashName)' — bỏ qua pop." -ForegroundColor $C_Warn
        return
    }
    $stashRef = ($stashLine -split ' ')[0]
    & git stash pop $stashRef 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "⚠️ Stash pop gặp conflict. Xử lý thủ công: git stash pop $stashRef" -ForegroundColor $C_Warn
        exit 1
    }
    Write-SubLog "Stash" "Đã khôi phục thay đổi cục bộ" $C_Succ
    $Script:StashName = $null
}

if ($commitsBehind -gt 0) {
    Write-Host "`n🔔 Remote có $commitsBehind commit mới!" -ForegroundColor $C_Warn
    if ([string]$cfg.git.pullConflictPolicy -eq "ask") {
        if (Confirm-YesNo "Bạn có muốn PULL code mới về không?" -Default "y") {
            $stashed = Invoke-StashIfDirty
            Write-Host "🔄 Đang pull từ remote..." -ForegroundColor $C_Info
            & git --no-pager pull $remoteName $remoteBranchShort
            if ($LASTEXITCODE -ne 0) {
                Write-Host "❌ Pull thất bại — giải quyết xung đột rồi chạy lại." -ForegroundColor $C_Err
                exit 1
            }
            if ($stashed) { Invoke-PopStash }
            Write-SubLog "Pull" "Thành công!" $C_Succ
        } else {
            Write-SubLog "Pull" "Đã bỏ qua" $C_Gray
        }
    }
} else {
    Write-SubLog "Remote" "Không có thay đổi mới" $C_Gray
}

# ──────────────────────────────────────────────────────────────────────────────
# BƯỚC 4 – QUÉT FILE NHẠY CẢM (config-driven)
# ──────────────────────────────────────────────────────────────────────────────
function Test-SensitiveFile([string]$path) {
    if ($cfg.sensitive.enabled -ne $true) { return $false }
    foreach ($a in @($cfg.sensitive.allowedPatterns)) { if ($path -match $a) { return $false } }
    foreach ($p in @($cfg.sensitive.blockedPatterns))  { if ($path -match $p) { return $true  } }
    return $false
}

# ──────────────────────────────────────────────────────────────────────────────
# BƯỚC 5 – THAY ĐỔI CỤC BỘ
# ──────────────────────────────────────────────────────────────────────────────
$gitStatus = @(& git status --porcelain 2>$null)
if ($gitStatus.Count -eq 0) {
    Write-StepTitle "HOÀN TẤT"
    Write-Host "✅ Không có thay đổi cục bộ. Repo đã đồng bộ." -ForegroundColor $C_Succ
    exit 0
}

Write-StepTitle "THAY ĐỔI CỤC BỘ"
$blockedFiles = @()

foreach ($line in $gitStatus) {
    if (-not $line -or $line.Length -lt 3) { continue }
    $rawPath = $line.Substring(3).Trim()
    # Porcelain v1: path có ký tự đặc biệt được bọc trong dấu ngoặc kép + escape octal
    if ($rawPath.StartsWith('"') -and $rawPath.EndsWith('"')) {
        $rawPath = $rawPath.Substring(1, $rawPath.Length - 2)
    }
    if (Test-SensitiveFile $rawPath) {
        $blockedFiles += $rawPath
        Write-Host "  🚫 [BLOCKED] $rawPath" -ForegroundColor $C_Err
    } else {
        $code  = $line.Substring(0, 2).Trim()
        $color = switch -Regex ($code) {
            '^A'    { 'Green'   }
            '^M'    { 'Cyan'    }
            '^D'    { 'Red'     }
            '^R'    { 'Yellow'  }
            '^U'    { 'Magenta' }
            default { 'Gray'    }
        }
        Write-Host "  [$code] $rawPath" -ForegroundColor $color
    }
}

if ($blockedFiles.Count -gt 0) {
    Write-Host "`n🚫 DỪNG LẠI — $($blockedFiles.Count) file nhạy cảm bị chặn:" -ForegroundColor $C_Err
    $blockedFiles | ForEach-Object { Write-Host "   · $_" -ForegroundColor $C_Err }
    Write-Host "`n💡 Thêm vào .gitignore rồi chạy: git rm --cached <file>" -ForegroundColor $C_Warn
    exit 1
}

# ──────────────────────────────────────────────────────────────────────────────
# BƯỚC 6 – COMMIT
# ──────────────────────────────────────────────────────────────────────────────
if (-not (Confirm-YesNo "Bạn có muốn COMMIT những thay đổi này không?" -Default "y")) {
    Write-SubLog "Commit" "Đã bỏ qua" $C_Gray
} else {
    # ✅ FIX 10: `git add .` bỏ sót deletions trong một số git version cũ.
    #    `git add -A` stage đúng: new · modified · deleted.
    & git add -A
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ git add thất bại." -ForegroundColor $C_Err; exit 1
    }

    if ($cfg.artifactUnstage.enabled -eq $true) {
        $stagedNow   = @(& git diff --cached --name-only 2>$null)
        # ✅ FIX 11: Tên biến $patterns bị dùng lại ở Bước 1 (junkCleanup) cùng scope
        #    → có thể override nhau với StrictMode. Đổi tên tường minh.
        $artifactPats = @($cfg.artifactUnstage.patterns) + @($cfg.artifactUnstage.extraPatterns)
        foreach ($f in $stagedNow) {
            $isArt = $false
            foreach ($pat in $artifactPats) {
                if ($f -match $pat) { $isArt = $true; break }
            }
            if ($isArt) {
                & git reset HEAD -- $f 2>$null | Out-Null
                Write-SubLog "Gỡ artifact" $f $C_Warn
            }
        }
    }

    $stagedFinal = @(& git diff --cached --name-only 2>$null)
    if ($stagedFinal.Count -eq 0) {
        Write-Host "✅ Không còn file nào sau khi lọc artifact." -ForegroundColor $C_Succ; exit 0
    }

    # Gợi ý commit message — đa ngôn ngữ lập trình
    $hasWorkflow  = @($stagedFinal | Where-Object { $_ -match '\.ya?ml$' -or $_ -match '\.github[\\/]' })
    $hasProjFile  = @($stagedFinal | Where-Object { $_ -match '\.(csproj|vbproj|fsproj|sln|gradle|pom\.xml)$' })
    $hasResources = @($stagedFinal | Where-Object { $_ -match '\.(png|jpg|jpeg|svg|resx|strings|xcassets)$' })
    $hasCode      = @($stagedFinal | Where-Object {
        $_ -match '\.(cs|xaml|razor|fs|vb|js|ts|jsx|tsx|vue|py|go|java|kt|swift|rb|rs|cpp|c|h)$'
    })
    $hasConfig    = @($stagedFinal | Where-Object { $_ -match '\.(json|xml|toml|ini|conf|config)$' })
    $hasDoc       = @($stagedFinal | Where-Object { $_ -match '\.(md|txt|rst|adoc)$' })

    $suggestion =
        if     ($hasWorkflow.Count  -gt 0) { "ci: cập nhật workflow CI/CD" }
        elseif ($hasProjFile.Count  -gt 0) { "build: cập nhật cấu hình project" }
        elseif ($hasResources.Count -gt 0) { "res: cập nhật tài nguyên ($($hasResources.Count) file)" }
        elseif ($hasCode.Count      -gt 0) { "feat: cập nhật $($hasCode.Count) file code" }
        elseif ($hasConfig.Count    -gt 0) { "chore: cập nhật cấu hình" }
        elseif ($hasDoc.Count       -gt 0) { "docs: cập nhật tài liệu" }
        else                               { "chore: cập nhật lúc $(Get-Date -Format 'HH:mm dd/MM/yyyy')" }

    Write-Host "`n💬 Gợi ý: `"$suggestion`"" -ForegroundColor $C_Gray
    $msg = if ($NonInteractive -or $Yes) {
        Write-Host "✍️  Commit message: $suggestion (auto)" -ForegroundColor $C_Gray
        $suggestion
    } else {
        $inp = Read-Host "✍️  Commit message (Enter = dùng gợi ý)"
        if ([string]::IsNullOrWhiteSpace($inp)) { $suggestion } else { $inp }
    }

    & git commit -m "$msg"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Commit thất bại." -ForegroundColor $C_Err; exit 1
    }
    Write-SubLog "Commit" "Thành công!" $C_Succ
}

# ──────────────────────────────────────────────────────────────────────────────
# BƯỚC 7 – PUSH (retry + force-with-lease)
# ──────────────────────────────────────────────────────────────────────────────
if (-not (Confirm-YesNo "Bạn có muốn PUSH lên remote không?" -Default "y")) {
    Write-Host "⏭️ Đã bỏ qua PUSH." -ForegroundColor $C_Gray
} else {
    Write-Host "`n🚀 Đang PUSH lên $remoteName/$localBranch ..." -ForegroundColor $C_Info

    # ✅ FIX 12: Branch mới chưa có trên remote cần --set-upstream để tạo tracking.
    #    Thiếu thì push vẫn thành công nhưng lần sau `@{u}` vẫn không tìm được upstream.
    if (-not $remoteExists) {
        & git push --set-upstream $remoteName $localBranch
    } else {
        & git push $remoteName $localBranch
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Host "`n⚠️ Push bị từ chối (remote có commit mới?)." -ForegroundColor $C_Warn
        if (-not (Confirm-YesNo "Thử pull --rebase rồi push lại?" -Default "y")) { exit 1 }

        & git --no-pager pull --rebase $remoteName $remoteBranchShort
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Rebase thất bại — giải quyết conflict rồi chạy lại." -ForegroundColor $C_Err; exit 1
        }

        & git push $remoteName $localBranch
        if ($LASTEXITCODE -ne 0) {
            Write-Host "`n⚠️ Vẫn lỗi push." -ForegroundColor $C_Warn
            if (Confirm-YesNo "Thử force-with-lease? (chỉ dùng khi bạn chắc)" -Default "n") {
                & git --no-pager fetch $remoteName 2>$null | Out-Null
                & git push $remoteName $localBranch --force-with-lease
                # ✅ FIX 13: Gốc không kiểm tra exitcode sau force-with-lease → script kết thúc "thành công"
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "❌ Force push thất bại. Kiểm tra quyền trên remote." -ForegroundColor $C_Err; exit 1
                }
            } else { exit 1 }
        }
    }
    Write-Host "`n🎉 Đồng bộ hoàn tất!" -ForegroundColor $C_Succ
}

$duration = (Get-Date) - $Global:StartTime
Write-StepTitle "HOÀN TẤT TRONG $($duration.TotalSeconds.ToString('F1')) GIÂY" $C_Succ
Write-Host ""

# Dọn biến môi trường tạm — không để lại side-effect cho session
$env:GIT_PAGER = $null
$env:PAGER     = $null