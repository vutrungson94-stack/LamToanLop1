# Cleanup.psm1
function Remove-JunkFiles {
    param([string[]]$Patterns, [string[]]$RestrictDirs, [bool]$Confirm, [switch]$DryRun)
    $junk = @()
    foreach ($dir in $RestrictDirs) {
        if (-not (Test-Path $dir)) { continue }
        foreach ($pat in $Patterns) {
            $junk += Get-ChildItem -Path $dir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $pat }
        }
    }
    $junk = $junk | Sort-Object FullName -Unique
    if ($junk.Count -eq 0) { return }
    Write-Log "Phát hiện $($junk.Count) file rác." -Level Warn
    if ($Confirm -and (-not $DryRun)) {
        if (-not (Confirm-YesNo "Xóa $($junk.Count) file rác?" -Default "n")) { return }
    }
    foreach ($f in $junk) {
        if ($DryRun) {
            Write-Log "[DRY RUN] Sẽ xóa $($f.FullName)" -Level Info
        } else {
            Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
            Write-Log "Đã xóa $($f.Name)" -Level Info
        }
    }
    if (-not $DryRun) { Write-Log "Đã xóa $($junk.Count) file rác." -Level Success }
}

function Find-LargeFiles {
    param([double]$ThresholdMB, [string[]]$ExcludeDirs)
    $thresholdBytes = $ThresholdMB * 1MB
    $allFiles = Get-ChildItem -Path . -Recurse -File -ErrorAction SilentlyContinue
    # Parallel filtering for PS7+
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $largeFiles = $allFiles | ForEach-Object -Parallel {
            $f = $_
            $exclude = $using:ExcludeDirs
            $threshold = $using:thresholdBytes
            $excluded = $false
            foreach ($d in $exclude) {
                if ($f.FullName -match "(^|[$([regex]::Escape([IO.Path]::DirectorySeparatorChar))])$d($|[$([regex]::Escape([IO.Path]::DirectorySeparatorChar))])") {
                    $excluded = $true; break
                }
            }
            if (-not $excluded -and $f.Length -gt $threshold) { $f }
        }
    } else {
        $largeFiles = @()
        foreach ($f in $allFiles) {
            $excluded = $false
            foreach ($d in $ExcludeDirs) {
                if ($f.FullName -match "(^|[$([regex]::Escape([IO.Path]::DirectorySeparatorChar))])$d($|[$([regex]::Escape([IO.Path]::DirectorySeparatorChar))])") {
                    $excluded = $true; break
                }
            }
            if (-not $excluded -and $f.Length -gt $thresholdBytes) { $largeFiles += $f }
        }
    }
    return $largeFiles
}

function Show-LargeFiles {
    param([object[]]$Files, [int]$MaxDisplay = 25)
    $count = $Files.Count
    for ($i = 0; $i -lt [Math]::Min($count, $MaxDisplay); $i++) {
        $f = $Files[$i]
        Write-SubLog "(!) $($f.Name)" "$([Math]::Round($f.Length/1MB,2)) MB" $global:C_Warn
    }
    if ($count -gt $MaxDisplay) {
        Write-Host "  ... và $($count - $MaxDisplay) file nữa." -ForegroundColor $global:C_Gray
    }
}

Export-ModuleMember -Function Remove-JunkFiles, Find-LargeFiles, Show-LargeFiles