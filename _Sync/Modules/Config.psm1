# Config.psm1
function Get-DefaultConfig {
    $json = @'
{
  "_readme": "gsync config",
  "git": {
    "remoteName": "origin",
    "defaultBranchFallback": "main",
    "pullConflictPolicy": "ask",
    "stashWhenWorkingTreeDirty": true
  },
  "gitignore": {
    "enabled": true,
    "rulesToAdd": [ "# === SECURITY ===", "ssh_id", "*.pfx", ".env", "bin/", "obj/", "node_modules/", ".vs/", "*.apk", "*.aab" ]
  },
  "sensitive": {
    "enabled": true,
    "allowedPatterns": [ "\\.env\\.example$" ],
    "blockedPatterns": [ "\\.keystore$", "\\.env$", "secrets\\.json$" ]
  },
  "junkCleanup": {
    "enabled": true,
    "patterns": [ "*.tmp", "Thumbs.db" ],
    "restrictToDirs": [ "." ],
    "confirmBeforeDelete": false
  },
  "largeFiles": {
    "enabled": true,
    "excludeDirs": [ ".git", "node_modules" ]
  },
  "artifactUnstage": {
    "enabled": true,
    "patterns": [ "\\.(apk|aab|ipa|msix)$" ],
    "extraPatterns": [ "publish-output/" ]
  },
  "ui": {
    "largeFileThresholdMB": 90
  },
  "webhook": {
    "enabled": false,
    "url": "",
    "onSuccess": true,
    "onFailure": true
  }
}
'@
    return ($json | ConvertFrom-Json)
}

function Import-Config {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        Write-Log "Không tìm thấy config, tạo mặc định..." -Level Info
        $cfg = Get-DefaultConfig
        try {
            $jsonOut = $cfg | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($Path, $jsonOut, [System.Text.UTF8Encoding]::new($false))
            Write-Log "Đã tạo config mới: $Path" -Level Success
        } catch {
            Write-Warn "Không thể ghi config: $_"
        }
        return $cfg
    }
    try {
        $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        return ($raw | ConvertFrom-Json)
    } catch {
        Write-Error "Lỗi parse config: $($_.Exception.Message)"
        return $null
    }
}

Export-ModuleMember -Function Get-DefaultConfig, Import-Config