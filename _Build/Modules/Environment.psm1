# ==================================================================================================
# Modules/Environment.psm1
# ==================================================================================================

# ── Xác định hệ điều hành ───────────────────────────────────────────────────────
function Get-OSPlatform {
    if ($PSVersionTable.PSEdition -eq 'Core') {
        if ($IsWindows) { return 'Windows' }
        if ($IsLinux)   { return 'Linux' }
        if ($IsMacOS)   { return 'MacOS' }
    }
    if ([System.Environment]::OSVersion.Platform -eq 'Win32NT') { return 'Windows' }
    return 'Unknown'
}
$global:OS = Get-OSPlatform

# ── Thiết lập UTF-8 ────────────────────────────────────────────────────────────
if ($global:OS -eq 'Windows') {
    try { & chcp 65001 | Out-Null } catch {}
}
$OutputEncoding           = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8

# ── Thư mục gốc script ──────────────────────────────────────────────────────────
if (-not $global:ScriptRoot) {
    throw "ScriptRoot chưa được khởi tạo. Hãy set trước khi import module."
}

# ── File cache SDK ───────────────────────────────────────────────────────────
$global:CacheFile = Join-Path $global:ScriptRoot ".sdkcache.json"

# ── Danh sách file tạm cần dọn khi script kết thúc ─────────────────────────
$global:TempFiles = [System.Collections.Generic.List[string]]::new()

function Register-TempFile {
    param([string]$Path)
    if ($Path -and (Test-Path $Path)) {
        $global:TempFiles.Add($Path)
    }
}

# Đăng ký sự kiện dọn dẹp khi PowerShell thoát (PS Core)
if ($PSVersionTable.PSEdition -eq 'Core') {
    Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
        foreach ($f in $global:TempFiles) {
            if (Test-Path $f) {
                Remove-Item $f -Force -ErrorAction SilentlyContinue
            }
        }
    } | Out-Null
}

# Định nghĩa các biến cho Powershell 5.1/7+ compatibility
$global:IsPwsh7      = $PSVersionTable.PSVersion.Major -ge 7
$global:SupportsDepth = (Get-Command Get-ChildItem).Parameters.ContainsKey('Depth')

# ==================================================================================
# HÀM TIỆN ÍCH CHUNG
# ==================================================================================
function Get-RelativeDepth {
    param(
        [string]$Root,
        [string]$Child
    )
    try {
        $rootNorm = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
        $childNorm = [IO.Path]::GetFullPath($Child).TrimEnd('\','/')
        if ($childNorm.Length -le $rootNorm.Length) { return 0 }
        $relative = $childNorm.Substring($rootNorm.Length).TrimStart('\','/')
        if ([string]::IsNullOrWhiteSpace($relative)) { return 0 }
        return ($relative -split '[\\/]').Count
    }
    catch { return 999999 }
}

function Invoke-CompatibleChildItem {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$Filter = '*',
        [switch]$File,
        [switch]$Directory,
        [switch]$Recurse,
        [int]$Depth = 999
    )
    if (-not (Test-Path -Path $Path)) { return @() }
    $items = @()
    if ($global:SupportsDepth) {
        $gciArgs = @{ Path = $Path; Force = $true; ErrorAction = 'SilentlyContinue' }
        if ($Recurse)   { $gciArgs['Recurse'] = $true; $gciArgs['Depth'] = $Depth }
        if ($File)      { $gciArgs['File']      = $true }
        if ($Directory) { $gciArgs['Directory'] = $true }
        $items = Get-ChildItem @gciArgs
    } else {
        $gciArgs = @{ Path = $Path; Force = $true; ErrorAction = 'SilentlyContinue' }
        if ($Recurse) { $gciArgs['Recurse'] = $true }
        $items = Get-ChildItem @gciArgs
        if ($File)      { $items = $items | Where-Object { -not $_.PSIsContainer } }
        if ($Directory) { $items = $items | Where-Object { $_.PSIsContainer } }
        $items = $items | Where-Object { (Get-RelativeDepth -Root $Path -Child $_.FullName) -le $Depth }
    }
    if ($Filter -and $Filter -ne '*') {
        $items = $items | Where-Object { $_.Name -like $Filter }
    }
    return $items
}

function Get-SafePath {
    param([string]$path)
    if ([string]::IsNullOrWhiteSpace($path)) { return $path }
    if ($global:OS -ne 'Windows' -or ($path -notmatch '[\s\u0080-\uFFFF]')) {
        if (Test-Path $path) {
            return (Get-Item $path).FullName
        } else {
            return $path
        }
    }
    $absPath = (Get-Item -Path $path -ErrorAction SilentlyContinue).FullName
    if (-not $absPath) { return $path }
    if ($absPath -notmatch '[\s\u0080-\uFFFF]') { return $absPath }
    try {
        if (-not ([System.Management.Automation.PSTypeName]'GBuild.PathHelper').Type) {
            Add-Type -Namespace 'GBuild' -Name 'PathHelper' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode, SetLastError = true)]
public static extern uint GetShortPathName(string lpszLongPath, System.Text.StringBuilder lpszShortPath, uint cchBuffer);
'@ -ErrorAction Stop
        }
        $sb  = [System.Text.StringBuilder]::new(260)
        $len = [GBuild.PathHelper]::GetShortPathName($absPath, $sb, 260)
        if ($len -gt 0 -and $len -lt 260) { return $sb.ToString(0, [int]$len) }
    } catch {}
    try {
        $fso = New-Object -ComObject Scripting.FileSystemObject
        return $fso.GetFile($absPath).ShortPath
    } catch { return $absPath }
}

