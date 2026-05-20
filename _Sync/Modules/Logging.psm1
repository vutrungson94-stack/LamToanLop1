# Logging.psm1
$global:C_Header = "Magenta"
$global:C_Info   = "Cyan"
$global:C_Warn   = "Yellow"
$global:C_Err    = "Red"
$global:C_Succ   = "Green"
$global:C_Gray   = "DarkGray"

$script:LogFilePath = $null
$script:LogLevel = "Info"

function Start-Log {
    param([string]$Path, [string]$Level = "Info")
    $script:LogFilePath = $Path
    $script:LogLevel = $Level
    if (Test-Path $Path) { Remove-Item $Path -Force }
    Write-Log "=== Log started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" -Level Info
}

function Stop-Log {
    if ($script:LogFilePath) {
        Write-Log "=== Log ended at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" -Level Info
    }
}

function Write-Log {
    param([string]$Message, [string]$Level = "Info", [string]$Color = $null)
    if ($Level -eq "Debug" -and $script:LogLevel -ne "Debug") { return }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Level] $Message"
    if ($script:LogFilePath) {
        Add-Content -Path $script:LogFilePath -Value $logLine -Encoding UTF8
    }
    if ($Color) {
        Write-Host $Message -ForegroundColor $Color
    } elseif ($Level -eq "Error") {
        Write-Host $Message -ForegroundColor $global:C_Err
    } elseif ($Level -eq "Warn") {
        Write-Host $Message -ForegroundColor $global:C_Warn
    } elseif ($Level -eq "Success") {
        Write-Host $Message -ForegroundColor $global:C_Succ
    } else {
        Write-Host $Message
    }
}

function Write-Error { param($Message) Write-Log $Message -Level Error -Color $global:C_Err }
function Write-Warn  { param($Message) Write-Log $Message -Level Warn  -Color $global:C_Warn }
function Write-Info  { param($Message) Write-Log $Message -Level Info  -Color $global:C_Info }
function Write-Success{ param($Message) Write-Log $Message -Level Success -Color $global:C_Succ }

Export-ModuleMember -Variable C_Header, C_Info, C_Warn, C_Err, C_Succ, C_Gray
Export-ModuleMember -Function Start-Log, Stop-Log, Write-Log, Write-Error, Write-Warn, Write-Info, Write-Success