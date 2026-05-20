# GitUtils.psm1
function Initialize-SshKey {
    $sshKeyPath = Join-Path $PSScriptRoot 'ssh_id'
    if (-not (Test-Path $sshKeyPath)) { return }
    $resolved = (Resolve-Path $sshKeyPath).Path
    $escaped = $resolved -replace '"', '\"'
    $env:GIT_SSH_COMMAND = "ssh -i `"$escaped`" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
    Write-SubLog "SSH Key" "Đã nạp ($resolved)" $global:C_Succ
}

function Test-GitVersion {
    param([string]$Minimum)
    $v = & git --version 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
    if ($v -match '(\d+\.\d+\.\d+)') {
        $ver = [version]$matches[1]
        $min = [version]$Minimum
        return $ver -ge $min
    }
    return $false
}

function Test-GitRepository {
    $null = & git rev-parse --is-inside-work-tree 2>&1
    return $LASTEXITCODE -eq 0
}

function Initialize-GitRepository {
    param([string]$RepoUrl)
    Write-Log "Khởi tạo repo mới từ $RepoUrl" -Level Info
    & git init
    if ($LASTEXITCODE -ne 0) { throw "git init thất bại" }
    $null = & git remote get-url origin 2>$null
    if ($LASTEXITCODE -eq 0) {
        & git remote set-url origin $RepoUrl
    } else {
        & git remote add origin $RepoUrl
    }
    & git fetch origin --prune
    $lsRemote = (& git ls-remote --symref origin HEAD 2>$null) -join "`n"
    $branch = "main"
    if ($lsRemote -match "ref: refs/heads/(?<b>\S+)\s+HEAD") { $branch = $Matches.b }
    & git checkout -B $branch "origin/$branch" -f
    & git branch --set-upstream-to="origin/$branch" $branch
    Write-Log "Đã đồng bộ repo thành công." -Level Success
}

function Clear-GitLock {
    $lockFile = Join-Path (Get-Location) ".git/index.lock"
    if (Test-Path $lockFile) {
        Write-Log "Phát hiện index.lock, đang xóa..." -Level Warn
        Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
        if (Test-Path $lockFile) {
            throw "Không thể xóa lock file"
        }
        Write-Log "Đã xóa lock" -Level Success
    }
}

function Get-GitConflictType {
    $gitDir = & git rev-parse --git-dir 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $gitDir) { return $null }
    if ((Test-Path (Join-Path $gitDir "rebase-merge")) -or (Test-Path (Join-Path $gitDir "rebase-apply"))) { return "rebase" }
    if (Test-Path (Join-Path $gitDir "MERGE_HEAD")) { return "merge" }
    if (Test-Path (Join-Path $gitDir "CHERRY_PICK_HEAD")) { return "cherry-pick" }
    return $null
}

function Invoke-GitAbort {
    param([string]$ConflictType)
    switch ($ConflictType) {
        "rebase" { & git rebase --abort }
        "merge" { & git merge --abort }
        "cherry-pick" { & git cherry-pick --abort }
    }
    if ($LASTEXITCODE -ne 0) { throw "Không thể abort $ConflictType" }
    Write-Log "Đã abort $ConflictType" -Level Success
}

function Invoke-GitConflictHandler {
    param([string]$ConflictType)
    Write-Host "`n⚠️ Xung đột $ConflictType!" -ForegroundColor $global:C_Warn
    Write-Host "   Hướng dẫn giải quyết:" -ForegroundColor $global:C_Info
    Write-Host "   1. Xem file conflict: git diff --name-only --diff-filter=U"
    Write-Host "   2. Sửa file, rồi git add"
    Write-Host "   3. git $ConflictType --continue"
    Write-Host "   Hoặc hủy: git $ConflictType --abort"
    if (Confirm-YesNo "Hiển thị danh sách file conflict?" -Default "y") {
        $files = & git diff --name-only --diff-filter=U 2>$null
        if ($files) { $files | ForEach-Object { Write-Host "      $_" -ForegroundColor $global:C_Warn } }
    }
    throw "Conflict detected"
}

function Get-CurrentBranch {
    $branch = & git branch --show-current 2>$null
    if (-not $branch) {
        $branch = & git rev-parse --abbrev-ref HEAD 2>$null
    }
    if (-not $branch -or $branch -eq 'HEAD') {
        $fallback = $cfg.git.defaultBranchFallback
        if ($global:NonInteractive -or $global:Yes) { $branch = $fallback }
        else {
            $inp = Read-Host "Nhập tên nhánh (Enter = $fallback)"
            $branch = if ([string]::IsNullOrWhiteSpace($inp)) { $fallback } else { $inp }
        }
    }
    return $branch
}

function Get-UpstreamBranch {
    param([string]$RemoteName, [string]$LocalBranch)
    $upstream = & git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null
    if ($LASTEXITCODE -eq 0 -and $upstream) { return $upstream }
    return "$RemoteName/$LocalBranch"
}

function Test-RemoteBranch {
    param([string]$RemoteName, [string]$Branch)
    $null = & git rev-parse "$Branch" 2>$null
    return $LASTEXITCODE -eq 0
}

function Invoke-GitFetch {
    param([string]$RemoteName, [int]$Retry = 3)
    for ($i = 1; $i -le $Retry; $i++) {
        Write-Log "Fetch từ $RemoteName (lần $i/$Retry)..." -Level Info
        & git fetch $RemoteName --prune
        if ($LASTEXITCODE -eq 0) { return $true }
        if ($i -lt $Retry) { Start-Sleep -Seconds 5 }
    }
    Write-Error "Fetch thất bại sau $Retry lần thử."
    return $false
}

