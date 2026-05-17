#!/usr/bin/env pwsh
# ==================================================================================================
#  FILE NAME: gbuild.ps1
# ==================================================================================================
# --------------------------------------------------------------------------------------------------
# [SECTION 0] KHAI BÁO THAM SỐ
# --------------------------------------------------------------------------------------------------
param(
    [switch]$GitHub,
    [switch]$NonInteractive,
    [switch]$Incremental
)

# --------------------------------------------------------------------------------------------------
# [SECTION 1] CẤU HÌNH MÔI TRƯỜNG & BIẾN TOÀN CỤC
# --------------------------------------------------------------------------------------------------
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Global:StartTime = Get-Date

# Bảng màu log
$C_Header = "Magenta"; $C_Info = "Cyan"; $C_Warn = "Yellow"; $C_Err = "Red"; $C_Succ = "Green"; $C_Gray = "DarkGray"

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
$script:OS = Get-OSPlatform

# ── Thiết lập UTF-8 ────────────────────────────────────────────────────────────
if ($script:OS -eq 'Windows') {
    try { & chcp 65001 | Out-Null } catch {}
}
$OutputEncoding           = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8

# ── Thư mục gốc script ──────────────────────────────────────────────────────────
$script:ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

# ==================================================================================
# GIAO DIỆN & LOG
# ==================================================================================
# Độ rộng terminal (clamp 80–120)
$script:GW  = [Math]::Min([Math]::Max(([Console]::WindowWidth), 80), 120)
$script:GCL = [int]($script:GW * 0.60)   # cột trái chiếm 60% màn hình

# ── Nội bộ: in 2 cột trái + phải ──────────────────────────────────────────────────
function _2Col {
    param([string]$L, [string]$R = "",
          [string]$LC = "White", [string]$RC = "DarkGray")
    $pad = [Math]::Max($script:GCL - $L.Length, 1)
    Write-Host $L  -NoNewline -ForegroundColor $LC
    Write-Host (' ' * $pad) -NoNewline
    if ($R) { Write-Host $R -ForegroundColor $RC }
    else    { Write-Host "" }
}

# ── Thanh tiến trình: [ XX%] ██████░░░░ ▶ Label ──────────────────────────────────
function Show-ProgressBar {
    param([int]$Current, [int]$Total, [string]$Label)
    if ($Total -le 0) { $Total = 1 }
    $pct  = [int][Math]::Min([Math]::Ceiling($Current / $Total * 100), 100)
    $fill = [int][Math]::Min([Math]::Floor($pct / 100.0 * 20), 20)
    $bar  = ("█" * $fill) + ("░" * (20 - $fill))
    Write-Host ""
    _2Col "[ $($pct.ToString('D2'))%] $bar  ▶ $Label" "| $Label" $C_Info "DarkGray"
    Write-Host ("─" * $script:GW) -ForegroundColor $C_Gray
}

# ── Tiêu đề section dạng box ─────────────────────────────────────────────────────
function Write-StepTitle {
    param([string]$Text, [string]$Color = "White", [bool]$ShowSeparator = $true)
    $inner  = "   $Text   "
    $hLine  = "─" * $inner.Length
    Write-Host "  ┌$hLine┐" -ForegroundColor $C_Gray
    Write-Host "  │$inner│" -ForegroundColor $Color
    Write-Host "  └$hLine┘" -ForegroundColor $C_Gray
    if ($ShowSeparator) { Write-Host "" }
}

# ── Box tiêu đề lớn giữa màn hình (dùng cho KẾT QUẢ BUILD) ──────────────────────
function Write-SectionBox {
    param([string]$Title, [string]$Color = "White")
    $inner  = "      $Title      "
    $hLine  = "─" * $inner.Length
    Write-Host ""
    Write-Host "  ┌$hLine┐" -ForegroundColor $C_Gray
    Write-Host "  │$(' ' * $inner.Length)│" -ForegroundColor $C_Gray
    Write-Host "  │$inner│" -ForegroundColor $Color
    Write-Host "  │$(' ' * $inner.Length)│" -ForegroundColor $C_Gray
    Write-Host "  └$hLine┘" -ForegroundColor $C_Gray
    Write-Host ""
}

# ── Các log helper ────────────────────────────────────────────────────────────────
function Write-Log    { param([string]$msg, [string]$color = "White")
    Write-Host "  $msg" -ForegroundColor $color }

function Write-SubLog { param([string]$msg)
    Write-Host "  ▶ Đang xử lý: $msg..." -ForegroundColor Gray }

function Write-Done   { param([string]$msg, [double]$secs = -1)
    $r = if ($secs -ge 0) { "[✅] Hoàn tất! ($($secs.ToString('F1'))s)" } else { "[✅] Hoàn tất!" }
    _2Col "  ✅ $msg" $r "Green" "DarkGray" }

function Write-Fail   { param([string]$msg, [double]$secs = -1)
    $r = if ($secs -ge 0) { "[❌] Thất bại! ($($secs.ToString('F1'))s)" } else { "[❌] Thất bại!" }
    _2Col "  ❌ $msg" $r "Red" "DarkGray" }

function Write-Info   { param([string]$msg)
    _2Col "  ℹ  $msg" "" $C_Info }

function Write-Warn   { param([string]$msg)
    _2Col "  ⚠️  $msg" "" $C_Warn }

function Write-Sep    { Write-Host ("─" * $script:GW) -ForegroundColor $C_Gray }

# ==================================================================================
# CÁC HÀM TIỆN ÍCH CHUNG
# ==================================================================================
function Get-CanonicalPath {
    param([string]$path)
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }

    # Resolve-Path có thể fail khi thư mục chưa tồn tại → fallback FullName
    try {
        if (Test-Path -LiteralPath $path) {
            return (Resolve-Path -LiteralPath $path -ErrorAction Stop).ProviderPath
        }
    } catch {}

    try {
        return ([System.IO.Path]::GetFullPath($path))
    } catch {
        return $path
    }
}

function Assert-InProjectRoot {
    param(
        [Parameter(Mandatory=$true)][string]$TargetPath,
        [Parameter(Mandatory=$true)][string]$ProjectRoot
    )

    $t = Get-CanonicalPath $TargetPath
    $r = Get-CanonicalPath $ProjectRoot

    if (-not $t -or -not $r) { return $false }

    # Chuẩn hóa dạng có trailing separator để tránh case "/repo2" bắt nhầm "/repo"
    $rTrim = $r.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $rPrefix = $rTrim + [System.IO.Path]::DirectorySeparatorChar

    # Trên Windows phân biệt không phân biệt hoa/thường
    $cmp = if ($script:OS -eq 'Windows') { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }

    return $t.StartsWith($rPrefix, $cmp) -or ($t -eq $rTrim)
}

function Get-SafePath {
    param([string]$path)

    if ([string]::IsNullOrWhiteSpace($path)) { return $path }

    # Trên non-Windows (macOS/Linux): resolve thành absolute path là đủ
    if ($script:OS -ne 'Windows') {
        try { return (Resolve-Path -LiteralPath $path -ErrorAction Stop).ProviderPath }
        catch { return $path }
    }

    # Path không tồn tại → trả về nguyên (có thể là path sẽ được tạo sau)
    if (-not (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue)) { return $path }

    # Normalize về absolute path (loại bỏ .., symlink v.v.)
    $absPath = try {
        (Get-Item -LiteralPath $path -ErrorAction Stop).FullName
    } catch { $path }
    if ([string]::IsNullOrWhiteSpace($absPath)) { return $path }

    # Nếu path đã an toàn (không có space, không có ký tự non-ASCII) → dùng luôn
    if ($absPath -notmatch '[\s\u0080-\uFFFF]') { return $absPath }

    # ── TẦNG 1: kernel32 GetShortPathNameW (P/Invoke) ─────────────────────────
    try {
        # Đăng ký type một lần duy nhất trong session (idempotent)
        if (-not ('GBuild.PathHelper' -as [type])) {
            Add-Type -Namespace 'GBuild' -Name 'PathHelper' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport(
    "kernel32.dll",
    CharSet     = System.Runtime.InteropServices.CharSet.Unicode,
    SetLastError= true)]
public static extern uint GetShortPathName(
    string lpszLongPath,
    System.Text.StringBuilder lpszShortPath,
    uint cchBuffer);
'@ -ErrorAction Stop
        }
        $sb  = [System.Text.StringBuilder]::new(32767)
        $len = [GBuild.PathHelper]::GetShortPathName($absPath, $sb, 32767)
        if ($len -gt 0 -and $len -lt 32767) {
            $shortPath = $sb.ToString(0, [int]$len)
            # Chỉ dùng nếu kết quả thực sự loại bỏ được ký tự nguy hiểm
            if ($shortPath -and ($shortPath -notmatch '[\s\u0080-\uFFFF]')) {
                return $shortPath
            }
        }
    } catch {}

    # ── TẦNG 2: FSO ShortPath (COM, legacy fallback) ──────────────────────────
    try {
        $fso       = New-Object -ComObject Scripting.FileSystemObject -ErrorAction Stop
        $shortPath = if (Test-Path -LiteralPath $absPath -PathType Container) {
            $fso.GetFolder($absPath).ShortPath
        } else {
            $fso.GetFile($absPath).ShortPath
        }
        if ($shortPath -and ($shortPath -notmatch '[\s\u0080-\uFFFF]')) {
            return $shortPath
        }
    } catch {}

    # ── TẦNG 3: Trả về absolute path chuẩn hóa ────────────────────────────────
    # Khi 8.3 names bị tắt hoàn toàn, không còn cách tạo short path.
    # Script đã set chcp 65001 + UTF-8 encoding ở trên nên external tools
    # nhận Unicode args qua W-API của PowerShell & operator.
    return $absPath
}

function Remove-ItemForce {
    param([string]$TargetDir)
    if (-not (Test-Path -LiteralPath $TargetDir)) { return $true }

    # Thử cách thông thường
    try { Remove-Item -LiteralPath $TargetDir -Recurse -Force -EA Stop; return $true } catch {}

    if ($script:OS -eq 'Windows') {
        # Fallback Robocopy
        $emptyDir = Join-Path $env:TEMP "gbuild_empty_$(Get-Random)"
        New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
        & robocopy $emptyDir $TargetDir /MIR /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
        $exitCode = $LASTEXITCODE
        Remove-Item -LiteralPath $emptyDir -Force -EA SilentlyContinue
        if ($exitCode -le 7) {
            Remove-Item -LiteralPath $TargetDir -Recurse -Force -EA SilentlyContinue
            return (-not (Test-Path -LiteralPath $TargetDir))
        }
        return $false
    } else {
        # Trên Linux/macOS: dùng lệnh rm -rf
        try {
            & /bin/rm -rf -- $TargetDir 2>$null
            return (-not (Test-Path -LiteralPath $TargetDir))
        } catch {
            return $false
        }
    }
}

function Update-VSCodeDotnetPath {
    param([string]$DotnetExePath)

    if ([string]::IsNullOrWhiteSpace($DotnetExePath)) { return }
    if (-not (Test-Path -LiteralPath $DotnetExePath))  { return }

    # Xác định thư mục gốc của script
    $vscodeDir    = Join-Path $script:ScriptRoot '.vscode'
    $settingsFile = Join-Path $vscodeDir 'settings.json'

    # Tạo .vscode nếu chưa có
    if (-not (Test-Path -LiteralPath $vscodeDir)) {
        New-Item -ItemType Directory -Path $vscodeDir -Force | Out-Null
    }

    # Đọc settings hiện tại (jsonc)
    $settings = [ordered]@{}
    if (Test-Path -LiteralPath $settingsFile) {
        try {
            $raw = Get-Content -LiteralPath $settingsFile -Raw -Encoding UTF8
            $raw = $raw -replace '(?m)^\s*//.*$', ''   # loại bỏ comment
            $settings = $raw | ConvertFrom-Json -AsHashtable -EA Stop
        } catch {
            Write-Warn "settings.json không hợp lệ, sẽ tạo mới."
        }
    }

    # Chỉ cập nhật nếu khác
    if ($settings['dotnet.dotnetPath'] -eq $DotnetExePath) {
        Write-Log "   ℹ️  dotnet.dotnetPath đã đúng, bỏ qua." $C_Gray
        return
    }

    $settings['dotnet.dotnetPath'] = $DotnetExePath

    try {
        $settings | ConvertTo-Json -Depth 10 |
            Out-File -FilePath $settingsFile -Encoding UTF8 -Force
        Write-Done "VS Code settings đã cập nhật → $DotnetExePath"
    } catch {
        Write-Fail "Không thể ghi $settingsFile : $_"
    }
}

