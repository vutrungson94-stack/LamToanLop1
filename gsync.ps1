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
    [string]$ConfigPath = (Join-Path (Get-Location) ".gitignore.config.json"),
    [string]$RepoUrl = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$Global:StartTime      = Get-Date

# ── Cross-platform ─────────────────────────────────────────────────────────────
$SEP = [IO.Path]::DirectorySeparatorChar
$IsWindowsEnv = $env:OS -like 'Windows*'

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

function Show-Header {
    Write-Host @"
`n╔══════════════════════════════════════════════════════════════════════╗
║           GIT SYNC VIP PRO — Đồng bộ thông minh & an toàn            ║
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

function Import-Config([string]$path) {
    if (-not (Test-Path $path)) {
        Write-Host "  ℹ️  Không tìm thấy '$($path | Split-Path -Leaf)'" -ForegroundColor $C_Info
        Write-Host "     → Đang tạo config mặc định đa năng..." -ForegroundColor $C_Gray
        $defaultCfg = Get-DefaultConfig
        try {
            $outPath = $path
            $jsonOut = $defaultCfg | ConvertTo-Json -Depth 10
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
function Initialize-SshKey {
    $sshKeyPath = Join-Path $PSScriptRoot 'ssh_id'
    if (-not (Test-Path $sshKeyPath)) { return }
    $resolved  = (Resolve-Path $sshKeyPath).Path
    $escaped   = $resolved -replace '"', '\"'
    $env:GIT_SSH_COMMAND = "ssh -i `"$escaped`" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
    Write-SubLog "SSH Key" "Đã nạp ($resolved)" $C_Succ
}

# ==============================================================================
# HÀM XỬ LÝ XUNG ĐỘT KHI PULL / REBASE
# ==============================================================================
function Get-GitConflictType {
    $gitDir = Join-Path (Get-Location) ".git"
    if ((Test-Path (Join-Path $gitDir "rebase-merge")) -or (Test-Path (Join-Path $gitDir "rebase-apply"))) {
        return "rebase"
    }
    if (Test-Path (Join-Path $gitDir "MERGE_HEAD")) {
        return "merge"
    }
    if (Test-Path (Join-Path $gitDir "CHERRY_PICK_HEAD")) {
        return "cherry-pick"
    }
    return $null
}

function Handle-GitConflict {
    $conflictType = Get-GitConflictType
    if (-not $conflictType) {
        Write-Host "❌ Lỗi pull không xác định (không phải conflict). Hãy kiểm tra lại." -ForegroundColor $C_Err
        exit 1
    }

    Write-Host "`n⚠️ Xung đột xảy ra trong quá trình ${conflictType}!" -ForegroundColor $C_Warn
    if (Confirm-YesNo "Bạn có muốn hủy bỏ (abort) ${conflictType} này không?" -Default "y") {
        switch ($conflictType) {
            "merge"        { & git merge --abort }
            "rebase"       { & git rebase --abort }
            "cherry-pick"  { & git cherry-pick --abort }
        }
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Không thể hủy bỏ ${conflictType}. Vui lòng xử lý thủ công." -ForegroundColor $C_Err
            exit 1
        }
        Write-Host "✅ Đã hủy bỏ ${conflictType}. Bạn có thể chạy lại script sau." -ForegroundColor $C_Succ
        exit 0
    }

    # Người dùng muốn tự giải quyết
    Write-Host "`n🔧 HƯỚNG DẪN GIẢI QUYẾT ${conflictType}:" -ForegroundColor $C_Info
    Write-Host "   1. Xem các file bị conflict: git diff --name-only --diff-filter=U"
    Write-Host "   2. Sửa từng file (tìm <<<<<<<, =======, >>>>>>>) rồi git add <file>"
    if ($conflictType -eq "merge") {
        Write-Host "   3. Khi đã giải quyết xong: git commit (hoặc git merge --continue)"
    } else {
        Write-Host "   3. Khi đã giải quyết xong: git ${conflictType} --continue"
    }
    Write-Host "   Hoặc để hủy bỏ toàn bộ: git ${conflictType} --abort"

    # Hỏi xem danh sách file conflict ngay
    if (Confirm-YesNo "`nBạn có muốn xem danh sách file conflict không?" -Default "y") {
        $conflictFiles = & git diff --name-only --diff-filter=U 2>$null
        if ($conflictFiles) {
            Write-Host "`n   📄 File conflict:" -ForegroundColor $C_Warn
            $conflictFiles | ForEach-Object { Write-Host "      $_" -ForegroundColor $C_Warn }
        } else {
            Write-Host "   ℹ️  Không tìm thấy file conflict (có thể đã được giải quyết?)." -ForegroundColor $C_Gray
        }
    }

    # Hỏi mở file conflict trong editor
    if (Confirm-YesNo "Bạn có muốn mở file conflict trong editor không?" -Default "n") {
        if ($conflictFiles) {
            foreach ($f in $conflictFiles) {
                try {
                    if ($env:EDITOR) {
                        & $env:EDITOR $f
                    } elseif ($IsWindowsEnv) {
                        Start-Process notepad $f
                    } else {
                        & 'vi' $f
                    }
                } catch {
                    Write-Host "   ⚠️  Không thể mở $f" -ForegroundColor $C_Warn
                }
            }
        } else {
            Write-Host "   ⚠️  Chưa có danh sách file conflict. Vui lòng chạy lại tùy chọn xem trước." -ForegroundColor $C_Warn
        }
    }

    Write-Host "`n👉 Sau khi giải quyết xong, chạy lại script này." -ForegroundColor $C_Warn
    exit 1
}