function Get-AheadBehind {
    param([string]$LocalBranch, [string]$RemoteBranch)
    $localCommit = & git rev-parse HEAD 2>$null
    $remoteCommit = & git rev-parse $RemoteBranch 2>$null
    if (-not $localCommit -or -not $remoteCommit -or $localCommit -eq $remoteCommit) { return 0,0 }
    $ab = & git rev-list --left-right --count "$localCommit...$remoteCommit" 2>$null
    if ($ab -match '(\d+)\s+(\d+)') { return [int]$Matches[1], [int]$Matches[2] }
    return 0,0
}

function Invoke-GitPull {
    param([string]$RemoteName, [string]$Branch, [int]$Retry = 3)
    for ($i = 1; $i -le $Retry; $i++) {
        Write-Log "Pull $RemoteName/$Branch (lần $i/$Retry)..." -Level Info
        & git pull $RemoteName $Branch
        if ($LASTEXITCODE -eq 0) { return $true }
        if ($i -lt $Retry) { Start-Sleep -Seconds 5 }
    }
    return $false
}

function Invoke-GitPush {
    param([string]$RemoteName, [string]$Branch, [string]$Upstream, [bool]$RemoteExists, [int]$Retry = 3)
    for ($i = 1; $i -le $Retry; $i++) {
        Write-Log "Push $Branch lên $RemoteName (lần $i/$Retry)..." -Level Info
        if (-not $RemoteExists) {
            & git push --set-upstream $RemoteName $Branch
        } else {
            & git push $RemoteName $Branch
        }
        if ($LASTEXITCODE -eq 0) { return $true }
        if ($i -lt $Retry) {
            Write-Log "Push thất bại, thử pull --rebase..." -Level Warn
            & git pull --rebase $RemoteName $Upstream
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Pull --rebase thất bại, không thể retry push."
                return $false
            }
            Start-Sleep -Seconds 3
        }
    }
    return $false
}

function Invoke-StashIfDirty {
    $dirty = & git status --porcelain 2>$null
    if ($dirty.Count -eq 0) { return $false }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $stashName = "gsync-auto-$stamp"
    & git stash push -u -m $stashName
    if ($LASTEXITCODE -eq 0) {
        Write-SubLog "Stash" "Đã lưu ($stashName)" $global:C_Info
        $global:StashName = $stashName
        return $true
    }
    Write-Warn "Không thể stash"
    return $false
}

function Invoke-PopStash {
    if (-not $global:StashName) { return }
    $stashLine = & git stash list --format='%gd %s' | Where-Object { $_ -match [regex]::Escape($global:StashName) } | Select-Object -First 1
    if (-not $stashLine) { Write-Warn "Không tìm thấy stash '$global:StashName'"; return }
    $stashRef = ($stashLine -split ' ')[0]
    & git stash pop $stashRef
    if ($LASTEXITCODE -ne 0) {
        throw "Stash pop conflict. Hãy xử lý thủ công: git stash pop $stashRef"
    }
    Write-SubLog "Stash" "Đã khôi phục" $global:C_Succ
    $global:StashName = $null
}

function Get-GitStatus {
    @(& git status --porcelain 2>$null)
}

function Undo-Artifacts {
    param([string[]]$Patterns, [string[]]$ExtraPatterns)
    $allPatterns = $Patterns + $ExtraPatterns
    $staged = @(& git diff --cached --name-only 2>$null)
    foreach ($f in $staged) {
        foreach ($pat in $allPatterns) {
            if ($f -match $pat) {
                & git restore --staged -- $f 2>$null
                Write-SubLog "Gỡ artifact" $f $global:C_Warn
                break
            }
        }
    }
}

function New-CommitMessageSuggestion {
    param([string[]]$StagedFiles)
    $hasWorkflow = $StagedFiles | Where-Object { $_ -match '\.ya?ml$|\.github[/\\]' }
    $hasProj = $StagedFiles | Where-Object { $_ -match '\.(csproj|sln|gradle|pom\.xml)$' }
    $hasCode = $StagedFiles | Where-Object { $_ -match '\.(cs|js|ts|py|go|java|kt|swift|rs|ps1|sh)$' }
    if ($hasWorkflow) { return "ci: update workflows" }
    if ($hasProj) { return "build: update project files" }
    if ($hasCode) { return "feat: update $($hasCode.Count) code files" }
    return "chore: update at $(Get-Date -Format 'HH:mm dd/MM/yyyy')"
}

function Send-WebhookNotification {
    param($Config, [string]$Status, [string]$Message)
    if (-not $Config.webhook.enabled) { return }
    if ($Status -eq "success" -and -not $Config.webhook.onSuccess) { return }
    if ($Status -eq "failure" -and -not $Config.webhook.onFailure) { return }
    $body = @{
        status = $Status
        message = $Message
        repo = (Get-Location).Path
        timestamp = (Get-Date).ToString("o")
    } | ConvertTo-Json
    try {
        Invoke-RestMethod -Uri $Config.webhook.url -Method Post -Body $body -ContentType "application/json" -ErrorAction SilentlyContinue
        Write-Log "Webhook notification sent ($Status)" -Level Info
    } catch {
        Write-Warn "Không thể gửi webhook: $_"
    }
}

Export-ModuleMember -Function Initialize-SshKey, Test-GitVersion, Test-GitRepository, Initialize-GitRepository, Clear-GitLock, Get-GitConflictType, Invoke-GitAbort, Invoke-GitConflictHandler, Get-CurrentBranch, Get-UpstreamBranch, Test-RemoteBranch, Invoke-GitFetch, Get-AheadBehind, Invoke-GitPull, Invoke-GitPush, Invoke-StashIfDirty, Invoke-PopStash, Get-GitStatus, Unstage-Artifacts, Generate-CommitMessageSuggestion, Send-WebhookNotification