function Open-Directory {
    param([string]$Path)
    if ($script:OS -eq 'Windows') {
        Start-Process explorer.exe -ArgumentList "`"$Path`""
    } elseif ($script:OS -eq 'MacOS') {
        Start-Process open -ArgumentList $Path
    } elseif ($script:OS -eq 'Linux') {
        Start-Process xdg-open -ArgumentList $Path
    }
}


# ==================================================================================
# HÀM LẤY Ổ ĐĨA / MOUNT POINT
# ==================================================================================
function Get-AvailableDrives {
    if ($script:OS -eq 'Windows') {
        Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
            Select-Object -ExpandProperty DeviceID
    } elseif ($script:OS -eq 'Linux') {
        @('/') + (Get-ChildItem /mnt -Directory -EA SilentlyContinue | Select-Object -ExpandProperty FullName)
    } elseif ($script:OS -eq 'MacOS') {
        @('/') + (Get-ChildItem /Volumes -Directory -EA SilentlyContinue | Select-Object -ExpandProperty FullName)
    } else {
        @('/')
    }
}

# ==================================================================================
# TÌM FILE / THƯ MỤC TRONG TOÀN BỘ Ổ ĐĨA
# ==================================================================================
function Find-FileInDrives {
    param(
        [string]$FileName,                     # Tên file hoặc thư mục cần tìm
        [scriptblock]$ValidateScript,          # Scriptblock nhận đường dẫn đầy đủ, trả về $true nếu đạt
        [int]$MaxDepth = 4,
        [switch]$Directory                     # Tìm thư mục thay vì file
    )

    $drives = Get-AvailableDrives

    foreach ($drive in $drives) {
        $root = Join-Path $drive ''
        Write-Host "`r   🔎 Đang quét $drive ...$(' ' * 20)" -NoNewline -ForegroundColor DarkGray

        # Tách riêng bước lấy dữ liệu và lọc để tránh lỗi pipe rỗng
        $childItems = if ($Directory) {
            Get-ChildItem -Path $root -Directory -Filter $FileName -Recurse -Depth $MaxDepth -EA SilentlyContinue
        } else {
            Get-ChildItem -Path $root -File -Filter $FileName -Recurse -Depth $MaxDepth -EA SilentlyContinue
        }

        $items = $childItems | Where-Object {
            $_.FullName -notmatch '[\\/](Windows|AppData|ProgramData|\$Recycle\.Bin|System Volume Information|proc|sys|dev|run)[\\/]'
        }

        # Lấy kết quả đầu tiên hợp lệ
        foreach ($item in $items) {
            if (& $ValidateScript $item.FullName) {
                Write-Host "" # Xuống dòng sau khi tìm thấy
                return $item.FullName
            }
        }
    }
    Write-Host "`r$(' ' * 80)`r" -NoNewline
    return $null
}

# ==================================================================================
# HÀM TÌM .NET SDK
# ==================================================================================
function Set-DotnetEnv {
    param([string]$SdkPath)
    # Chỉ set nếu chưa có, tránh duplicate trong PATH
    if ($env:PATH -notlike "*$SdkPath*") {
        $separator = if ($script:OS -eq 'Windows') { ';' } else { ':' }
        $env:PATH = "$SdkPath$separator" + $env:PATH
    }
    $env:DOTNET_ROOT                        = $SdkPath
    $env:DOTNET_MSBUILD_SDK_RESOLVER_CLI_DIR = $SdkPath
    # KHÔNG set DOTNET_MULTILEVEL_LOOKUP=0 — để dotnet vẫn tìm được SDK hệ thống
    # nếu SDK local bị hỏng, tránh làm chết IntelliSense
}

# ── Runtime Identifier động theo OS & CPU arch ────────────────────────────────
function Get-RuntimeIdentifier {
    $arch  = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
    $isArm = ($arch -eq [System.Runtime.InteropServices.Architecture]::Arm64)
    switch ($script:OS) {
        'Windows' { return $(if ($isArm) { 'win-arm64'   } else { 'win-x64'   }) }
        'MacOS'   { return $(if ($isArm) { 'osx-arm64'   } else { 'osx-x64'   }) }
        'Linux'   { return $(if ($isArm) { 'linux-arm64' } else { 'linux-x64' }) }
        default   { return 'win-x64' }
    }
}

# ── Kiểm tra port đang lắng nghe (đa nền tảng) ────────────────────────────────
function Test-PortListening {
    param([int]$Port)
    try {
        if ($script:OS -eq 'Windows') {
            return [bool](Get-NetTCPConnection -LocalPort $Port -State Listen -EA SilentlyContinue)
        } elseif ($script:OS -eq 'Linux') {
            $out = & ss -tlnp 2>/dev/null | Select-String ":$Port\s"
            return [bool]$out
        } elseif ($script:OS -eq 'MacOS') {
            $out = & lsof -iTCP:$Port -sTCP:LISTEN 2>/dev/null
            return [bool]$out
        }
    } catch {}
    return $false
}

# ── Mở URL trên trình duyệt (đa nền tảng) ─────────────────────────────────────
function Open-Url {
    param([string]$Url)
    try {
        if ($script:OS -eq 'Windows')   { Start-Process $Url }
        elseif ($script:OS -eq 'MacOS') { Start-Process open    -ArgumentList $Url }
        elseif ($script:OS -eq 'Linux') { Start-Process xdg-open -ArgumentList $Url }
    } catch { Write-Warn "Không thể tự mở trình duyệt. Vui lòng truy cập: $Url" }
}