# ==============================================================================
# MAIN
# ==============================================================================
$cfg = Import-Config $ConfigPath
Show-Header
Initialize-SshKey

$env:GIT_PAGER = 'cat'
$env:PAGER     = 'cat'

# BƯỚC 0 – KIỂM TRA MÔI TRƯỜNG
Write-StepTitle "KIỂM TRA MÔI TRƯỜNG"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Git chưa cài hoặc không có trong PATH." -ForegroundColor $C_Err; exit 1
}

$null = & git rev-parse --is-inside-work-tree 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "⚠️ Thư mục này chưa được đồng bộ với GitHub." -ForegroundColor $C_Warn; 
    
    if (-not (Confirm-YesNo "Bạn có muốn khởi tạo và GHI ĐÈ dữ liệu từ GitHub về máy này không?" -Default "n")) {
        Write-Host "❌ Đã hủy. Script yêu cầu Git repository để hoạt động." -ForegroundColor $C_Err
        exit 1
    }

    $repoUrl = if (-not [string]::IsNullOrWhiteSpace($RepoUrl)) { $RepoUrl }
           elseif ($NonInteractive -or $Yes) { Write-Host "❌ Cần -RepoUrl khi dùng -Yes/-NonInteractive"; exit 1 }
           else { Read-Host "🔗 Nhập URL..." }
    if ([string]::IsNullOrWhiteSpace($repoUrl)) {
        Write-Host "❌ URL không hợp lệ. Hủy bỏ." -ForegroundColor $C_Err; exit 1
    }

    Write-Host "🚀 Đang tiến hành thiết lập ban đầu..." -ForegroundColor $C_Info
    & git init
    if ($LASTEXITCODE -ne 0) { Write-Host "❌ git init thất bại." -ForegroundColor $C_Err; exit 1 }

    & git remote add origin $repoUrl
    if ($LASTEXITCODE -ne 0) { Write-Host "❌ Không thể thêm remote '$repoUrl'." -ForegroundColor $C_Err; exit 1 }

    & git fetch origin --prune
    if ($LASTEXITCODE -ne 0) { Write-Host "❌ Fetch thất bại — kiểm tra URL và kết nối mạng." -ForegroundColor $C_Err; exit 1 }
    
    $lsRemote    = (& git ls-remote --symref origin HEAD 2>$null) -join "`n"
    $remoteBranch = "main"
    if ($lsRemote -match "ref: refs/heads/(?<branch>\S+)\s+HEAD") {
        $remoteBranch = $Matches.branch
        Write-SubLog "Nhánh chính" "Phát hiện '$remoteBranch' trên GitHub" $C_Succ
    }

    Write-Host "🔥 Đang ghi đè dữ liệu từ nhánh '$remoteBranch'..." -ForegroundColor $C_Warn
    & git checkout -B $remoteBranch "origin/$remoteBranch" -f
    if ($LASTEXITCODE -ne 0) { Write-Host "❌ Checkout '$remoteBranch' thất bại." -ForegroundColor $C_Err; exit 1 }

    & git branch --set-upstream-to="origin/$remoteBranch" "$remoteBranch"
    
    Write-Host "✅ Đã đồng bộ thành công! Tiếp tục quy trình gsync..." -ForegroundColor $C_Succ
}

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

# Kiểm tra trạng thái rebase/merge/cherry-pick đang dang dở (từ lần chạy trước)
$inProgress = Get-GitConflictType
if ($inProgress) {
    Write-Host "`n⚠️ Git đang trong trạng thái ${inProgress} chưa hoàn tất." -ForegroundColor $C_Warn
    Write-Host "   Trạng thái này thường gây lỗi 'detached HEAD' hoặc không xác định được nhánh."
    if (Confirm-YesNo "Bạn có muốn hủy bỏ (abort) ${inProgress} này không?" -Default "y") {
        switch ($inProgress) {
            "rebase"       { & git rebase --abort }
            "merge"        { & git merge --abort }
            "cherry-pick"  { & git cherry-pick --abort }
        }
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Không thể hủy bỏ ${inProgress}. Vui lòng xử lý thủ công." -ForegroundColor $C_Err
            exit 1
        }
        Write-Host "✅ Đã hủy bỏ ${inProgress}. Tiếp tục script..." -ForegroundColor $C_Succ
    } else {
        # Gọi hàm xử lý xung đột (hiển thị hướng dẫn và thoát)
        Handle-GitConflict
    }
}

