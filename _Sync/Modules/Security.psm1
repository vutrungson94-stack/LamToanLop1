# Security.psm1
function Update-Gitignore {
    param([string[]]$Rules)
    $ignoreFile = ".gitignore"
    if (-not (Test-Path $ignoreFile)) {
        New-Item -ItemType File -Path $ignoreFile -Force | Out-Null
        Write-SubLog ".gitignore" "Đã tạo mới" $global:C_Succ
    }
    $current = @(Get-Content $ignoreFile -ErrorAction SilentlyContinue | ForEach-Object { $_.TrimEnd() })
    $added = 0
    foreach ($rule in $Rules) {
        $ruleStr = [string]$rule
        if (-not ($current -contains $ruleStr)) {
            [System.IO.File]::AppendAllText((Resolve-Path $ignoreFile).Path, "$ruleStr`n", [System.Text.UTF8Encoding]::new($false))
            $added++
        }
    }
    if ($added -gt 0) { Write-SubLog ".gitignore" "Đã thêm $added quy tắc" $global:C_Succ }
    else { Write-SubLog ".gitignore" "Đã an toàn" $global:C_Gray }
}

function Test-SensitiveFiles {
    param([string[]]$Status, $Config)
    $blocked = @()
    foreach ($line in $Status) {
        if (-not $line -or $line.Length -lt 3) { continue }
        $rawPath = $line.Substring(3).Trim()
        if ($rawPath.StartsWith('"') -and $rawPath.EndsWith('"')) {
            $rawPath = $rawPath.Substring(1, $rawPath.Length - 2)
        }
        $isAllowed = $false
        foreach ($a in $Config.sensitive.allowedPatterns) {
            if ($rawPath -match $a) { $isAllowed = $true; break }
        }
        if ($isAllowed) { <# hiển thị bình thường #>; continue }

        $isSensitive = $false
        foreach ($p in $Config.sensitive.blockedPatterns) {
            if ($rawPath -match $p) { $isSensitive = $true; break }
        }
        if ($isSensitive) {
            $blocked += $rawPath
            Write-Host "  🚫 [BLOCKED] $rawPath" -ForegroundColor $global:C_Err
        } else {
            $code = $line.Substring(0, 2).Trim()
            $color = switch -Regex ($code) {
                '^A' { 'Green' }; '^M' { 'Cyan' }; '^D' { 'Red' }; default { 'Gray' }
            }
            Write-Host "  [$code] $rawPath" -ForegroundColor $color
        }
    }
    return $blocked
}

Export-ModuleMember -Function Update-Gitignore, Test-SensitiveFiles