# ── Quét thư mục tìm dotnet SDK với thanh tiến trình (thay $ScanWithProgress) ──
function Invoke-ScanForDotnet {
    param(
        [string]  $RootPath,
        [int]     $MaxDepth  = 4,
        [string]  $Label     = "",
        [string[]]$ExcludeDirs = @()
    )
    $dotnetName = if ($script:OS -eq 'Windows') { 'dotnet.exe' } else { 'dotnet' }
    $excludePattern = if ($ExcludeDirs.Count -gt 0) {
        '[\\/](' + (($ExcludeDirs | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')[\\/]'
    } else { $null }

    Write-Host "`r   🔎 $Label ...$(' ' * 20)" -NoNewline -ForegroundColor DarkGray

    $found = Get-ChildItem -Path $RootPath -File -Filter $dotnetName `
                           -Recurse -Depth $MaxDepth -EA SilentlyContinue |
        Where-Object {
            if ($excludePattern -and ($_.FullName -match $excludePattern)) { return $false }
            try {
                $sdkCheck = & $_.FullName --list-sdks 2>&1
                return ($sdkCheck -match '\d+\.\d+')
            } catch { return $false }
        } |
        Select-Object -First 1

    Write-Host "`r$(' ' * 80)`r" -NoNewline
    return $found?.FullName
}

function Get-SmartDotnetPath {
    Write-Host "🔍 Đang kiểm tra cache SDK .NET..." -ForegroundColor Cyan
    $cacheFile  = Join-Path $script:ScriptRoot ".sdkcache.json"
    $dotnetName = if ($script:OS -eq 'Windows') { 'dotnet.exe' } else { 'dotnet' }

    # --- 1. ƯU TIÊN SỐ 1: KIỂM TRA CACHE (TỐC ĐỘ TỨC THÌ) ---
    if (Test-Path -LiteralPath $cacheFile) {
        try {
            $cacheData = Get-Content -LiteralPath $cacheFile -Raw | ConvertFrom-Json
            if ($cacheData.Path) {
                $dotnetExe = Join-Path $cacheData.Path $dotnetName
                if (Test-Path -LiteralPath $dotnetExe) {
                    $sdkCheck = & $dotnetExe --list-sdks 2>&1
                    if ($sdkCheck -match '\d+\.\d+') {
                        Write-Host "✅ [CACHE] Sử dụng SDK tại: $($cacheData.Path)" -ForegroundColor Green
                        Set-DotnetEnv -SdkPath (Get-SafePath $cacheData.Path)
                        return $dotnetExe
                    }
                }
            }
        } catch { }
        Write-Host "⚠️ Cache SDK không còn hiệu lực, chuyển sang tìm kiếm..." -ForegroundColor Yellow
    }

    # --- 2. ƯU TIÊN SỐ 2: KIỂM TRA TRONG PATH HỆ THỐNG ---
    Write-Host "🔍 Kiểm tra dotnet trong PATH..." -ForegroundColor Cyan
    $systemDotnet = Get-Command 'dotnet' -ErrorAction SilentlyContinue
    if ($systemDotnet) {
        $sdkCheck = & dotnet --list-sdks 2>&1
        if ($sdkCheck -and $sdkCheck -match '\d+\.\d+') {
            $dotnetExe  = $systemDotnet.Source
            $sdkFolder  = Split-Path $dotnetExe -Parent
            Write-Host "✅ Sử dụng dotnet từ PATH: $sdkFolder" -ForegroundColor Green
            @{ Path = $sdkFolder } | ConvertTo-Json | Out-File $cacheFile -Encoding utf8 -Force
            Set-DotnetEnv -SdkPath $sdkFolder
            return $dotnetExe
        }
    }

    # --- GIAI ĐOẠN DÒ TÌM LOCAL (Nếu hệ thống chưa có) ---
    # $dotnetName đã khai báo ở đầu hàm — không khai báo lại
    $excludeDirs = @('Windows', 'AppData', '$Recycle.Bin', 'System Volume Information',
                     'ProgramData', 'Microsoft', 'Package Cache', 'proc', 'sys', 'dev', 'run')

    # --- macOS / Linux: kiểm tra các vị trí cài đặt phổ biến ---
    if ($script:OS -in @('MacOS', 'Linux')) {
        $localCandidates = @(
            (Join-Path $script:ScriptRoot ".sdk" "dotnet"),
            (Join-Path $HOME ".dotnet"),
            "/usr/local/share/dotnet",
            "/usr/share/dotnet"
        )
        foreach ($candidate in $localCandidates) {
            if (-not $candidate) { continue }
            $exe = Join-Path $candidate $dotnetName
            if (Test-Path -LiteralPath $exe) {
                $sdkCheck = & $exe --list-sdks 2>&1
                if ($sdkCheck -match '\d+\.\d+') {
                    Write-Host "✅ Đã tìm thấy dotnet tại: $candidate" -ForegroundColor Green
                    @{ Path = $candidate } | ConvertTo-Json | Out-File $cacheFile -Encoding utf8 -Force
                    Set-DotnetEnv -SdkPath $candidate
                    return $exe
                }
            }
        }
        Write-Host "❌ Không tìm thấy SDK .NET nào hệ thống." -ForegroundColor Red
        return $null
    }

    if ($script:OS -eq 'Windows') {
        $currentDir  = (Get-Location).ProviderPath
        $projectDrive = Split-Path -Path $currentDir -Qualifier   # "G:"
        $driveRoot    = $projectDrive + [System.IO.Path]::DirectorySeparatorChar

        # Tính độ sâu tương đối từ gốc ổ đĩa đến thư mục hiện tại
        $sep      = [System.IO.Path]::DirectorySeparatorChar
        $depthX   = ($currentDir.TrimEnd($sep).Split($sep) | Where-Object { $_ -ne "" }).Count - 1
        $searchDepth = $depthX + 3

        # --- TÌM TỪ THƯ MỤC DỰ ÁN SÂU XUỐNG 3 CẤP ---
        Write-Host "🔍 [Bước 3] Tìm nhanh trong thư mục dự án hiện tại (độ sâu tối đa 3)..." -ForegroundColor Cyan
        $res = Invoke-ScanForDotnet -RootPath $currentDir -MaxDepth 3 -Label "Quét thư mục dự án" -ExcludeDirs $excludeDirs
        if ($res) {
            $folder = Split-Path $res -Parent
            Write-Host "💾 Đã lưu vị trí SDK vào cache: $folder" -ForegroundColor Green
            @{ Path = $folder } | ConvertTo-Json | Out-File $cacheFile -Encoding utf8 -Force
            Set-DotnetEnv -SdkPath (Get-SafePath $folder)
            return $res
        }

        # --- LÙI VỀ GỐC Ổ ĐĨA DỰ ÁN, QUÉT XUỐNG ĐỘ SÂU (depthX + 3) ---
        Write-Host "🔍 [Bước 4] Không thấy, lùi về gốc $driveRoot quét xuống độ sâu $searchDepth (depthX+3)..." -ForegroundColor Cyan
        $res = Invoke-ScanForDotnet -RootPath $driveRoot -MaxDepth $searchDepth -Label "Quét ổ đĩa hiện tại ($driveRoot)" -ExcludeDirs $excludeDirs
        if ($res) {
            $folder = Split-Path $res -Parent
            Write-Host "💾 Đã lưu vị trí SDK vào cache: $folder" -ForegroundColor Green
            @{ Path = $folder } | ConvertTo-Json | Out-File $cacheFile -Encoding utf8 -Force
            Set-DotnetEnv -SdkPath (Get-SafePath $folder)
            return $res
        }

        # --- MỞ RỘNG QUÉT CÁC Ổ ĐĨA KHÁC ---
        Write-Host "🔍 [Bước 5] Vẫn không thấy, mở rộng quét toàn bộ các ổ đĩa khả dụng..." -ForegroundColor Cyan
        $drives      = Get-AvailableDrives
        $otherDrives = $drives | Where-Object { $_ -ne $projectDrive }

        foreach ($drive in $otherDrives) {
            $targetRoot = $drive + [System.IO.Path]::DirectorySeparatorChar
            $res = Invoke-ScanForDotnet -RootPath $targetRoot -MaxDepth 4 -Label "Đang quét ổ đĩa $drive" -ExcludeDirs $excludeDirs
            if ($res) {
                $folder = Split-Path $res -Parent
                Write-Host "💾 Đã lưu vị trí SDK vào cache: $folder" -ForegroundColor Green
                @{ Path = $folder } | ConvertTo-Json | Out-File $cacheFile -Encoding utf8 -Force
                Set-DotnetEnv -SdkPath (Get-SafePath $folder)
                return $res
            }
        }
    }

    Write-Host "❌ Không tìm thấy SDK .NET nào hệ thống." -ForegroundColor Red
    return $null
}

# Khởi tạo biến $dotnetCmd để sử dụng cho toàn bộ quá trình build phía sau
$global:dotnetCmd = Get-SmartDotnetPath
if (-not $global:dotnetCmd) {
    Write-Host "❌ Không có SDK .NET, không thể tiếp tục." -ForegroundColor Red
    exit 1
}

function Get-AndroidSdkPath {
    Write-Log "🔍 Đang săn tìm Android SDK..." $C_Gray
    $adbExeName = if ($script:OS -eq 'Windows') { 'adb.exe' } else { 'adb' }
    $searchList = @(
        (Join-Path $script:ScriptRoot ".sdk" "android-sdk"),
        (Join-Path $script:ScriptRoot ".." ".sdk" "android-sdk"),
        (Join-Path (Get-Location) ".sdk" "android-sdk"),
        $env:ANDROID_HOME,
        $env:ANDROID_SDK_ROOT
    )

    # Thêm vị trí theo OS (không hardcode C:\)
    if ($script:OS -eq 'Windows') {
        $pf86     = ${env:ProgramFiles(x86)}
        $pf       = $env:ProgramFiles
        $sysDrive = $env:SystemDrive
        $localAppData = $env:LOCALAPPDATA
        if ($localAppData) { $searchList += (Join-Path $localAppData "Android" "Sdk") }
        if ($pf86)         { $searchList += (Join-Path $pf86 "Android" "android-sdk") }
        if ($pf)           { $searchList += (Join-Path $pf   "Android" "android-sdk") }
        if ($sysDrive)     { $searchList += (Join-Path $sysDrive "Android" "android-sdk") }
    } elseif ($script:OS -eq 'MacOS') {
        $searchList += (Join-Path $env:HOME "Library" "Android" "sdk")
    } elseif ($script:OS -eq 'Linux') {
        $searchList += (Join-Path $env:HOME "Android" "Sdk")
        $searchList += "/opt/android-sdk"
    }

    foreach ($p in $searchList) {
        if ($p -and (Test-Path -LiteralPath $p)) {
            $found = (Get-Item -LiteralPath $p).FullName.TrimEnd('\', '/')
            Write-Log "✅ Đã thấy Android SDK: $found" $C_Succ
            $safePath = Get-SafePath $found
            # Set ANDROID_HOME với safe path để child processes dùng được
            $env:ANDROID_HOME     = $safePath
            $env:ANDROID_SDK_ROOT = $safePath
            return $safePath
        }
    }

    # Nếu chưa tìm thấy, quét các ổ cứng cố định với độ sâu 3
    Write-Log "⚙️ Đang quét ổ cứng tìm Android SDK..." $C_Gray
    $fixedDrives = Get-AvailableDrives
    $excludeDirs = @('Windows', 'AppData', '$Recycle.Bin', 'System Volume Information', 'ProgramData', 'Microsoft', 'Package Cache')
    
    foreach ($drive in $fixedDrives) {
        $root = Join-Path $drive ''
        $topDirs = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin $excludeDirs }
        
        foreach ($dir in $topDirs) {
            $pathStr = $dir.FullName
            if ($pathStr.Length -gt 50) { $pathStr = $pathStr.Substring(0, 47) + "..." }
            Write-Host "`r   🔍 Đang dò: $pathStr$(' ' * 20)" -NoNewline -ForegroundColor DarkGray

            $androidDirs = Get-ChildItem -Path $dir.FullName -Directory -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                            Where-Object { $_.Name -eq "android-sdk" -or (Test-Path (Join-Path $_.FullName "platform-tools" $adbExeName)) }
            if ($androidDirs) {
                Write-Host "" # Xuống dòng
                $found = $androidDirs[0].FullName
                Write-Log "✅ Đã thấy Android SDK: $found" $C_Succ
                $safePath = Get-SafePath $found
                $env:ANDROID_HOME     = $safePath
                $env:ANDROID_SDK_ROOT = $safePath
                return $safePath
            }
        }
        Write-Host "`r$(' ' * 80)`r" -NoNewline
    }

    $foundSdk = Find-FileInDrives -FileName 'android-sdk' -Directory -MaxDepth 3 -ValidateScript {
        param($path)
        # Kiểm tra xem có platform-tools/adb không
        $adbName = if ($script:OS -eq 'Windows') { 'adb.exe' } else { 'adb' }
        return (Test-Path (Join-Path $path "platform-tools" $adbName))
    }  # ← Đóng scriptblock ValidateScript

    if ($foundSdk) {
        Write-Host ""
        Write-Log "✅ Đã thấy Android SDK: $foundSdk" $C_Succ
        $safePath = Get-SafePath $foundSdk
        $env:ANDROID_HOME     = $safePath
        $env:ANDROID_SDK_ROOT = $safePath
        return $safePath
    }

    Write-Log "❌ Không tìm thấy Android SDK." $C_Err
    return $null
}

function Get-JavaSdkPath {
    $javacExe = if ($script:OS -eq 'Windows') { 'javac.exe' } else { 'javac' }
    $javaExe  = if ($script:OS -eq 'Windows') { 'java.exe' } else { 'java' }

    # 1. Kiểm tra các vị trí ưu tiên (gần script, biến môi trường)
    $searchList = @(
        (Join-Path $script:ScriptRoot ".sdk" "jdk"),
        (Join-Path $script:ScriptRoot ".." ".sdk" "jdk"),
        (Join-Path $script:ScriptRoot ".." ".." ".." ".sdk" "jdk"),
        (Join-Path (Get-Location) ".sdk" "jdk"),
        $env:JAVA_HOME
    )

    if ($script:OS -eq 'Windows') {
        $pf   = $env:ProgramFiles
        $pf86 = ${env:ProgramFiles(x86)}
        if ($pf)   { $searchList += (Join-Path $pf   "Java") }
        if ($pf86) { $searchList += (Join-Path $pf86 "Java") }
    } elseif ($script:OS -eq 'MacOS') {
        $searchList += "/Library/Java/JavaVirtualMachines"
        $searchList += (Join-Path $env:HOME "Library" "Java" "JavaVirtualMachines")
    } elseif ($script:OS -eq 'Linux') {
        $searchList += "/usr/lib/jvm"
        $searchList += "/usr/local/lib/jvm"
    }

    foreach ($p in $searchList) {
        if ($p -and (Test-Path -LiteralPath (Join-Path $p "bin" $javacExe))) {
            Write-Log "✅ Đã tìm thấy Java SDK: $p" $C_Succ
            $safePath = Get-SafePath $p
            # Set JAVA_HOME với safe path
            $env:JAVA_HOME = $safePath
            return $safePath
        }
    }

    # 2. Quét các ổ đĩa cục bộ tìm thư mục chứa bin/javac (độ sâu 4)
    Write-Log "⚙️ Đang quét ổ đĩa tìm Java SDK..." $C_Gray

    # ValidateScript tự tính exe names để không phụ thuộc scope ngoài
    $foundJavac = Find-FileInDrives -FileName $javacExe -MaxDepth 4 -ValidateScript {
        param($javacPath)
        $binDir = Split-Path $javacPath -Parent
        # Tính lại tên exe bên trong scriptblock (tránh lỗi scope khi truyền qua hàm)
        $jcExe = if ($script:OS -eq 'Windows') { 'javac.exe' } else { 'javac' }
        $jExe  = if ($script:OS -eq 'Windows') { 'java.exe'  } else { 'java'  }
        return ((Test-Path (Join-Path $binDir $jcExe)) -and (Test-Path (Join-Path $binDir $jExe)))
    }

    if ($foundJavac) {
        $binDir = Split-Path $foundJavac -Parent
        $jdkDir = Split-Path $binDir -Parent
        Write-Host ""
        Write-Log "✅ Đã tìm thấy Java SDK: $jdkDir" $C_Succ
        $safePath = Get-SafePath $jdkDir
        $env:JAVA_HOME = $safePath
        return $safePath
    }

    # 3. Không tìm thấy
    Write-Log "❌ Không tìm thấy Java JDK. Hãy đặt JDK vào thư mục '.sdk/jdk' gần script hoặc cài đặt JDK." $C_Err
    return $null
}