function Update-VSCodeDotnetPath {
    param([string]$DotnetExePath)
    if ([string]::IsNullOrWhiteSpace($DotnetExePath) -or -not (Test-Path -Path $DotnetExePath)) { return }
    $vscodeDir    = Join-Path $global:ScriptRoot '.vscode'
    $settingsFile = Join-Path $vscodeDir 'settings.json'
    if (-not (Test-Path -Path $vscodeDir)) {
        New-Item -ItemType Directory -Path $vscodeDir -Force | Out-Null
    }
    $settings = [ordered]@{}
    if (Test-Path -Path $settingsFile) {
        try {
            $raw = Get-Content -Path $settingsFile -Raw -Encoding UTF8
            $raw = $raw -replace '(?m)^\s*//.*$', ''
            $parsed = $raw | ConvertFrom-Json
            if ($null -ne $parsed) {
                $parsed.PSObject.Properties | ForEach-Object { $settings[$_.Name] = $_.Value }
            }
        } catch { Write-Warn "settings.json không hợp lệ, sẽ tạo mới." }
    }
    if ($settings['dotnet.dotnetPath'] -eq $DotnetExePath) { return }
    $settings['dotnet.dotnetPath'] = $DotnetExePath
    try {
        Save-JsonSafe -Path $settingsFile -Data $settings
        Write-Host "✅ VS Code settings đã cập nhật → $DotnetExePath" -ForegroundColor Green
    } catch { Write-Error "Không thể ghi $settingsFile : $_" }
}

function Save-JsonSafe {
    param($Path, $Data)
    $tempPath = "$Path.tmp"
    Register-TempFile $tempPath
    try {
        $Data | ConvertTo-Json -Depth 10 | Out-File -FilePath $tempPath -Encoding utf8
        Move-Item -Path $tempPath -Destination $Path -Force
    } catch {
        Write-Warn "Không thể ghi file ${Path}: $_"
    }
}

function Open-Target {
    param([string]$Target)
    try {
        if ($global:OS -eq 'Windows') {
            if ($Target -match '^https?://') { Start-Process $Target }
            else { Start-Process explorer.exe -ArgumentList "`"$Target`"" }
        }
        elseif ($global:OS -eq 'MacOS') { Start-Process open    -ArgumentList @($Target) }
        elseif ($global:OS -eq 'Linux') { Start-Process xdg-open -ArgumentList @($Target) }
    } catch { Write-Warn "Không thể tự mở. Vui lòng truy cập thủ công: $Target" }
}

function Get-AvailableDrives {
    if ($global:OS -eq 'Windows') {
        Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Select-Object -ExpandProperty DeviceID
    } elseif ($global:OS -eq 'Linux') {
        @('/') + (Get-ChildItem /mnt -Directory -EA SilentlyContinue | Select-Object -ExpandProperty FullName)
    } elseif ($global:OS -eq 'MacOS') {
        @('/') + (Get-ChildItem /Volumes -Directory -EA SilentlyContinue | Select-Object -ExpandProperty FullName)
    } else { @('/') }
}

function Get-RuntimeIdentifier {
    $arch  = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
    $isArm = ($arch -eq [System.Runtime.InteropServices.Architecture]::Arm64)
    switch ($global:OS) {
        'Windows' { return $(if ($isArm) { 'win-arm64'   } else { 'win-x64'   }) }
        'MacOS'   { return $(if ($isArm) { 'osx-arm64'   } else { 'osx-x64'   }) }
        'Linux'   { return $(if ($isArm) { 'linux-arm64' } else { 'linux-x64' }) }
        default   { return 'win-x64' }
    }
}

function Test-PortListening {
    param([int]$Port)
    try {
        if ($global:OS -eq 'Windows') {
            return [bool](Get-NetTCPConnection -LocalPort $Port -State Listen -EA SilentlyContinue)
        } elseif ($global:OS -eq 'Linux') {
            $out = & ss -tlnp 2>/dev/null | Select-String ":$Port\s"
            return [bool]$out
        } elseif ($global:OS -eq 'MacOS') {
            $out = & lsof -iTCP:$Port -sTCP:LISTEN 2>/dev/null
            return [bool]$out
        }
    } catch {}
    return $false
}

# Export các hàm công cộng
Export-ModuleMember -Function Get-RelativeDepth, Invoke-CompatibleChildItem, Get-SafePath, Save-JsonSafe,
    Update-VSCodeDotnetPath, Open-Target, Get-AvailableDrives, Get-RuntimeIdentifier, Test-PortListening,
    Register-TempFile