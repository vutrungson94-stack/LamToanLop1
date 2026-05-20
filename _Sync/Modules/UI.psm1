# UI.psm1
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
"@ -ForegroundColor $global:C_Header
}

function Write-StepTitle([string]$Title, [string]$Color = "Cyan") {
    $w = Get-ConsoleWidth
    $padding = [Math]::Max(0, $w - $Title.Length - 12)
    Write-Host "`n── [ $Title ] $('─' * $padding)" -ForegroundColor $Color
}

function Write-SubLog([string]$Label, [string]$Value, [string]$Color = "White") {
    Write-Host "  $Label" -NoNewline -ForegroundColor $global:C_Gray
    Write-Host (": $Value") -ForegroundColor $Color
}

function Confirm-YesNo {
    param([string]$Question, [string]$Default = "y")
    if ($global:No) { return $false }
    if ($global:Yes) { return $true }
    if ($global:NonInteractive) { return ($Default -eq "y") }
    $suffix = if ($Default -eq "y") { "(y/n) [Mặc định: y]" } else { "(y/n) [Mặc định: n]" }
    $ans = Read-Host "$Question $suffix"
    if ([string]::IsNullOrWhiteSpace($ans)) { return ($Default -eq "y") }
    return ($ans.Trim().ToLowerInvariant() -eq "y")
}

Export-ModuleMember -Function Get-ConsoleWidth, Show-Header, Write-StepTitle, Write-SubLog, Confirm-YesNo