# ==================================================================================
# PROJECT & TFM
# ==================================================================================
function Get-CsprojTfms {
    param([string]$projPath, [string]$FallbackTfm = 'net9.0')
    if (-not (Test-Path -LiteralPath $projPath)) { return @() }
        
    try {
        [xml]$xml = Get-Content -LiteralPath $projPath -Raw
        $tfms = @()
        
        # Lấy từ cả TargetFramework và TargetFrameworks
        $nodes = $xml.SelectNodes("//*[local-name()='TargetFramework' or local-name()='TargetFrameworks']")
        foreach ($node in $nodes) {
            $tfms += $node.InnerText.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() }
        }
        
        if ($tfms.Count -eq 0) { return @($FallbackTfm) }

        # Check GUI App
        $isWindowsGui = ($xml.SelectSingleNode("//*[local-name()='UseWindowsForms' or local-name()='UseWPF']") | Select-Object -ExpandProperty InnerText) -match 'true'

        # Fix regex TFM Windows (Point 4)
        return $tfms | ForEach-Object {
            $t = $_
            # Kiểm tra xem chuỗi có chứa "-windows" không (bao gồm cả version)
            if ($isWindowsGui -and $t -notmatch '-windows') {
                "$t-windows"
            } else {
                $t
            }
        } | Sort-Object -Unique
    } catch {
        return @($FallbackTfm)
    }
}

function Find-Project {
    Write-Log "📂 Đang quét tìm file project..." $C_Gray
    # Tìm từ $PSScriptRoot thay vì "." để tránh quét sai khi chạy từ thư mục khác
    $searchRoot = $script:ScriptRoot
    $allProjects = @(Get-ChildItem -Path $searchRoot -Recurse -Filter *.csproj -File |
        Where-Object { $_.FullName -notmatch '[\\/](obj|bin|node_modules|\.sdk)[\\/]' } |
        Sort-Object FullName)

    if ($allProjects.Count -eq 0) {
        return $null
    }
    if ($allProjects.Count -eq 1) {
        return $allProjects[0]
    }

    # Ưu tiên project cùng thư mục với script
    $scriptDirProjects = @($allProjects | Where-Object { $_.DirectoryName -eq $script:ScriptRoot })
    if ($scriptDirProjects.Count -eq 1) {
        return $scriptDirProjects[0]
    }

    if ($NonInteractive) {
        Write-Warn "Chế độ NonInteractive: Tự động chọn project đầu tiên -> $($allProjects[0].Name)"
        return $allProjects[0]
    }

    # Nếu nhiều project, cho người dùng chọn
    Write-Host "`n📋 Tìm thấy nhiều project:" -ForegroundColor Cyan
    for ($i=0; $i -lt $allProjects.Count; $i++) {
        Write-Host "  [$i] $($allProjects[$i].FullName)" -ForegroundColor DarkGray
    }
    $sel = Read-Host "⌨  Nhập số thứ tự (hoặc Enter để chọn 0)"
    if ([string]::IsNullOrWhiteSpace($sel)) { $sel = 0 }
    $idx = [int]$sel
    if ($idx -lt 0 -or $idx -ge $allProjects.Count) { $idx = 0 }
    return $allProjects[$idx]
}

function Get-ProjectType {
    param([string]$csprojPath)
    if (-not (Test-Path -LiteralPath $csprojPath)) { return "Unknown" }

    $content = Get-Content -LiteralPath $csprojPath -Raw -EA SilentlyContinue
    if (-not $content) { return "Unknown" }

    if ($content -match '<UseMaui>\s*true\s*</UseMaui>') { return "MAUI" }
    if ($content -match 'Sdk\s*=\s*"Microsoft\.NET\.Sdk\.Web"') { return "Web" }
    if ($content -match 'Sdk\s*=\s*"Microsoft\.NET\.Sdk\.BlazorWebAssembly"') { return "BlazorWasm" }

    if ($content -match '<UseWindowsForms>\s*true\s*</UseWindowsForms>') { return "WinForms" }
    if ($content -match '<UseWPF>\s*true\s*</UseWPF>') { return "WPF" }
    if ($content -match '<OutputType>\s*Exe\s*</OutputType>') { return "Console" }
    if ($content -match '<OutputType>\s*WinExe\s*</OutputType>') {
        # WindowsDesktop SDK mà không có UseWPF/UseWindowsForms tường minh → fallback WinForms
        if ($content -match 'Sdk\s*=\s*"Microsoft\.NET\.Sdk\.WindowsDesktop"') { return "WinForms" }
        return "WinExe"
    }

    return "Library"
}

function Get-ProjectPort {
    param([string]$ProjectDir)
    $port = 5000 # Mặc định nếu không tìm thấy gì
    $lsPath = Join-Path $ProjectDir "Properties" "launchSettings.json"
    if (Test-Path -LiteralPath $lsPath) {
        try {
            $ls = Get-Content -LiteralPath $lsPath -Raw | ConvertFrom-Json
            # Lấy port đầu tiên từ bất kỳ profile nào có applicationUrl
            foreach ($userProfile in $ls.profiles.PSObject.Properties.Value) {
                if ($userProfile.applicationUrl -match ':(\d+)') {
                    return [int]$matches[1]
                }
            }
        } catch {}
    }
    return $port
}

# ==================================================================================
# KEYSTORE
# ==================================================================================
function Find-AndroidKeystore([string]$projectDir) {
    Write-Log "🔐 Đang tìm kiếm Keystore để ký..." $C_Gray
    $propsFile = Join-Path $projectDir 'signing.properties'
    if (Test-Path -LiteralPath $propsFile) {
        $props = @{}
        Get-Content -LiteralPath $propsFile | ForEach-Object { if ($_ -match '^\s*([^#=]+?)\s*=\s*(.+)$') { $props[$matches[1].Trim()] = $matches[2].Trim() } }
        $ksPath = $props['storeFile']
        if ($ksPath -and -not ([System.IO.Path]::IsPathRooted($ksPath))) { $ksPath = Join-Path $projectDir $ksPath }
        if ($ksPath -and (Test-Path -LiteralPath $ksPath)) {
            Write-Log "📝 Đã nạp thông tin từ signing.properties" $C_Succ
            return @{ Path = $ksPath; StorePass = $props['storePassword']; Alias = $props['keyAlias']; KeyPass = $props['keyPassword']; Source = 'properties' }
        }
    }
    $ksFile = Get-ChildItem -LiteralPath $projectDir -Recurse -EA SilentlyContinue |
        Where-Object { $_.Extension -in @('.keystore', '.jks') -and
                       $_.FullName -notmatch '[\\/](obj|bin)[\\/]' } |
        Select-Object -First 1
    if ($ksFile) { return @{ Path = $ksFile.FullName; Source = 'file' } }
    return $null
}

function Read-KeystoreInteractive([hashtable]$ks) {
    Write-Host "`n--- THÔNG TIN KÝ ANDROID ---" -ForegroundColor $C_Info
    Write-Host "📍 File: $($ks.Path)" -ForegroundColor $C_Gray
    if (-not $ks.StorePass) {
        $sp = Read-Host "🔑 Nhập Store Password (Enter để bỏ qua ký)"
        if ([string]::IsNullOrWhiteSpace($sp)) { return $null }
        $ks.StorePass = $sp
    }
    if (-not $ks.Alias) {
        $ka = Read-Host "🔑 Nhập Key Alias (Ví dụ: key0)"
        if ([string]::IsNullOrWhiteSpace($ka)) {
            Write-Log "⚠️ Cảnh báo: Sử dụng alias mặc định 'key0'" $C_Warn
            $ks.Alias = 'key0'
        } else { $ks.Alias = $ka }
    }
    if (-not $ks.KeyPass) {
        $kp = Read-Host "🔑 Nhập Key Password (Để trống = giống Store Pass)"
        $ks.KeyPass = if ($kp) { $kp } else { $ks.StorePass }
    }
    return $ks
}

