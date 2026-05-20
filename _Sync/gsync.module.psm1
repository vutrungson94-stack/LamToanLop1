# gsync.module.psm1
$moduleRoot = $PSScriptRoot
$modulesDir = Join-Path $moduleRoot "Modules"

Import-Module (Join-Path $modulesDir "Logging.psm1") -Force -Global
Import-Module (Join-Path $modulesDir "Config.psm1") -Force -Global
Import-Module (Join-Path $modulesDir "GitUtils.psm1") -Force -Global
Import-Module (Join-Path $modulesDir "Security.psm1") -Force -Global
Import-Module (Join-Path $modulesDir "Cleanup.psm1") -Force -Global
Import-Module (Join-Path $modulesDir "UI.psm1") -Force -Global

function Start-GSync {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$NonInteractive,
        [switch]$Yes,
        [switch]$No,
        [string]$ConfigPath,
        [string]$RepoUrl,
        [string]$RemoteName,
        [switch]$DryRun
    )

    $Global:StartTime = Get-Date   # ← Fix: đặt vào đây, không phải ngoài module
    $global:NonInteractive = $NonInteractive
    $global:Yes = $Yes
    $global:No = $No
    $global:DryRun = $DryRun

    if ($Yes -and $No) {
        Write-Error "❌ Không thể dùng -Yes và -No cùng lúc."
        exit 1
    }

    # Khởi tạo logging
    $logFile = Join-Path $moduleRoot ".gsync.log"
    Start-Log -Path $logFile -Level "Info"

    # Load config
    $cfg = Import-Config -Path $ConfigPath
    if (-not $cfg) { exit 1 }

    Show-Header
    Initialize-SshKey

    # Kiểm tra git version
    if (-not (Test-GitVersion -Minimum "2.20")) {
        Write-Log "⚠️ Git version quá cũ, một số tính năng có thể không hoạt động." -Level Warn
    }

    # Kiểm tra môi trường Git
    if (-not (Test-GitRepository)) {
        Write-Log "⚠️ Thư mục hiện tại chưa phải Git repo." -Level Warn
        if (-not (Confirm-YesNo "Bạn có muốn khởi tạo và GHI ĐÈ dữ liệu từ GitHub về máy này không?" -Default "n")) {
            Write-Log "❌ Hủy bỏ. Script yêu cầu Git repository để hoạt động." -Level Error
            exit 1
        }
        $repoUrl = if (-not [string]::IsNullOrWhiteSpace($RepoUrl)) { $RepoUrl }
                   elseif ($NonInteractive -or $Yes) { Write-Log "Cần -RepoUrl khi dùng -Yes/-NonInteractive" -Level Error; exit 1 }
                   else { Read-Host "🔗 Nhập URL" }
        $initOk = Initialize-GitRepository -RepoUrl $repoUrl
        if (-not $initOk) { exit 1 }
    }

    # Giải phóng lock nếu có
    Clear-GitLock

    # Xử lý rebase/merge đang dang dở
    $inProgress = Get-GitConflictType
    if ($inProgress) {
        Write-Log "⚠️ Git đang trong trạng thái $inProgress chưa hoàn tất." -Level Warn
        if (Confirm-YesNo "Hủy bỏ (abort) $inProgress?" -Default "y") {
            Invoke-GitAbort -ConflictType $inProgress
        } else {
            Invoke-GitConflictHandler -ConflictType $inProgress
            exit 1
        }
    }

    # Lấy thông tin nhánh
    $localBranch = Get-CurrentBranch -Config $cfg
    $remoteName = if ($RemoteName) { $RemoteName } else { [string]$cfg.git.remoteName }
    $upstream = Get-UpstreamBranch -RemoteName $remoteName -LocalBranch $localBranch
    $remoteExists = Test-RemoteBranch -RemoteName $remoteName -Branch $upstream

    Write-SubLog "Nhánh local" $localBranch $global:C_Info
    Write-SubLog "Remote tracking" "$remoteName/$upstream" $global:C_Gray
    if (-not $remoteExists) {
        Write-SubLog "Remote branch" "Chưa tồn tại — sẽ tạo khi push" $global:C_Warn
    }

    # Bước 1: .gitignore & dọn rác
    Write-StepTitle "BẢO VỆ & DỌN DẸP"
    if ($cfg.gitignore.enabled) {
        Update-Gitignore -Rules $cfg.gitignore.rulesToAdd
    }
    if ($cfg.junkCleanup.enabled) {
        Remove-JunkFiles -Patterns $cfg.junkCleanup.patterns -RestrictDirs $cfg.junkCleanup.restrictToDirs -Confirm:$cfg.junkCleanup.confirmBeforeDelete -DryRun:$DryRun
    }

    # Bước 2: Phát hiện file lớn
    if ($cfg.largeFiles.enabled) {
        $thresholdMB = [double]$cfg.ui.largeFileThresholdMB
        $excludeDirs = @($cfg.largeFiles.excludeDirs)
        $largeFiles = Find-LargeFiles -ThresholdMB $thresholdMB -ExcludeDirs $excludeDirs
        if ($largeFiles.Count -gt 0) {
            Write-Log "⚠️ Phát hiện $($largeFiles.Count) file lớn (> ${thresholdMB}MB)" -Level Warn
            Show-LargeFiles -Files $largeFiles -MaxDisplay 25
            if (-not (Confirm-YesNo "Tiếp tục?" -Default "n")) { exit 1 }
        }
    }

    # Bước 3: Fetch và phân tích ahead/behind
    Write-StepTitle "PHÂN TÍCH THAY ĐỔI"
    $fetchResult = Invoke-GitFetch -RemoteName $remoteName -Retry 3
    if (-not $fetchResult) { exit 1 }

    $commitsAhead, $commitsBehind = Get-AheadBehind -LocalBranch $localBranch -RemoteBranch "$remoteName/$upstream"
    Write-SubLog "Local ahead" "$commitsAhead commit(s)" $(if ($commitsAhead -gt 0) { $global:C_Warn } else { $global:C_Succ })
    Write-SubLog "Remote behind" "$commitsBehind commit(s)" $(if ($commitsBehind -gt 0) { $global:C_Warn } else { $global:C_Succ })

    # Bước 4: Pull nếu cần (có retry)
    $stashed = $false
    if ($commitsBehind -gt 0) {
        Write-Log "Remote có $commitsBehind commit mới." -Level Warn
        $policy = [string]$cfg.git.pullConflictPolicy
        $shouldPull = switch ($policy) {
            "always" { $true }
            "never" { $false }
            "ask" { Confirm-YesNo "Pull code mới?" -Default "y" }
            default { Confirm-YesNo "Pull code mới?" -Default "y" }
        }
        if ($shouldPull) {
            if ($cfg.git.stashWhenWorkingTreeDirty) {
                $stashed = Invoke-StashIfDirty
            }
            Write-Progress -Activity "Pulling from remote..." -Status "Fetching changes"
            $pullSuccess = Invoke-GitPull -RemoteName $remoteName -Branch $upstream -Retry 3
            Write-Progress -Activity "Pulling from remote..." -Completed
            if (-not $pullSuccess) {
                if ($stashed) { Invoke-PopStash }
                Invoke-GitConflictHandler
                exit 1
            }
            if ($stashed) { Invoke-PopStash }
            Write-SubLog "Pull" "Thành công" $global:C_Succ
        } else {
            Write-SubLog "Pull" "Bỏ qua" $global:C_Gray
        }
    }

    # Bước 5: Kiểm tra thay đổi cục bộ
    $status = Get-GitStatus
    if ($status.Count -eq 0) {
        Write-StepTitle "HOÀN TẤT"
        Write-Host "✅ Không có thay đổi. Repo đã đồng bộ." -ForegroundColor $global:C_Succ
        Send-WebhookNotification -Config $cfg -Status "success" -Message "No local changes"
        Stop-Log
        exit 0
    }

    # Bước 6: Phát hiện file nhạy cảm
    Write-StepTitle "THAY ĐỔI CỤC BỘ"
    $blocked = Test-SensitiveFiles -Status $status -Config $cfg
    if ($blocked.Count -gt 0) {
        Write-Log "🚫 DỪNG LẠI — $($blocked.Count) file nhạy cảm bị chặn." -Level Error
        $blocked | ForEach-Object { Write-Host "   · $_" -ForegroundColor $global:C_Err }
        Write-Log "Thêm vào .gitignore và chạy: git rm --cached <file>" -Level Warn
        Send-WebhookNotification -Config $cfg -Status "failure" -Message "Sensitive files blocked"
        exit 1
    }

    # Bước 7: Commit
    if (-not (Confirm-YesNo "Commit các thay đổi?" -Default "y")) {
        Write-SubLog "Commit" "Bỏ qua" $global:C_Gray
        Stop-Log
        exit 0
    }

    & git add -A
    if ($LASTEXITCODE -ne 0) { Write-Error "git add thất bại"; exit 1 }

    if ($cfg.artifactUnstage.enabled) {
        Undo-Artifacts -Patterns $cfg.artifactUnstage.patterns -ExtraPatterns $cfg.artifactUnstage.extraPatterns
    }

    $staged = & git diff --cached --name-only
    if ($staged.Count -eq 0) {
        Write-Host "✅ Không còn file nào sau khi lọc artifact." -ForegroundColor $global:C_Succ
        Stop-Log
        exit 0
    }

    $suggestion = New-CommitMessageSuggestion -StagedFiles $staged
    $inp = Read-Host "✍️ Commit message (Enter = $suggestion)"
    $msg = if ([string]::IsNullOrWhiteSpace($inp)) { $suggestion } else { $inp }
    & git commit -m "$msg"
    if ($LASTEXITCODE -ne 0) { Write-Error "Commit thất bại"; exit 1 }
    Write-SubLog "Commit" "Thành công" $global:C_Succ

    # Bước 8: Push (retry, force-with-lease)
    if (-not (Confirm-YesNo "Push lên remote?" -Default "y")) {
        Write-Host "⏭️ Đã bỏ qua PUSH." -ForegroundColor $global:C_Gray
        Stop-Log
        exit 0
    }

    $pushSuccess = Invoke-GitPush -RemoteName $remoteName -Branch $localBranch -Upstream $upstream -RemoteExists $remoteExists -Retry 3
    if (-not $pushSuccess) {
        Write-Error "Push thất bại sau nhiều lần thử."
        Send-WebhookNotification -Config $cfg -Status "failure" -Message "Push failed"
        exit 1
    }

    $duration = (Get-Date) - $Global:StartTime
    Write-StepTitle "HOÀN TẤT TRONG $($duration.TotalSeconds.ToString('F1')) GIÂY" $global:C_Succ
    Send-WebhookNotification -Config $cfg -Status "success" -Message "Sync completed"
    Stop-Log

    # Cleanup environment variables
    Remove-Item Env:GIT_SSH_COMMAND -ErrorAction SilentlyContinue
    Remove-Item Env:GIT_PAGER -ErrorAction SilentlyContinue
    Remove-Item Env:PAGER -ErrorAction SilentlyContinue
    Remove-Item Env:GIT_CONFIG_PARAMETERS -ErrorAction SilentlyContinue
}

Export-ModuleMember -Function Start-GSync