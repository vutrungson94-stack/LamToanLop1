# Modules/Logging.psm1
$global:C_Header = "Magenta"
$global:C_Info   = "Cyan"
$global:C_Warn   = "Yellow"
$global:C_Err    = "Red"
$global:C_Succ   = "Green"
$global:C_Gray   = "DarkGray"

# Độ rộng terminal (clamp 80–120)
$script:GW  = [Math]::Min([Math]::Max(([Console]::WindowWidth), 80), 120)
$script:GCL = [int]($script:GW * 0.60)

function Set-LogLevel { param([string]$Level) $script:LogLevel = $Level }

function Write-Log {
    [CmdletBinding()]
    param([string]$Message, [string]$Color = $null)
    if ($Color) {
        Write-Host "  $Message" -ForegroundColor $Color
    } else {
        Write-Host "  $Message"
    }
}

function _2Col {
    param([string]$L, [string]$R = "", [string]$LC = "White", [string]$RC = "DarkGray")
    $pad = [Math]::Max($script:GCL - $L.Length, 1)
    Write-Host $L  -NoNewline -ForegroundColor $LC
    Write-Host (' ' * $pad) -NoNewline
    if ($R) { Write-Host $R -ForegroundColor $RC }
    else    { Write-Host "" }
}

function Show-ProgressBar {
    param([int]$Current, [int]$Total, [string]$Label)
    if ($Total -le 0) { $Total = 1 }
    $pct  = [int][Math]::Min([Math]::Ceiling($Current / $Total * 100), 100)
    $fill = [int][Math]::Min([Math]::Floor($pct / 100.0 * 20), 20)
    $bar  = ("█" * $fill) + ("░" * (20 - $fill))
    Write-Host ""
    Write-Host "  [ $($pct.ToString('D2'))%] $bar  ▶ $Label" -ForegroundColor $global:C_Info
    Write-Host ("─" * $script:GW) -ForegroundColor $global:C_Gray
}

function Write-VisualBox {
    param(
        [string]$Text,
        [string]$Color = "White",
        [bool]  $ShowSeparator = $true,
        [switch]$Large
    )
    $padding = if ($Large) { "      " } else { "   " }
    $inner   = "$padding$Text$padding"
    $hLine   = "─" * $inner.Length
    if ($Large) { Write-Host "" }
    Write-Host "  ┌$hLine┐" -ForegroundColor $global:C_Gray
    if ($Large) { Write-Host "  │$(' ' * $inner.Length)│" -ForegroundColor $global:C_Gray }
    Write-Host "  │$inner│" -ForegroundColor $Color
    if ($Large) { Write-Host "  │$(' ' * $inner.Length)│" -ForegroundColor $global:C_Gray }
    Write-Host "  └$hLine┘" -ForegroundColor $global:C_Gray
    if ($ShowSeparator) { Write-Host "" }
}

function Write-StepTitle { 
    param(
        [string]$Text, 
        [string]$Color = "White", 
        [bool]$ShowSeparator = $true
    ) 
    Write-VisualBox -Text $Text -Color $Color -ShowSeparator $ShowSeparator 
}
function Write-SectionBox { 
    param(
        [string]$Title, 
        [string]$Color = "White"
    ) 
    Write-VisualBox -Text $Title -Color $Color -Large 
}
function Write-SubLog { 
    param(
        [string]$msg
    ) 
    Write-Host "  ▶ Đang xử lý: $msg..." -ForegroundColor Gray 
}
function Write-Done {
    param([string]$msg, [double]$secs = -1)
    $r = if ($secs -ge 0) { "[✅] Hoàn tất! ($($secs.ToString('F1'))s)" } else { "[✅] Hoàn tất!" }
    _2Col "  ✅ $msg" $r "Green" "DarkGray"
}
function Write-Fail {
    param([string]$msg, [double]$secs = -1)
    $r = if ($secs -ge 0) { "[❌] Thất bại! ($($secs.ToString('F1'))s)" } else { "[❌] Thất bại!" }
    _2Col "  ❌ $msg" $r "Red" "DarkGray"
}
function Write-Info { 
    param([string]$msg) {
        _2Col "  ℹ  $msg" "" $global:C_Info 
    } 
}
function Write-Warn { 
    param([string]$msg) {
        _2Col "  ⚠️  $msg" "" $global:C_Warn 
    } 
}
function Write-Sep  { 
    Write-Host ("─" * $script:GW) -ForegroundColor $global:C_Gray 
}

Export-ModuleMember -Function Set-LogLevel, Write-Log, _2Col, Show-ProgressBar, Write-VisualBox,
    Write-StepTitle, Write-SectionBox, Write-SubLog, Write-Done, Write-Fail, Write-Info, Write-Warn, Write-Sep