# ==================================================================================================
# SMART CLEAN - CROSS-PLATFORM, SECURE & THOROUGH
# ==================================================================================================
function Invoke-SmartClean {
    param(
        [Parameter(Mandatory=$true)] [string]$ProjectDir,
        [string]$OutputSubDir = "",
        [string]$CsprojPath = ""
    )

    # ── 1. Chuẩn hóa path tuyệt đối & kiểm tra tồn tại ───────────────────────
    $absProjectDir = try { [System.IO.Path]::GetFullPath($ProjectDir) } catch { return }
    if (-not (Test-Path -LiteralPath $absProjectDir -PathType Container)) { return }

    # ── 2. Hàm bảo mật: Chỉ cho phép thao tác bên trong project root ──────────
    # BUG FIX: dùng StringComparison phù hợp OS — Linux case-sensitive (Ordinal),
    #          Windows không phân biệt hoa/thường (OrdinalIgnoreCase).
    $pathCmp = if ($script:OS -eq 'Windows') {
        [System.StringComparison]::OrdinalIgnoreCase
    } else {
        [System.StringComparison]::Ordinal
    }
    $rootPrefix = $absProjectDir.TrimEnd([System.IO.Path]::DirectorySeparatorChar,
                                          [System.IO.Path]::AltDirectorySeparatorChar) +
                  [System.IO.Path]::DirectorySeparatorChar

    function Assert-SafePath {
        param([string]$Target)
        if ([string]::IsNullOrWhiteSpace($Target)) { return $false }
        $canonical = try { [System.IO.Path]::GetFullPath($Target) } catch { return $false }
        # BUG FIX: dùng $pathCmp thay vì hardcode OrdinalIgnoreCase
        return $canonical.StartsWith($rootPrefix, $pathCmp) -or
               [string]::Equals($canonical, $absProjectDir.TrimEnd(
                   [System.IO.Path]::DirectorySeparatorChar,
                   [System.IO.Path]::AltDirectorySeparatorChar), $pathCmp)
    }

    # ── 3. Đọc nội dung csproj để phát hiện loại project ─────────────────────
    # BUG FIX: dùng -LiteralPath cho Test-Path và Get-Content
    $csprojContent = ""
    if ($CsprojPath -and (Test-Path -LiteralPath $CsprojPath -PathType Leaf)) {
        $csprojContent = Get-Content -LiteralPath $CsprojPath -Raw -EA SilentlyContinue
    }
    $isWeb   = $csprojContent -match 'Sdk\s*=\s*"Microsoft\.NET\.Sdk\.(Web|BlazorWebAssembly)"'
    $isMaui  = $csprojContent -match '<UseMaui>\s*true\s*</UseMaui>'

    # ── 4. Xây dựng danh sách target cần xóa (an toàn & động) ────────────────
    $targetsToClean = [System.Collections.Generic.List[string]]::new()

    # Hàm helper: thêm path vào danh sách nếu tồn tại & an toàn
    function Add-CleanTarget {
        param([string]$Path)
        if ([string]::IsNullOrWhiteSpace($Path)) { return }
        # BUG FIX: dùng -LiteralPath để tránh glob chars ([, ], *, ?) trong tên thư mục
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
        if (-not (Assert-SafePath $Path)) { return }
        # BUG FIX: bỏ qua symlink — không xóa target của symlink, chỉ xóa symlink
        $item = Get-Item -LiteralPath $Path -Force -EA SilentlyContinue
        if ($item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            Write-Log "   ⚠️  Bỏ qua symlink: $Path" $C_Warn
            return
        }
        $targetsToClean.Add($Path)
    }

    # Build output (bắt buộc mọi loại project)
    foreach ($name in @('bin', 'obj')) {
        Add-CleanTarget (Join-Path $absProjectDir $name)
    }

    # IDE caches phổ biến
    foreach ($name in @('.vs', '.idea', '.fleet', '.cache')) {
        Add-CleanTarget (Join-Path $absProjectDir $name)
    }

    # Web / Blazor caches
    # BUG FIX: dùng Join-Path với nhiều arg thay vì forward-slash literal trong string
    #          'wwwroot/_framework' trong 1 arg → trên Windows sẽ thành 1 path component sai
    if ($isWeb) {
        foreach ($pair in @(
            @('wwwroot', '_framework'),
            @('wwwroot', '_content'),
            @('.vite'),
            @('node_modules')
        )) {
            Add-CleanTarget ([System.IO.Path]::Combine(@($absProjectDir) + $pair))
        }
    }

    # MAUI-specific caches
    if ($isMaui) {
        foreach ($name in @('.maui', 'MauiAssets')) {
            Add-CleanTarget (Join-Path $absProjectDir $name)
        }
        # Dọn sạch Platforms/*/bin  Platforms/*/obj
        $platformsDir = Join-Path $absProjectDir 'Platforms'
        if (Test-Path -LiteralPath $platformsDir -PathType Container) {
            Get-ChildItem -LiteralPath $platformsDir -Directory -EA SilentlyContinue | ForEach-Object {
                Add-CleanTarget (Join-Path $_.FullName 'bin')
                Add-CleanTarget (Join-Path $_.FullName 'obj')
            }
        }
    }

    # ── 5. Xóa sớm các file cache NuGet hay gây lỗi TFM mismatch ─────────────
    # BUG FIX: dùng Join-Path với 2 arg riêng thay vì "obj/project.assets.json"
    $objDir     = Join-Path $absProjectDir "obj"
    $assetsFile = Join-Path $objDir "project.assets.json"
    if (Test-Path -LiteralPath $assetsFile -PathType Leaf) {
        try {
            Remove-Item -LiteralPath $assetsFile -Force -EA Stop
            Write-Log "   🗑️  Đã xóa project.assets.json (TFM mismatch cache)" $C_Gray
        } catch { }
    }

    if (Test-Path -LiteralPath $objDir -PathType Container) {
        Get-ChildItem -LiteralPath $objDir -Recurse -File -EA SilentlyContinue |
            Where-Object { $_.Extension -in @('.nuspec', '.cache') -or
                           $_.Name -in @('project.nuget.cache', 'project.assets.json') } |
            Where-Object { Assert-SafePath $_.FullName } |
            ForEach-Object {
                try { Remove-Item -LiteralPath $_.FullName -Force -EA Stop } catch {}
            }
    }

    # ── 6. Hàm xóa thư mục đa nền tảng với retry thông minh ──────────────────
    function Remove-SafeFolder {
        param([string]$FolderPath)
        if (-not (Test-Path -LiteralPath $FolderPath)) { return $true }
        if (-not (Assert-SafePath $FolderPath)) {
            Write-Warn "   ⛔ Bỏ qua path ngoài project: $FolderPath"
            return $false
        }

        $item = Get-Item -LiteralPath $FolderPath -Force -EA SilentlyContinue
        if ($item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            Write-Log "   ⚠️  Phát hiện symlink/junction, tiến hành gỡ link: $(Split-Path $FolderPath -Leaf)" $C_Warn
            try {
                if ($script:OS -eq 'Windows') {
                    # Dùng cmd rmdir để xóa junction/symlink thư mục cực kỳ an toàn, không đụng ruột
                    & cmd.exe /c rmdir "`"$FolderPath`""
                } else {
                    # Trên Linux/macOS
                    & unlink $FolderPath
                }
                return (-not (Test-Path -LiteralPath $FolderPath))
            } catch {
                Write-Warn "   ⚠️  Không gỡ được symlink: $FolderPath"
                return $false
            }
        }

        $maxRetries = 3; $delaySec = 1
        for ($i = 0; $i -lt $maxRetries; $i++) {
            try {
                Remove-Item -LiteralPath $FolderPath -Recurse -Force -EA Stop
                return $true
            } catch {
                if ($i -lt ($maxRetries - 1)) {
                    Start-Sleep -Seconds $delaySec
                    $delaySec *= 2
                } else {
                    Write-Warn "   ⚠️  Không xóa được (bị khóa/thiếu quyền): $(Split-Path $FolderPath -Leaf)"
                    return $false   # BUG FIX: return tường minh thay vì fall-through
                }
            }
        }
        return $false  # safety net — không bao giờ đến đây nhưng giữ type đúng
    }

    # ── 7. Thực thi & báo cáo ────────────────────────────────────────────────
    Write-Log "🧹 [SmartClean] Dọn cache an toàn & đa nền tảng..." $C_Info
    Write-Log "   📂 Root: $absProjectDir" $C_Gray

    $cleanedCount = 0; $failedCount = 0
    foreach ($folder in $targetsToClean) {
        $label = $folder.Replace($absProjectDir, '').TrimStart([System.IO.Path]::DirectorySeparatorChar,
                                                                [System.IO.Path]::AltDirectorySeparatorChar)
        Write-Host "   🗑️  $label" -NoNewline -ForegroundColor DarkGray
        if (Remove-SafeFolder $folder) {
            Write-Host "  ✅" -ForegroundColor Green
            $cleanedCount++
        } else {
            Write-Host "  ⚠️" -ForegroundColor Yellow
            $failedCount++
        }
    }

    if ($cleanedCount -eq 0 -and $failedCount -eq 0) {
        Write-Log "ℹ️  [SmartClean] Không có mục nào cần dọn." $C_Gray
    } elseif ($failedCount -eq 0) {
        Write-Log "✅ [SmartClean] Hoàn tất. Đã dọn $cleanedCount mục." $C_Succ
    } else {
        Write-Log "⚠️  [SmartClean] Hoàn tất với $failedCount lỗi. Đã dọn $cleanedCount/$($cleanedCount+$failedCount) mục." $C_Warn
    }
}
# ==================================================================================
# BUILD & DEPLOY
# ==================================================================================
function Invoke-DeviceDebug {
    param([string]$Project, [string]$Tfm)
    $sdk = Get-AndroidSdkPath
    if (!$sdk) { return }
    $adbExeName = if ($script:OS -eq 'Windows') { 'adb.exe' } else { 'adb' }
    $adb = Join-Path $sdk "platform-tools" $adbExeName
    if (!(Test-Path -LiteralPath $adb)) { return }
    $rawDevices = & $adb devices | Select-String -Pattern "\tdevice$"
    $devices = @(& $rawDevices | ForEach-Object { ($_ -split "`t")[0].Trim() })
    if ($devices.Count -eq 0) {
        Write-Log "❌ Không tìm thấy thiết bị Android nào đang kết nối!" $C_Err
        return
    }

     # Kiểm tra nhà sản xuất trước khi tối ưu
    $manufacturer = & $adb shell getprop ro.product.manufacturer 2>&1 | Out-String
    if ($manufacturer.Trim() -and $manufacturer.Trim() -eq 'Xiaomi') {
        Write-Log "🛠  Thiết bị Xiaomi – tối ưu cài đặt..." $C_Gray
        & $adb shell settings put global verifier_verify_adb_installs 0 2>&1 | Out-Null
        & $adb shell settings put global package_verifier_enable 0 2>&1 | Out-Null
    } else {
        Write-Log "ℹ️  Thiết bị không phải Xiaomi, bỏ qua tối ưu." $C_Gray
    }
    
    Write-Host "`n📱 PHÁT HIỆN THIẾT BỊ: $($devices[0].ToString().Trim())" -ForegroundColor $C_Info
    $confirm = Read-Host "`n❓ Bạn có muốn bắt đầu gỡ lỗi trên thiết bị này không? (Y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') { return }
    
    # Tái sử dụng $sdk đã lấy ở trên — KHÔNG gọi lại Get-AndroidSdkPath lần nữa
    $androidSdk = $sdk
    $javaSdk    = Get-JavaSdkPath

    # Lấy safe path cho project và các SDK
    $safeProject    = Get-SafePath $Project
    $safeAndroidSdk = Get-SafePath $androidSdk
    $safeJavaSdk    = Get-SafePath $javaSdk

    Write-Log "🚀 Đang triển khai app lên thiết bị..." $C_Succ

    # Dùng array để PS tự quote đúng từng argument
    $debugParams = @(
        "build", $safeProject,
        "-t:Run",
        "-f", $Tfm,
        "-p:AndroidSdkDirectory=$safeAndroidSdk",
        "-p:JavaSdkDirectory=$safeJavaSdk"
    )
    & $global:dotnetCmd @debugParams
}

function Invoke-AutoDeploy {
    param(
        [string]$ApkPath, 
        [string]$AppId,
        [string]$AndroidSdkPath
    )

    $sdk = $AndroidSdkPath
    if (-not $sdk) { $sdk = Get-AndroidSdkPath }  # fallback nếu không truyền
    $adbExeName = if ($script:OS -eq 'Windows') { 'adb.exe' } else { 'adb' }
    $adb = if ($sdk) { Join-Path $sdk "platform-tools" $adbExeName } else { "adb" }
    if (-not (Test-Path -LiteralPath $adb) -and $adb -ne "adb") { return }
    
    if (-not (Test-Path -LiteralPath $ApkPath)) { return }

    # Đảm bảo APK path an toàn trước khi truyền cho adb
    $safeApkPath = Get-SafePath $ApkPath
    
    $rawList = @(& $adb devices 2>&1)
    $allDevices = @($rawList | Where-Object { $_ -match "\tdevice$" } | ForEach-Object { ($_ -split "\t")[0].Trim() })
    if ($allDevices.Count -eq 0) { return }
    
    $realDevices = @($allDevices | Where-Object { $_ -notmatch "^emulator-" -and $_ -notmatch "^127\.0\.0\." })
    $emulators   = @($allDevices | Where-Object { $_ -match "^emulator-" -or $_ -match "^127\.0\.0\." })
    $targetDevice = if ($realDevices.Count -gt 0) { $realDevices[0] } else { $emulators[0] }
    
    Write-Log "🗑️  Gỡ app cũ ($AppId)..." $C_Warn
    & $adb -s $targetDevice uninstall $AppId 2>&1 | Out-Null
    Start-Sleep -Milliseconds 800
    
    Write-Log "📦 Đang cài APK..." $C_Info
    $installOut = & $adb -s $targetDevice install -r -d -t -g --no-streaming $safeApkPath 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Log "✅ Cài đặt thành công!" $C_Succ
        $mainAct = $installOut | Select-String "$AppId/" | Select-Object -First 1
        if ($mainAct) {
            $act = ($mainAct -split "$AppId/")[1].Trim() -replace "\s.*", ""
            if ($act) {
                Write-Log "🚀 Khởi động: $AppId/$act" $C_Info
                & $adb -s $targetDevice shell "am start -n $AppId/$act" 2>&1 | Out-Null
            }
        }
    } else {
        Write-Log "❌ Cài đặt thất bại! Mã lỗi: $LASTEXITCODE" $C_Err
        Write-Log $installOut $C_Warn
    }
}

function Invoke-KillByPort {
    param(
        [string]$ProjectDir, 
        [string]$ProjectType,
        [string]$ExeName,
        [string]$OutputDir = ""
    )

    # Chỉ áp dụng cho Web/Blazor, các loại khác bỏ qua
    if ($ProjectType -notin @('Web', 'BlazorWasm')) {
        return
    }

    Write-Log "🔍 Đang dừng tiến trình web cũ..." $C_Gray

    # Chuẩn hóa biến so sánh hoa/thường theo OS
    $pathCmpProc = if ($script:OS -eq 'Windows') { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }

    # 1. Kill các process có Path nằm trong thư mục output ($rawOut)
    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $procPath = $null
        try { 
            # Đọc Path có thể lỗi quyền truy cập ở các process hệ thống
            $procPath = $_.Path 
        } catch { 
            return $false 
        }
        
        # Nếu process không có Path hoặc Path trống thì bỏ qua
        if ([string]::IsNullOrWhiteSpace($procPath)) { 
            return $false 
        }

        # Trả về kết quả so sánh đường dẫn tuyệt đối
        return $procPath.StartsWith($rawOut, $pathCmpProc)
    } | Stop-Process -Force -ErrorAction SilentlyContinue

    Write-Log "   ✅ Đã quét dọn và giải phóng thư mục output an toàn." $C_Succ

    # Thu thập port từ nhiều nguồn
    $portsToKill = [System.Collections.Generic.HashSet[int]]::new()

    # --- Nguồn 1: launchSettings.json (chính xác nhất) ---
    $launchSettings = Join-Path $ProjectDir "Properties" "launchSettings.json"
    if (Test-Path -LiteralPath $launchSettings) {
        try {
            $ls = Get-Content -LiteralPath $launchSettings -Raw | ConvertFrom-Json
            # Duyệt tất cả profiles
            $ls.profiles.PSObject.Properties.Value | ForEach-Object {
                $_.applicationUrl -split ';' | ForEach-Object {
                    if ($_ -match ':(\d+)') { [void]$portsToKill.Add([int]$matches[1]) }
                }
            }
        } catch { }
    }

    # --- Nguồn 2: appsettings.json (Kestrel config) ---
    foreach ($cfgFile in @("appsettings.json", "appsettings.Production.json")) {
        $cfgPath = Join-Path $ProjectDir $cfgFile
        if (Test-Path -LiteralPath $cfgPath) {
            try {
                $cfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json
                $cfg.Kestrel?.Endpoints?.PSObject.Properties.Value.Url | ForEach-Object {
                    if ($_ -match ':(\d+)') { [void]$portsToKill.Add([int]$matches[1]) }
                }
                if ($cfg.Urls) {
                    $cfg.Urls -split ';' | ForEach-Object {
                        if ($_ -match ':(\d+)') { [void]$portsToKill.Add([int]$matches[1]) }
                    }
                }
            } catch {}
        }
    }

    # --- Nguồn 3: Fallback mặc định ASP.NET nếu không tìm thấy gì ---
    if ($portsToKill.Count -gt 0) {
        Write-Log "   📋 Port từ cấu hình: $($portsToKill -join ', ')" $C_Gray
        
        foreach ($port in $portsToKill) {
            if ($script:OS -eq 'Windows') {
                $conns = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
                foreach ($conn in $conns) {
                    if ($conn.OwningProcess -gt 0) {
                        try {
                            $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
                            if ($proc -and $proc.Path -and $proc.Path.StartsWith($OutputDir, [System.StringComparison]::OrdinalIgnoreCase)) {
                                Write-Log "   🔌 Giải phóng port $port (PID $($conn.OwningProcess))..." $C_Gray
                                Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
                            }
                        } catch {}
                    }
                }
            } else {
                # Xử lý cho Linux & macOS
                Write-Log "   🔌 Giải phóng port $port trên $($script:OS)..." $C_Gray
                if ($script:OS -eq 'MacOS') {
                    # lsof tìm tiến trình giữ port, xargs truyền PID cho lệnh kill
                    & sh -c "lsof -t -iTCP:$port -sTCP:LISTEN | xargs kill -9 2>/dev/null"
                } else { # Linux
                    # fuser tự động tìm và kill tiến trình dùng port tcp
                    & sh -c "fuser -k ${port}/tcp 2>/dev/null"
                }
            }
        }
    } else {
        Write-Log "   ℹ️ Không tìm thấy port cấu hình — chỉ kill theo tên exe." $C_Gray
    }
}

function ProcessBuildAndShow {
    param(
        [string]$Project, 
        [string]$Tfm, 
        [string]$OutputSubDir, 
        [string[]]$BuildArgs,
        [string]$ProjectType,
        [switch]$Incremental
    )

    $projectDir = Split-Path $Project -Parent

    # Bảo vệ: chỉ xử lý project nằm trong thư mục script
    $resolvedProjectDir = try { (Get-Item -LiteralPath $projectDir -EA Stop).FullName } catch { $null }
    $resolvedScriptRoot = try { (Get-Item -LiteralPath $script:ScriptRoot -EA Stop).FullName } catch { $null }
    if ($resolvedProjectDir -and $resolvedScriptRoot) {
        $guardRoot = $resolvedScriptRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        $guardProj = $resolvedProjectDir.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        $guardCmp  = if ($script:OS -eq 'Windows') { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
        if (-not $guardProj.StartsWith($guardRoot, $guardCmp)) {
            Write-Log "❌ [SAFETY] ProjectDir '$projectDir' nằm ngoài script root. Hủy để tránh xóa nhầm!" $C_Err
            exit 1
        }
    }

    # Dọn bin/obj và cache Android nếu là MAUI
    Invoke-SmartClean -ProjectDir $projectDir -OutputSubDir $OutputSubDir -CsprojPath $Project

    $rawOut = Join-Path $script:ScriptRoot "publish-output" $OutputSubDir
    $csprojContent = Get-Content -LiteralPath $Project -Raw -EA SilentlyContinue
    $exeBaseName = [System.IO.Path]::GetFileNameWithoutExtension($Project)

    # Kill process theo port (chỉ cho Web/BlazorWasm) – đã kiểm tra đường dẫn trong hàm
    Invoke-KillByPort -ProjectDir $projectDir -ProjectType $ProjectType -ExeName $exeBaseName -OutputDir $rawOut

    # ================================================================
    # DỪNG TIẾN TRÌNH CŨ + DỌN OUTPUT CÓ CHỌN LỌC
    # ================================================================
    Write-Log "🔍 Đang dừng tiến trình cũ trong $rawOut..." $C_Gray

    $pathCmpProc = if ($script:OS -eq 'Windows') { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }

    # 1. Kill các process có Path nằm trong $rawOut
    Get-Process | Where-Object {
        try { $_.Path -and $_.Path.StartsWith($rawOut, $pathCmpProc) } catch { $false }
    } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # 2. Quét và kill các process đang giữ file trong $rawOut (nếu còn) — Windows-only
    if ($script:OS -eq 'Windows') {
        $lockedProcs = Get-Process | Where-Object {
            try {
                foreach ($mod in $_.Modules) {
                    if ($mod.FileName -like (Join-Path $rawOut "*")) { return $true }
                }
            } catch {}
            return $false
        }
        if ($lockedProcs) {
            $fullSafeList = @(
                'Code','devenv','rider','fleet','explorer','svchost','System','Idle',
                'csrss','winlogon','services','lsass','smss','wininit','taskhostw','dwm',
                'conhost','powershell','pwsh',
                'OmniSharp','VBCSCompiler','RazorLanguageServer',
                'ServiceHub.RoslynCodeAnalysisService',
                'ServiceHub.IdentityHost','Microsoft.CodeAnalysis.LanguageServer',
                'Microsoft.ServiceHub.Controller','csc','MSBuild'
            )
            $lockedProcs | Where-Object { $_.Name -notin $fullSafeList } |
                Stop-Process -Force -ErrorAction SilentlyContinue
            Write-Log "   🎯 Đã kill tiến trình khóa file." $C_Warn
        }
    }

    # 3. Dọn artifact build cũ (chỉ khi KHÔNG Incremental)
    if (-not $Incremental) {
        if (Test-Path -LiteralPath $rawOut) {
            # File artifact theo phần mở rộng đặc trưng (không dùng *.json chung chung)
            $artifactExtensions = @(
                '.dll', '.exe', '.pdb', '.deps.json', '.runtimeconfig.json',
                '.xml', '.staticwebassets.runtime.json', '.so', '.dylib',
                '.apk', '.aab', '.msix', '.appxbundle', '.pkg', '.ipa',
                '.wasm', '.blat', '.dat', '.map'
            )
            Get-ChildItem -LiteralPath $rawOut -Recurse -File -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in $artifactExtensions } |
                Remove-Item -Force -ErrorAction SilentlyContinue

            # Xóa các thư mục artifact đặc trưng (do publish tạo)
            $artifactFolders = @('wwwroot', 'bin', 'obj', '_framework')
            foreach ($folderName in $artifactFolders) {
                $folderPath = Join-Path $rawOut $folderName
                if (Test-Path -LiteralPath $folderPath) {
                    Remove-Item -LiteralPath $folderPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

            # Xóa các thư mục rỗng còn sót
            Get-ChildItem -LiteralPath $rawOut -Directory -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { @(Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0 } |
                Remove-Item -Force -ErrorAction SilentlyContinue

            Write-Log "   ✅ Đã dọn artifact cũ, giữ nguyên file khác" $C_Gray
        } else {
            Write-Log "   ℹ️ Thư mục output chưa tồn tại" $C_Gray
        }
    } else {
        Write-Log "⚡ Incremental mode: bỏ qua dọn output." $C_Info
    }

    # Đảm bảo thư mục output tồn tại
    if (-not (Test-Path -LiteralPath $rawOut)) {
        New-Item -ItemType Directory -Force -Path $rawOut | Out-Null
    }
    Write-Log "   ✅ Thư mục output đã sẵn sàng." $C_Gray

    # ================================================================
    # CHUẨN BỊ BUILD
    # ================================================================
    $dotnetExe = $global:dotnetCmd
    if (-not $dotnetExe) {
        Write-Log "❌ KHÔNG TÌM THẤY SDK .NET!" $C_Err
        exit 1
    }

    $safeRawOut = Get-SafePath $rawOut
    $safeProject = Get-SafePath $Project

    Write-Log "🐞 Sử dụng dotnet: $dotnetExe" $C_Gray
    Write-Log "🐞 TFM: $Tfm | Output: $rawOut" $C_Gray
    Write-Log "🐞 Loại dự án: $ProjectType" $C_Gray

    # Kiểm tra nền tảng
    $isAndroidPlatform = $Tfm -match 'android'
    $isApplePlatform   = $Tfm -match '(ios|maccatalyst)'
    $isWindowsPlatform = $Tfm -match 'windows'
    
    $androidSdk = $null; $javaSdk = $null
    if ($isAndroidPlatform) {
        $androidSdk = Get-AndroidSdkPath
        $javaSdk    = Get-JavaSdkPath
        if (-not $androidSdk) { Write-Log "❌ Thiếu Android SDK!" $C_Err; exit 1 }
        if (-not $javaSdk)    { Write-Log "❌ Thiếu Java JDK!" $C_Err; exit 1 }
    }

    # Xây dựng tham số publish
    $params = @(
        "publish", $safeProject,
        "-f", $Tfm,
        "-c", "Release",
        "--output", $safeRawOut
    )

    switch ($ProjectType) {
        'MAUI' {
            if ($isAndroidPlatform) {
                $params += @("-p:AndroidUseSharedRuntime=false", "-p:EmbedAssembliesIntoApk=true")
            }
        }
        'Web' {
            if (-not $isWindowsPlatform -and -not $isAndroidPlatform -and -not $isApplePlatform) {
                $rid = Get-RuntimeIdentifier
                $params += @("-r", $rid, "--self-contained", "true")
                if ($BuildArgs -notcontains "-p:PublishSingleFile=false") {
                    $params += @("-p:PublishSingleFile=true", "-p:IncludeAllContentForSelfExtract=true")
                }
            }
        }
        { $_ -in @('WinForms', 'WPF', 'Console', 'WinExe') } {
            # Những loại này chỉ chạy trên Windows; vẫn dùng Get-RuntimeIdentifier để hỗ trợ arm64
            if ($BuildArgs -notcontains "--self-contained") { $params += "--self-contained" }
            if ($BuildArgs -notcontains "-r") { $params += "-r", (Get-RuntimeIdentifier) }
        }
        'BlazorWasm' {
            $params += @("-r", "browser-wasm")
        }
        'Library' {
            Write-Log "⚠️ Dự án dạng Library, chuyển sang build thay vì publish." $C_Warn
            $params = @(
                "build", $safeProject,
                "-f", $Tfm,
                "-c", "Release"
            )
        }
        default {
            Write-Log "⚠️ Loại dự án không xác định, dùng publish mặc định." $C_Warn
        }
    }

    if ($isAndroidPlatform) {
        if ($androidSdk) { $params += "-p:AndroidSdkDirectory=$androidSdk" }
        if ($javaSdk)    { $params += "-p:JavaSdkDirectory=$javaSdk" }
    }

    if ($BuildArgs) { $params += $BuildArgs }
    $params += @("-p:BuildInParallel=true", "-m")
    $params += "-v", "minimal"

    Write-Host ""
    Write-Sep
    Write-SubLog "dotnet publish  [$Tfm]"
    Write-Sep

    $sw        = [System.Diagnostics.Stopwatch]::StartNew()
    $copyCount = 0; $warnCount = 0; $errCount = 0
    $isProgressActive = $false

    $output = & $dotnetExe @params 2>&1 | ForEach-Object {
        $line = $_.ToString().TrimEnd()
        if ([string]::IsNullOrWhiteSpace($line)) { return $line }
        
        # Ẩn bớt các dòng copy file, chỉ đếm ngầm
        if ($line -match '^\s*Copying file from') { $copyCount++; return $line }
        
        # Nếu là Lỗi
        if ($line -match '(?i)\berror\b') {
            if ($isProgressActive) { Write-Host ""; $isProgressActive = $false }
            $errCount++; Write-Host "  ❌ $line" -ForegroundColor $C_Err
        }
        # Nếu là Cảnh báo
        elseif ($line -match '(?i)\bwarning\b') {
            if ($isProgressActive) { Write-Host ""; $isProgressActive = $false }
            $warnCount++; Write-Host "  ⚠️  $line" -ForegroundColor $C_Warn
        }
        # Nếu là các mốc hoàn thành quan trọng
        elseif ($line -match '(Build succeeded|Build FAILED|->\s|Publish:|Done Building|Time Elapsed)') {
            if ($isProgressActive) { Write-Host ""; $isProgressActive = $false }
            Write-Host "  ✔  $line" -ForegroundColor $C_Succ
        }
        # CÁC LOG KHÁC -> IN ĐÈ TRÊN 1 DÒNG ĐỂ LÀM TIẾN TRÌNH
        else {
            $shortLine = $line.Trim()
            # Cắt bớt nếu dòng log quá dài để không bị rớt dòng (word-wrap) làm vỡ giao diện
            if ($shortLine.Length -gt 70) { $shortLine = $shortLine.Substring(0, 67) + "..." }
            
            Write-Host "`r   ⚙️ Đang thực thi: $shortLine$(' ' * 20)" -NoNewline -ForegroundColor DarkGray
            $isProgressActive = $true
        }
        
        # Trả về line để lưu vào biến $output (dùng cho việc in lỗi cuối script)
        $line
    }
    
    # Dọn dẹp dòng tiến trình sau khi tiến trình dotnet kết thúc
    if ($isProgressActive) { Write-Host "`r$(' ' * 100)`r" -NoNewline }

    $exitCode = $LASTEXITCODE
    $sw.Stop()

    Write-Sep
    Write-SectionBox "KẾT QUẢ BUILD"

    if ($copyCount -gt 0) {
        _2Col "  📦 Static files" "$copyCount file(s) copied" $C_Gray "DarkGray"
    }

    if ($exitCode -ne 0) {
        Write-Fail "BUILD THẤT BẠI (exit $exitCode) — $errCount lỗi, $warnCount cảnh báo" $sw.Elapsed.TotalSeconds
        $output | Where-Object { $_ -match '(?i)\serror\s' } |
            ForEach-Object { Write-Host "    >> $_" -ForegroundColor $C_Err }
        exit 1
    }

    Write-Done "File APK/AAB/EXE đã sẵn sàng!" $sw.Elapsed.TotalSeconds

    # Tự động mở thư mục output (trừ Library)
    if ($ProjectType -ne 'Library') {
        Open-Directory $rawOut
    }

    # Auto Deploy cho Android APK
    if ($isAndroidPlatform -and $OutputSubDir -eq "apk") {
        $apkFile = Get-ChildItem -LiteralPath $rawOut -Filter "*Signed*.apk" -Recurse | Select-Object -First 1
        if (-not $apkFile) { $apkFile = Get-ChildItem -LiteralPath $rawOut -Filter "*.apk" -Recurse | Select-Object -First 1 }
        if ($apkFile) {
            $appIdMatch = [regex]::Match($csprojContent, '<ApplicationId>([^<]+)</ApplicationId>')
            $appId      = if ($appIdMatch.Success) { $appIdMatch.Groups[1].Value.Trim() } else { "com.companyname.app" }
            Write-Host "`n" -NoNewline
            Invoke-AutoDeploy -ApkPath $apkFile.FullName -AppId $appId -AndroidSdkPath $androidSdk
        } else {
            Write-Log "⚠️ Không tìm thấy APK để deploy." $C_Warn
            Open-Directory $rawOut   # Open-Directory tự xử lý theo OS
        }
    }
}

function Invoke-GitHubBuild([string]$PackageFormat) {
    Write-Log "☁ Đang kết nối GitHub Cloud..." $C_Info
    $ghCmd = Get-Command gh -EA SilentlyContinue
    if (-not $ghCmd) {
        Write-Log "❌ Không tìm thấy GitHub CLI (gh). Cài tại: https://cli.github.com" $C_Err
        return
    }
    $gh = $ghCmd.Source
    
    $branch = git branch --show-current 2>$null
    if (-not $branch) { $branch = "main" }
    
    Write-Log "🚀 Đang gửi yêu cầu build $PackageFormat lên nhánh $branch..." $C_Succ
    & $gh workflow run build.yml --ref $branch -f "package_format=$PackageFormat"
    Write-Log "✅ Đã trigger thành công. Vui lòng kiểm tra web GitHub." $C_Info
}

# ==================================================================================
# LẤY TFM CAO NHẤT
# ==================================================================================
function Get-LatestInstalledTfm([string[]]$SdksList) {
    try {
        if ($SdksList) {
            $latest = $SdksList[-1]
            if ($latest -match "^(\d+\.\d+)") {
                return "net$($matches[1])"
            }
        }
    } catch {}
    return "net9.0"
}

# ==================================================================================
# MAIN FLOW
# ==================================================================================
$TotalSteps = 4   # Khởi tạo | Quét project | Chọn chế độ | Build
$StepIndex  = 0

# Banner
Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║          🚀  MULTI-PURPOSE BUILD TOOL  —  VIP PRO MAX        ║
╚══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor $C_Header

# ── BƯỚC 1: Khởi tạo môi trường ──────────────────────────────────────────────────
$StepIndex++
$sw1 = [Diagnostics.Stopwatch]::StartNew()
Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Khởi tạo môi trường"
Write-SubLog "Kiểm tra .NET SDK"

$globalSdksList = $null
if ($global:dotnetCmd) {
    $globalSdksList = @(& $global:dotnetCmd --list-sdks 2>$null)
}
$currentTfm = Get-LatestInstalledTfm -SdksList $globalSdksList

# Cập nhật global.json một lần
$gJsonPath  = Join-Path $script:ScriptRoot 'global.json'

if ($globalSdksList) {
    $latestSdkVersion = ($globalSdksList[-1] -split ' ')[0]
    $needsUpdate = $true

    if (Test-Path -LiteralPath $gJsonPath) {
        try {
            $existing = Get-Content -LiteralPath $gJsonPath -Raw | ConvertFrom-Json
            if ($existing.sdk.version -eq $latestSdkVersion) { $needsUpdate = $false }
        } catch { }
    }

    if ($needsUpdate) {
        @{
            sdk = @{
                version     = $latestSdkVersion
                rollForward = 'latestMajor'
            }
        } | ConvertTo-Json | Out-File $gJsonPath -Encoding utf8 -Force
        Write-Done "Đã cập nhật global.json → $latestSdkVersion"
    } else {
        Write-Log "ℹ global.json đã mới nhất ($latestSdkVersion)" $C_Gray
    }
}
$sw1.Stop()
Write-Done "SDK: $currentTfm  |  dotnet: $([System.IO.Path]::GetFileName($global:dotnetCmd))" $sw1.Elapsed.TotalSeconds

# ── Tự động đồng bộ SDK path vào VS Code workspace settings ──────────────────────
Update-VSCodeDotnetPath -DotnetExePath $global:dotnetCmd

# ── BƯỚC 2: Quét project ─────────────────────────────────────────────────────────
$StepIndex++
$sw2 = [Diagnostics.Stopwatch]::StartNew()
Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Quét project"
Write-SubLog "Tìm kiếm .csproj"

$csproj = Find-Project
if (-not $csproj) { Write-Fail "Không tìm thấy project!"; exit 1 }
$projPath    = $csproj.FullName
$projectType = Get-ProjectType -csprojPath $projPath
$tfms        = @(Get-CsprojTfms -projPath $projPath)
# Ưu tiên TFM đã khai báo đúng chuẩn trong .csproj, nếu không có thì fallback sang $currentTfm
$winTfm      = ($tfms | Where-Object { $_ -match '-windows$' }) | Select-Object -First 1
if (-not $winTfm -and ($projectType -in @('WinForms','WPF','WinExe'))) { $winTfm = "$currentTfm-windows" }

$androidTfm  = $tfms | Where-Object { $_ -match 'android'      } | Select-Object -First 1
$iosTfm      = $tfms | Where-Object { $_ -match 'ios'          } | Select-Object -First 1
$macTfm      = $tfms | Where-Object { $_ -match 'maccatalyst'  } | Select-Object -First 1
$sw2.Stop()
Write-Done "Project: $($csproj.Name)  ($projectType)" $sw2.Elapsed.TotalSeconds

# ── BƯỚC 3: Menu chọn chế độ ─────────────────────────────────────────────────────
$StepIndex++
Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Chọn chế độ (Input)"

$choice = '0'
if ($GitHub -or $NonInteractive) {
    $choice = '13'
    Write-Info "Chế độ non-interactive → tự chọn GitHub Build"
} else {
    Write-Host ""
    Write-Host "  ⌨  Nhập số lựa chọn của bạn..." -ForegroundColor $C_Gray
    Write-Host ""

    switch ($projectType) {
        'MAUI' {
            if ($androidTfm) {
                Write-Host "  [1]  Debug trực tiếp trên thiết bị Android" -ForegroundColor $C_Gray
                Write-Host "  [2]  Xuất bản Android APK" -ForegroundColor $C_Info
                Write-Host "  [3]  Xuất bản Android AAB (Google Play)" -ForegroundColor $C_Info
            }
            if ($script:OS -eq 'MacOS') { Write-Host "  [4]  Xuất bản iOS IPA"       -ForegroundColor "Magenta" }
            if ($script:OS -eq 'MacOS') { Write-Host "  [5]  Xuất bản Mac Catalyst"  -ForegroundColor "Magenta" }
            if ($winTfm)                { Write-Host "  [6]  Xuất bản Windows MSIX"  -ForegroundColor "DarkYellow" }
        }
        'Web'       { Write-Host "  [7]  Xuất bản Web UI (EXE + tự khởi chạy)" -ForegroundColor "Cyan" }
        'BlazorWasm'{ Write-Host "  [7]  Xuất bản Blazor WASM"                  -ForegroundColor "Cyan" }
        'WinForms'  { Write-Host "  [8]  Xuất bản WinForms App"                 -ForegroundColor "DarkYellow" }
        'WPF'       { Write-Host "  [9]  Xuất bản WPF App"                      -ForegroundColor "DarkYellow" }
        'Console'   { Write-Host "  [10] Xuất bản Console App"                  -ForegroundColor "DarkYellow" }
        'Library'   { Write-Host "  [11] Build Library"                         -ForegroundColor "DarkYellow" }
        'WinExe'    { Write-Host "  [8]  Xuất bản Windows App"                  -ForegroundColor "DarkYellow" }
        default     { Write-Host "  [12] Build mặc định"                        -ForegroundColor "DarkYellow" }
    }
    Write-Host "  [13] ☁  GitHub Cloud Build" -ForegroundColor $C_Succ
    Write-Host "  [0]  Thoát" -ForegroundColor $C_Gray
    Write-Host ""

    $choice = Read-Host "  ►"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }
}

# ── BƯỚC 4: Thực thi build ───────────────────────────────────────────────────────
$StepIndex++

# ==================================================================================================
# [SECTION 5] THỰC THI THEO LỰA CHỌN
# ==================================================================================================
switch ($choice) {
    '1' {
        Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Debug: Android Device"
        Write-StepTitle "DEBUG TRỰC TIẾP TRÊN THIẾT BỊ ANDROID"
        if (!$androidTfm -or $projectType -ne 'MAUI') { Write-Fail "Không hỗ trợ!"; exit 1 }
        Invoke-DeviceDebug -Project $projPath -Tfm $androidTfm
    }
    '2' {
        Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang Build: ANDROID APK"
        Write-StepTitle "XUẤT BẢN ANDROID APK" -Color $C_Info
        ProcessBuildAndShow -Project $projPath -Tfm $androidTfm -OutputSubDir "apk" -BuildArgs @("-p:AndroidPackageFormat=apk") -ProjectType $projectType -Incremental:$Incremental
    }
    '3' {
        Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang Build: ANDROID AAB"
        Write-StepTitle "XUẤT BẢN ANDROID AAB (GOOGLE PLAY)" -Color "Magenta"

        # ── 1. Lấy thông tin keystore (tự động từ env hoặc fallback) ──
        $ks = $null
        $envKsPath  = $env:ANDROID_KEYSTORE_PATH
        $envKsPass  = $env:ANDROID_KEYSTORE_PASS
        $envKsAlias = $env:ANDROID_KEY_ALIAS
        $envKsKeyPass = $env:ANDROID_KEY_PASS

        if ($envKsPath -and (Test-Path -LiteralPath $envKsPath) -and $envKsPass) {
            $ks = @{
                Path      = $envKsPath
                StorePass = $envKsPass
                Alias     = if ($envKsAlias) { $envKsAlias } else { 'key0' }
                KeyPass   = if ($envKsKeyPass) { $envKsKeyPass } else { $envKsPass }
                Source    = 'environment'
            }
            Write-Log "✅ Đã nạp keystore từ biến môi trường." $C_Succ
        } else {
            $ks = Find-AndroidKeystore (Split-Path $projPath)
            if ($ks -and -not $ks.StorePass) {
                if (-not $NonInteractive) {
                    $ks = Read-KeystoreInteractive -ks $ks
                } else {
                    Write-Fail "NonInteractive: không có mật khẩu keystore, hủy build AAB."
                    exit 1
                }
            }
        }

        if (-not $ks -or -not $ks.StorePass) {
            Write-Fail "Không có thông tin ký, không thể build AAB."
            exit 1
        }

        # ── 2. Chuẩn bị file signing.properties (tự động) ──
        $projectDir = Split-Path $projPath
        $signingFile = Join-Path $projectDir 'signing.properties'
        $originalBackup = $null

        # Nếu file đã tồn tại, backup lại để phục hồi sau
        if (Test-Path -LiteralPath $signingFile) {
            $originalBackup = $signingFile + '.gbuild_backup'
            Copy-Item -LiteralPath $signingFile -Destination $originalBackup -Force
        }

        try {
            # Tạo signing.properties từ dữ liệu keystore
            @"
storeFile=$($ks.Path)
storePassword=$($ks.StorePass)
keyAlias=$($ks.Alias)
keyPassword=$($ks.KeyPass)
"@ | Out-File -FilePath $signingFile -Encoding utf8

            # ── 3. Build AAB ──
            $bArgs = @("-p:AndroidPackageFormat=aab")
            ProcessBuildAndShow -Project $projPath -Tfm $androidTfm -OutputSubDir "aab" -BuildArgs $bArgs -ProjectType $projectType -Incremental:$Incremental
        }
        finally {
            # ── 4. Dọn dẹp file tạm ──
            if ($originalBackup) {
                # Phục hồi file gốc của người dùng
                Move-Item -LiteralPath $originalBackup -Destination $signingFile -Force
            } else {
                # Xóa file do script tạo ra
                if (Test-Path -LiteralPath $signingFile) {
                    Remove-Item -LiteralPath $signingFile -Force
                }
            }
        }
    }
    '4' {
        Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang Build: iOS"
        Write-StepTitle "XUẤT BẢN iOS IPA" -Color "Magenta"
        ProcessBuildAndShow -Project $projPath -Tfm $iosTfm -OutputSubDir "ios" -BuildArgs @("-p:ArchiveOnBuild=true") -ProjectType $projectType -Incremental:$Incremental
    }
    '5' {
        Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang Build: Mac Catalyst"
        Write-StepTitle "XUẤT BẢN MAC CATALYST" -Color "Magenta"
        ProcessBuildAndShow -Project $projPath -Tfm $macTfm -OutputSubDir "mac" -ProjectType $projectType -Incremental:$Incremental
    }
    '6' {
        Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang Build: Windows MSIX"
        Write-StepTitle "XUẤT BẢN WINDOWS MSIX" -Color "DarkYellow"
        if ($projectType -eq 'MAUI') {
            $targetTfm = if ($winTfm) { $winTfm } else { "$currentTfm-windows" }
            ProcessBuildAndShow -Project $projPath -Tfm $targetTfm -OutputSubDir "win" -BuildArgs @("-p:WindowsPackageType=None","-p:PublishSingleFile=false","--self-contained","true") -ProjectType $projectType -Incremental:$Incremental
        }
    }
    '7' {
        if ($projectType -eq 'Web') {
            Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang Build: WEB"
            Write-StepTitle "XUẤT BẢN WEB UI" -Color $C_Info
            $swWeb = [Diagnostics.Stopwatch]::StartNew()
            ProcessBuildAndShow -Project $projPath -Tfm $currentTfm -OutputSubDir "web" -BuildArgs @("-p:PublishSingleFile=false") -ProjectType $projectType -Incremental:$Incremental
            $webOutDir     = Join-Path $script:ScriptRoot "publish-output" "web"
            # BUG FIX: trên macOS/Linux không có .exe — dùng tên file không extension
            $exeBaseName   = [System.IO.Path]::GetFileNameWithoutExtension($projPath)
            $exeSuffix     = if ($script:OS -eq 'Windows') { '.exe' } else { '' }
            $exePath       = Join-Path $webOutDir ($exeBaseName + $exeSuffix)
            $dynamicPort   = Get-ProjectPort -ProjectDir (Split-Path $projPath)
            $url           = "http://localhost:$dynamicPort"
            if (Test-Path -LiteralPath $exePath) {
                Write-SubLog "Khởi chạy ứng dụng ngầm tại $url"
                # BUG FIX: -WindowStyle Hidden chỉ có ý nghĩa trên Windows
                $spArgs = @{
                    FilePath        = (Get-SafePath $exePath)
                    ArgumentList    = "--urls=$url"
                    WorkingDirectory= (Get-SafePath $webOutDir)
                    PassThru        = $true
                }
                if ($script:OS -eq 'Windows') { $spArgs['WindowStyle'] = 'Hidden' }
                Start-Process @spArgs | Out-Null
                $maxWait = 15; $waited = 0; $portReady = $false
                while ($waited -lt $maxWait) {
                    Start-Sleep -Seconds 1; $waited++
                    if (Test-PortListening -Port $dynamicPort) { $portReady = $true; break }
                }
                $swWeb.Stop()
                if ($portReady) {
                    Open-Url $url
                    Write-Done "App đang chạy tại $url" $swWeb.Elapsed.TotalSeconds
                } else {
                    Write-Warn "App phản hồi chậm — kiểm tra tại: $url"
                }
            }
        } elseif ($projectType -eq 'BlazorWasm') {
            Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang Build: Blazor WASM"
            Write-StepTitle "XUẤT BẢN BLAZOR WASM" -Color $C_Info
            ProcessBuildAndShow -Project $projPath -Tfm $currentTfm -OutputSubDir "blazorwasm" -ProjectType $projectType -Incremental:$Incremental
        }
    }
    '8' {
        Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang Build: DESKTOP APP"
        Write-StepTitle "XUẤT BẢN DESKTOP APP" -Color "DarkYellow"

        $targetTfm = if ($winTfm) { $winTfm } elseif ($tfms) { $tfms[0] } else { "$currentTfm-windows" }

        if ($projectType -in @('WinForms','WinExe')) {
            ProcessBuildAndShow -Project $projPath -Tfm $targetTfm -OutputSubDir "winforms" -ProjectType $projectType -Incremental:$Incremental
        } elseif ($projectType -eq 'MAUI' -and $winTfm) {
            # $targetTfm đã được tính đúng ở trên — winTfm luôn được ưu tiên
            ProcessBuildAndShow -Project $projPath -Tfm $targetTfm -OutputSubDir "win" -BuildArgs @("-p:WindowsPackageType=None","-p:PublishSingleFile=false","--self-contained","true") -ProjectType $projectType -Incremental:$Incremental
        }
    }
    '9' {
        Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang Build: WPF"
        Write-StepTitle "XUẤT BẢN WPF APP" -Color "DarkYellow"
        if ($projectType -eq 'WPF') {
            ProcessBuildAndShow -Project $projPath -Tfm $currentTfm -OutputSubDir "wpf" -BuildArgs @("-r",(Get-RuntimeIdentifier),"--self-contained","true") -ProjectType $projectType -Incremental:$Incremental
        }
    }
    '10' {
        Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang Build: CONSOLE"
        Write-StepTitle "XUẤT BẢN CONSOLE APP" -Color "DarkYellow"
        if ($projectType -eq 'Console') {
            ProcessBuildAndShow -Project $projPath -Tfm $currentTfm -OutputSubDir "console" -BuildArgs @("-r",(Get-RuntimeIdentifier),"--self-contained","true") -ProjectType $projectType -Incremental:$Incremental
        }
    }
    '11' {
        Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Build: LIBRARY"
        Write-StepTitle "BUILD LIBRARY" -Color "Gray"
        if ($projectType -eq 'Library') {
            ProcessBuildAndShow -Project $projPath -Tfm $currentTfm -OutputSubDir "lib" -ProjectType $projectType -Incremental:$Incremental
        }
    }
    '12' {
        Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Build: DEFAULT"
        Write-StepTitle "BUILD MẶC ĐỊNH" -Color "Gray"
        ProcessBuildAndShow -Project $projPath -Tfm $currentTfm -OutputSubDir "default" -ProjectType $projectType -Incremental:$Incremental
    }
    '13' {
        Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "GitHub Cloud Build"
        Write-StepTitle "GỬI YÊU CẦU BUILD LÊN GITHUB" -Color $C_Succ
        $userInput = Read-Host "  📦 Định dạng (1=apk [mặc định] / 2=aab)"
        $fmt = if ($userInput -eq "2") { "aab" } else { "apk" }
        Write-SubLog "Kích hoạt GitHub Actions — $fmt"
        Invoke-GitHubBuild -PackageFormat $fmt
        Write-Done "Đã trigger GitHub Actions ($fmt)"
    }
    '0' {
        Write-Info "Đã thoát."
        exit 0
    }
    default {
        Write-Fail "Lựa chọn không hợp lệ: '$choice'"
        exit 1
    }
}

$totalSec = [math]::Round(((Get-Date) - $Global:StartTime).TotalSeconds, 1)
Write-Host ""
Write-Sep
_2Col "  🏁 HOÀN TẤT" "Tổng thời gian: ${totalSec}s" $C_Succ "DarkGray"
Write-Sep