# Xác định nhánh
$localBranch = (& git branch --show-current 2>$null)
if ([string]::IsNullOrWhiteSpace($localBranch)) {
    $localBranch = (& git rev-parse --abbrev-ref HEAD 2>$null)
}
if ([string]::IsNullOrWhiteSpace($localBranch) -or $localBranch -eq 'HEAD') {
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

$upstreamRaw = (& git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null)
$upstreamRef = if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($upstreamRaw)) {
    $upstreamRaw
} else {
    "$remoteName/$localBranch"
}

$remoteBranchRef   = $upstreamRef
$remoteBranchShort = ($remoteBranchRef -split '/', 2)[-1]
if ([string]::IsNullOrWhiteSpace($remoteBranchShort)) { $remoteBranchShort = $localBranch }

$null = & git rev-parse $remoteBranchRef 2>$null
$remoteExists = ($LASTEXITCODE -eq 0)

Write-SubLog "Nhánh local"     $localBranch      $C_Info
Write-SubLog "Remote tracking" $remoteBranchRef  $C_Gray
if (-not $remoteExists) {
    Write-SubLog "Remote branch" "Chưa tồn tại — sẽ tạo khi push" $C_Warn
}

# BƯỚC 1 – .GITIGNORE & DỌN RÁC
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
            Add-Content $ignoreFile $pStr -Encoding UTF8; $added++
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
            $escaped = [regex]::Escape($d)
            if ($fullPath -match "(^|[$([regex]::Escape($SEP))/])$escaped([$([regex]::Escape($SEP))/]|$)") {
                return $true
            }
        }
        return $false
    }

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

# BƯỚC 2 – FETCH & AHEAD/BEHIND
Write-StepTitle "PHÂN TÍCH THAY ĐỔI"
Write-SubLog "Remote" "Đang fetch..." $C_Gray

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

# BƯỚC 3 – PULL
$Script:StashName = $null

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
                # Pull thất bại – gọi hàm xử lý conflict
                if ($stashed) { Invoke-PopStash }   # Trả lại thay đổi trước khi xử lý
                Handle-GitConflict
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

# BƯỚC 4 – QUÉT FILE NHẠY CẢM
function Test-SensitiveFile([string]$path) {
    if ($cfg.sensitive.enabled -ne $true) { return $false }
    foreach ($a in @($cfg.sensitive.allowedPatterns)) { if ($path -match $a) { return $false } }
    foreach ($p in @($cfg.sensitive.blockedPatterns))  { if ($path -match $p) { return $true  } }
    return $false
}

# BƯỚC 5 – THAY ĐỔI CỤC BỘ
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

# BƯỚC 6 – COMMIT
if (-not (Confirm-YesNo "Bạn có muốn COMMIT những thay đổi này không?" -Default "y")) {
    Write-SubLog "Commit" "Đã bỏ qua" $C_Gray
} else {
    & git add -A
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ git add thất bại." -ForegroundColor $C_Err; exit 1
    }

    if ($cfg.artifactUnstage.enabled -eq $true) {
        $stagedNow   = @(& git diff --cached --name-only 2>$null)
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

# BƯỚC 7 – PUSH
if (-not (Confirm-YesNo "Bạn có muốn PUSH lên remote không?" -Default "y")) {
    Write-Host "⏭️ Đã bỏ qua PUSH." -ForegroundColor $C_Gray
} else {
    Write-Host "`n🚀 Đang PUSH lên $remoteName/$localBranch ..." -ForegroundColor $C_Info

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
            Handle-GitConflict   # Gọi hàm xử lý conflict chung
        }

        & git push $remoteName $localBranch
        if ($LASTEXITCODE -ne 0) {
            Write-Host "`n⚠️ Vẫn lỗi push." -ForegroundColor $C_Warn
            if (Confirm-YesNo "Thử force-with-lease? (chỉ dùng khi bạn chắc)" -Default "n") {
                & git --no-pager fetch $remoteName 2>$null | Out-Null
                & git push $remoteName $localBranch --force-with-lease
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

Remove-Item Env:GIT_PAGER -ErrorAction SilentlyContinue
Remove-Item Env:PAGER     -ErrorAction SilentlyContinue