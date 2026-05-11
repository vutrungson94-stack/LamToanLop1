#!/usr/bin/env pwsh
# ==================================================================================================
#  FILE NAME: gbuild.ps1
# ==================================================================================================
# --------------------------------------------------------------------------------------------------
# [SECTION 0] KHAI BÁO THAM SỐ
# --------------------------------------------------------------------------------------------------
param(
    [switch]$GitHub,
    [switch]$NonInteractive
)

# --------------------------------------------------------------------------------------------------
# [SECTION 1] CẤU HÌNH MÔI TRƯỜNG & BIẾN TOÀN CỤC
# --------------------------------------------------------------------------------------------------
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Global:StartTime = Get-Date

# Bảng màu log
$C_Header = "Magenta"; $C_Info = "Cyan"; $C_Warn = "Yellow"; $C_Err = "Red"; $C_Succ = "Green"; $C_Gray = "DarkGray"

# ==================================================================================================
# HÀM HIỂN THỊ & LOG — GIAO DIỆN 2 CỘT
# ==================================================================================================

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
function Draw-ProgressBar {
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

# Thiết lập UTF-8 toàn cục để mọi external process (dotnet, adb, git...)
# nhận và xuất Unicode đúng. Thiếu bước này thì mọi trick path đều vô nghĩa.
if ($IsWindows) {
    try { & chcp 65001 | Out-Null } catch {}
}
$OutputEncoding           = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8

function Get-SafePath {
    param([string]$path)

    if ([string]::IsNullOrWhiteSpace($path)) { return $path }

    # Trên non-Windows (macOS/Linux): resolve thành absolute path là đủ
    if (-not $IsWindows) {
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

# ==================================================================================================
# [SECTION 2] HÀM BỔ TRỢ (HELPERS)
# ==================================================================================================
function Remove-ItemForce {
    param([string]$TargetDir)
    if (-not (Test-Path $TargetDir)) { return $true }
    try { Remove-Item -LiteralPath $TargetDir -Recurse -Force -EA Stop; return $true } catch {}
    
    # Fallback Robocopy để phá lock OS
    $emptyDir = Join-Path $env:TEMP "gbuild_empty_$(Get-Random)"
    New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
    & robocopy "`"$emptyDir`"" "`"$TargetDir`"" /MIR /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    $exitCode = $LASTEXITCODE
    Remove-Item -LiteralPath $emptyDir -Force -EA SilentlyContinue
    if ($exitCode -le 7) {
        Remove-Item -LiteralPath $TargetDir -Recurse -Force -EA SilentlyContinue
        return (-not (Test-Path $TargetDir))
    }
    return $false
}

# Hàm lấy Port đầu tiên từ cấu hình dự án
function Get-ProjectPort {
    param([string]$ProjectDir)
    $port = 5000 # Mặc định nếu không tìm thấy gì
    $lsPath = Join-Path $ProjectDir "Properties\launchSettings.json"
    if (Test-Path $lsPath) {
        try {
            $ls = Get-Content $lsPath -Raw | ConvertFrom-Json
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
# ==================================================================================================
# HÀM TÌM KIẾM .NET SDK THÔNG MINH
# ==================================================================================================
function Get-SmartDotnetPath {
    Write-Host "🔍 Đang kiểm tra cache SDK .NET..." -ForegroundColor Cyan
    $cacheFile = Join-Path $PSScriptRoot ".sdkcache.json"

    # --- 1. ƯU TIÊN SỐ 1: KIỂM TRA CACHE (TỐC ĐỘ TỨC THÌ) ---
    if (Test-Path $cacheFile) {
        try {
            $cacheData = Get-Content $cacheFile -Raw | ConvertFrom-Json
            if ($cacheData.Path) {
                $cachedFolder = $cacheData.Path
                $dotnetExe = Join-Path $cachedFolder "dotnet.exe"
                if (Test-Path $dotnetExe) {
                    $sdkCheck = & $dotnetExe --list-sdks 2>&1
                    if ($sdkCheck -and $sdkCheck -match '\d+\.\d+') {
                        Write-Host "✅ Sử dụng SDK từ cache: $cachedFolder" -ForegroundColor Green
                        $safeSdkPath = Get-SafePath $cachedFolder
                        $env:DOTNET_ROOT = $safeSdkPath
                        $env:DOTNET_MSBUILD_SDK_RESOLVER_CLI_DIR = $safeSdkPath
                        $env:DOTNET_MULTILEVEL_LOOKUP = "0"
                        $env:PATH = "$safeSdkPath;" + $env:PATH
                        return $dotnetExe
                    }
                }
                Write-Host "⚠️ Cache SDK không còn hiệu lực, đang quét lại..." -ForegroundColor Yellow
            }
        } catch {
            Write-Host "⚠️ Lỗi đọc cache, tiến hành quét mới..." -ForegroundColor Yellow
        }
    }

    # --- 2. ƯU TIÊN SỐ 2: KIỂM TRA TRONG PATH HỆ THỐNG ---
    Write-Host "🔍 Đang kiểm tra dotnet trong PATH hệ thống..." -ForegroundColor Cyan
    $systemDotnet = Get-Command "dotnet" -ErrorAction SilentlyContinue
    if ($systemDotnet) {
        $sdkCheck = & dotnet --list-sdks 2>&1
        if ($sdkCheck -and $sdkCheck -match '\d+\.\d+') {
            $dotnetExe = $systemDotnet.Source
            $sdkFolder = Split-Path $dotnetExe -Parent
            Write-Host "✅ Sử dụng dotnet từ PATH: $sdkFolder" -ForegroundColor Green
            @{ Path = $sdkFolder } | ConvertTo-Json | Out-File $cacheFile -Encoding utf8 -Force
            return $dotnetExe
        }
    }

    # --- 3. ƯU TIÊN SỐ 3: QUÉT NHANH THƯ MỤC HIỆN TẠI (DEPTH 4) ---
    Write-Host "⚙️ Đang quét nhanh thư mục dự án..." -ForegroundColor Cyan
    $quickPaths = @($PSScriptRoot, (Get-Location).Path) | Select-Object -Unique
    foreach ($qPath in $quickPaths) {
        $sdks = Get-ChildItem -Path $qPath -Directory -Recurse -Depth 4 -Filter '.sdk' -ErrorAction SilentlyContinue
        foreach ($sdkDir in $sdks) {
            $dotnetExe = Join-Path $sdkDir.FullName "dotnet.exe"
            if (Test-Path $dotnetExe) {
                $sdkCheck = & $dotnetExe --list-sdks 2>&1
                if ($sdkCheck -match '\d+\.\d+') {
                    $foundPath = $sdkDir.FullName
                    Write-Host "✅ Đã tìm thấy SDK local: $foundPath" -ForegroundColor Green
                    $safeSdkPath = Get-SafePath $foundPath
                    $env:DOTNET_ROOT = $safeSdkPath
                    $env:PATH = "$safeSdkPath;" + $env:PATH
                    @{ Path = $foundPath } | ConvertTo-Json | Out-File $cacheFile -Encoding utf8 -Force
                    return $dotnetExe
                }
            }
        }
    }

    # --- 4. ƯU TIÊN SỐ 4: QUÉT TOÀN BỘ Ổ ĐĨA (HYBRID SCANNING) ---
    # Chiến thuật: Né các hố đen dữ liệu để không treo máy, quét sâu dần
    Write-Host "⚙️ Đang quét sâu các ổ đĩa để tìm SDK (Vui lòng chờ)..." -ForegroundColor Cyan
    $excludeDirs = @('Windows', 'AppData', '$Recycle.Bin', 'System Volume Information', 'ProgramData', 'Microsoft', 'Package Cache')
    $allDrives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -gt 0 } | Select-Object -ExpandProperty Root

    foreach ($drive in $allDrives) {
        $root = $drive + "\"
        Write-Host "   Rà soát ổ $root..." -ForegroundColor DarkGray

        # GIAI ĐOẠN A: Quét cực nhanh các thư mục .sdk ở cấp cao (Depth 2)
        $quickSearch = Get-ChildItem -Path $root -Directory -Depth 2 -Filter '.sdk' -ErrorAction SilentlyContinue
        
        # GIAI ĐOẠN B: Nếu không thấy, quét sâu vào các thư mục tiềm năng
        $potentialDirs = if ($quickSearch) { $quickSearch } else {
            Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin $excludeDirs }
        }

        foreach ($dir in $potentialDirs) {
            # Quét sâu thêm 5 cấp bên trong mỗi thư mục tiềm năng (Tổng cộng 6 cấp từ gốc)
            $deepSdks = Get-ChildItem -Path $dir.FullName -Directory -Recurse -Depth 5 -Filter '.sdk' -ErrorAction SilentlyContinue
            foreach ($sdkDir in $deepSdks) {
                $dotnetExe = Join-Path $sdkDir.FullName "dotnet.exe"
                if (Test-Path $dotnetExe) {
                    $sdkCheck = & $dotnetExe --list-sdks 2>&1
                    if ($sdkCheck -match '\d+\.\d+') {
                        $foundPath = $sdkDir.FullName
                        Write-Host "✅ Đã tìm thấy SDK tại: $foundPath" -ForegroundColor Green
                        $safeSdkPath = Get-SafePath $foundPath
                        $env:DOTNET_ROOT = $safeSdkPath
                        $env:PATH = "$safeSdkPath;" + $env:PATH
                        @{ Path = $foundPath } | ConvertTo-Json | Out-File $cacheFile -Encoding utf8 -Force
                        return $dotnetExe
                    }
                }
            }
        }
    }

    Write-Host "❌ Không tìm thấy bất kỳ SDK .NET hợp lệ nào." -ForegroundColor Red
    return $null
}
# Khởi tạo biến $dotnetCmd để sử dụng cho toàn bộ quá trình build phía sau
$global:dotnetCmd = Get-SmartDotnetPath
if (-not $global:dotnetCmd) {
    Write-Host "❌ Không có SDK .NET, không thể tiếp tục." -ForegroundColor Red
    exit 1
}

# Tìm Android SDK
function Get-AndroidSdkPath {
    Write-Log "🔍 Đang săn tìm Android SDK..." $C_Gray
    $searchList = @(
        (Join-Path $PSScriptRoot ".sdk\android-sdk"),
        (Join-Path $PSScriptRoot "..\.sdk\android-sdk"),
        (Join-Path (Get-Location) ".sdk\android-sdk"),
        $env:ANDROID_HOME,
        $env:ANDROID_SDK_ROOT,
        (Join-Path $env:LOCALAPPDATA "Android\Sdk"),
        "C:\Program Files (x86)\Android\android-sdk",
        "C:\Android\android-sdk"
    )
    foreach ($p in $searchList) {
        if ($p -and (Test-Path $p)) {
            $found = (Get-Item -LiteralPath $p).FullName.TrimEnd('\')
            Write-Log "✅ Đã thấy Android SDK: $found" $C_Succ
            $safePath = Get-SafePath $found
            # [FIX v4.2.0] Set ANDROID_HOME với safe path để child processes dùng được
            $env:ANDROID_HOME     = $safePath
            $env:ANDROID_SDK_ROOT = $safePath
            return $safePath
        }
    }

    # Nếu chưa tìm thấy, quét các ổ cứng cố định với độ sâu 3
    Write-Log "⚙️ Đang quét ổ cứng tìm Android SDK..." $C_Gray
    $fixedDrives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Select-Object -ExpandProperty DeviceID
    foreach ($drive in $fixedDrives) {
        $root = $drive + "\"
        $androidDirs = Get-ChildItem -Path $root -Directory -Recurse -Depth 4 -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -eq "android-sdk" -or (Test-Path (Join-Path $_.FullName "platform-tools\adb.exe")) }
        if ($androidDirs) {
            $found = $androidDirs[0].FullName
            Write-Log "✅ Đã thấy Android SDK: $found" $C_Succ
            $safePath = Get-SafePath $found
            $env:ANDROID_HOME     = $safePath
            $env:ANDROID_SDK_ROOT = $safePath
            return $safePath
        }
    }

    Write-Log "❌ Không tìm thấy Android SDK." $C_Err
    return $null
}

# Tìm Java JDK
function Get-JavaSdkPath {
    # 1. Kiểm tra các vị trí ưu tiên (gần script, biến môi trường)
    $searchList = @(
        (Join-Path $PSScriptRoot ".sdk\jdk"),
        (Join-Path $PSScriptRoot "..\.sdk\jdk"),
        (Join-Path $PSScriptRoot "..\..\..\.sdk\jdk"),
        (Join-Path (Get-Location) ".sdk\jdk"),
        $env:JAVA_HOME
    )
    foreach ($p in $searchList) {
        if ($p -and (Test-Path (Join-Path $p "bin\javac.exe"))) {
            Write-Log "✅ Đã tìm thấy Java SDK: $p" $C_Succ
            $safePath = Get-SafePath $p
            # [FIX v4.2.0] Set JAVA_HOME với safe path
            $env:JAVA_HOME = $safePath
            return $safePath
        }
    }

    # 2. Quét các ổ đĩa cục bộ tìm thư mục chứa `bin\javac.exe` (độ sâu 5)
    Write-Log "⚙️ Đang quét ổ đĩa tìm Java SDK..." $C_Gray
    $fixedDrives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Select-Object -ExpandProperty DeviceID
    foreach ($drive in $fixedDrives) {
        $root = $drive + "\"
        # Tìm `javac.exe` với độ sâu 5 (đủ cho `.sdk/jdk/bin` hoặc `Common/.sdk/jdk/bin`)
        $javacCandidates = @(Get-ChildItem -Path $root -Filter "javac.exe" -Recurse -Depth 5 -ErrorAction SilentlyContinue)
        foreach ($javac in $javacCandidates) {
            $binDir = $javac.Directory
            $jdkDir = $binDir.Parent.FullName
            # Kiểm tra cấu trúc thư mục `jdk/bin/javac.exe` và có `java.exe`
            if ((Test-Path (Join-Path $jdkDir "bin\javac.exe")) -and (Test-Path (Join-Path $jdkDir "bin\java.exe"))) {
                Write-Log "✅ Đã tìm thấy Java SDK: $jdkDir" $C_Succ
                $safePath = Get-SafePath $jdkDir
                $env:JAVA_HOME = $safePath
                return $safePath
            }
        }
    }

    # 3. Không tìm thấy
    Write-Log "❌ Không tìm thấy Java JDK. Hãy đặt JDK vào thư mục '.sdk\jdk' gần script hoặc cài đặt JDK." $C_Err
    return $null
}

# Đọc TFMs
function Get-CsprojTfms {
    param([string]$projPath)
    if (-not (Test-Path $projPath)) { return @() }
    $content = Get-Content $projPath -Raw
    $tfms = @()
    $tfmMatches = [regex]::Matches($content, '<TargetFrameworks?>([^<]+)</TargetFrameworks?>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    foreach ($m in $tfmMatches) {
        $val = $m.Groups[1].Value.Trim()
        $parts = $val.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)
        foreach ($p in $parts) { $tfms += $p.Trim() }
    }
    return $tfms | Sort-Object -Unique
}

# Tìm project
function Find-Project {
    Write-Log "📂 Đang quét tìm file project..." $C_Gray
    $allProjects = @(Get-ChildItem -Path . -Recurse -Filter *.csproj -File |
        Where-Object { $_.FullName -notmatch '[\\/](obj|bin|node_modules|\.sdk)[\\/]' } |
        Sort-Object FullName)

    if ($allProjects.Count -eq 0) {
        return $null
    }
    if ($allProjects.Count -eq 1) {
        return $allProjects[0]
    }

    # Ưu tiên project cùng thư mục với script
    $scriptDirProjects = @($allProjects | Where-Object { $_.DirectoryName -eq $PSScriptRoot })
    if ($scriptDirProjects.Count -eq 1) {
        return $scriptDirProjects[0]
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

# Phân loại project
function Get-ProjectType {
    param([string]$csprojPath)
    if (-not (Test-Path $csprojPath)) { return "Unknown" }

    $content = Get-Content $csprojPath -Raw -EA SilentlyContinue
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

# Quản lý Keystore
function Find-AndroidKeystore([string]$projectDir) {
    Write-Log "🔐 Đang tìm kiếm Keystore để ký..." $C_Gray
    $propsFile = Join-Path $projectDir 'signing.properties'
    if (Test-Path $propsFile) {
        $props = @{}
        Get-Content $propsFile | ForEach-Object { if ($_ -match '^\s*([^#=]+?)\s*=\s*(.+)$') { $props[$matches[1].Trim()] = $matches[2].Trim() } }
        $ksPath = $props['storeFile']
        if ($ksPath -and -not ([System.IO.Path]::IsPathRooted($ksPath))) { $ksPath = Join-Path $projectDir $ksPath }
        if ($ksPath -and (Test-Path $ksPath)) {
            Write-Log "📝 Đã nạp thông tin từ signing.properties" $C_Succ
            return @{ Path = $ksPath; StorePass = $props['storePassword']; Alias = $props['keyAlias']; KeyPass = $props['keyPassword']; Source = 'properties' }
        }
    }
    $ksFile = Get-ChildItem $projectDir -Recurse -Include *.keystore,*.jks | Where-Object { $_.FullName -notmatch '[\\/](obj|bin)[\\/]' } | Select-Object -First 1
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
# [SECTION 2.1] CLEAN & KILL UNIFIED — MẠNH NHẤT, CHỐNG LOCK FILE TOÀN DIỆN
#   Tích hợp Invoke-KillBuildProcesses vào Invoke-SmartClean thành một hàm duy nhất.
#   Luồng xử lý 4 bước theo mức độ leo thang (escalation):
#     Bước 0   → Kill build system (dotnet, msbuild, compiler, language server)
#     Bước 0.5 → Kill process giữ file trong bin/obj/.vs của project nguồn
#     Bước 0.7 → Kill EXE publish cũ đang chạy trong publish-output (từ lần build trước)
#     Bước 1   → Xóa bin/obj/.vs với retry + robocopy fallback + escalation kill lại nếu cần
#     Bước 2   → Dọn cache phụ (Xamarin/Android)
# ==================================================================================================

# Hàm Kill & Clean tổng hợp — thay thế cả Invoke-KillBuildProcesses lẫn Invoke-SmartClean cũ
function Invoke-SmartClean {
    param(
        [string]$ProjectDir,
        [string]$OutputSubDir = ""   # tuỳ chọn: nếu có → kill EXE cũ trong publish-output/<OutputSubDir>
    )

    # Danh sách process IDE / hệ thống tuyệt đối KHÔNG ĐƯỢC KILL
    $safeList = @(
        'Code', 'devenv', 'rider', 'fleet',
        'explorer', 'svchost', 'System', 'Idle',
        'csrss', 'winlogon', 'services', 'lsass',
        'smss', 'wininit', 'taskhostw', 'dwm', 'conhost', 'powershell', 'pwsh'
    )

    # Danh sách build tools cần kill (dùng lại ở Bước 1 khi escalate)
    #$buildProcs = @(
    #    'dotnet', 'msbuild', 'csc', 'vbcscompiler', 'VBCSCompiler', 'MSBuild',
    #    'OmniSharp', 'RazorLanguageServer',
    #    'ServiceHub.RoslynCodeAnalysisService', 'Microsoft.ServiceHub.Controller'
    #)

    Write-Log "🧹 [SmartClean] Bắt đầu dọn dẹp toàn diện..." $C_Info

    # ============================================================
    # BƯỚC 0.5: KILL TIẾN TRÌNH GIỮ FILE TRONG bin / obj / .vs
    # ============================================================
    Write-Log "   🔍 [Bước 0.5] Quét process khóa file bin/obj/.vs..." $C_Gray
    $srcFolders = @(
        "$ProjectDir\bin",
        "$ProjectDir\obj",
        "$ProjectDir\.vs"
    )
    Get-Process | ForEach-Object {
        $proc = $_
        if ($proc.Name -in $safeList) { return }
        $hit = $false
        try {
            foreach ($mod in $proc.Modules) {
                if ($mod.FileName -and (
                    $srcFolders | Where-Object { $mod.FileName.StartsWith($_, [System.StringComparison]::OrdinalIgnoreCase) }
                )) { $hit = $true; break }
            }
        } catch {}
        if ($hit) {
            Write-Log "      🎯 Kill (bin/obj lock): $($proc.Name) PID=$($proc.Id)" $C_Gray
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        }
    }
    Start-Sleep -Milliseconds 800

    # ============================================================
    # BƯỚC 0.7: KILL EXE PUBLISH CŨ ĐANG CHẠY
    #   — quét tất cả *.exe trong publish-output/<OutputSubDir>
    #   — kill theo BaseName (Get-Process không dùng .exe)
    #   — belt-and-suspenders: kill theo đường dẫn
    # ============================================================
    if (-not [string]::IsNullOrWhiteSpace($OutputSubDir)) {
        $publishOut = Join-Path $PSScriptRoot "publish-output\$OutputSubDir"
        if (Test-Path $publishOut) {
            Write-Log "   🔫 [Bước 0.7] Kill EXE publish cũ trong: $publishOut..." $C_Gray
            $exeFiles = @(Get-ChildItem -Path $publishOut -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue)
            foreach ($exe in $exeFiles) {
                # Kill theo tên process (BaseName, không có .exe)
                $running = @(
                    Get-Process -Name $exe.BaseName -ErrorAction SilentlyContinue | Where-Object {
                        try { $_.Path -and $_.Path.StartsWith($publishOut, [System.StringComparison]::OrdinalIgnoreCase) }
                        catch { $false }
                    }
                )
                if ($running.Count -gt 0) {
                    $running | Stop-Process -Force -ErrorAction SilentlyContinue
                    Write-Log "      🎯 Kill EXE cũ: $($exe.Name) (PID: $($running.Id -join ', '))" $C_Warn
                }
            }
            # Belt-and-suspenders: bất kỳ process nào path bắt đầu bằng $publishOut
            Get-Process | ForEach-Object {
                $p = $_
                if ($p.Name -in $safeList) { return }
                try {
                    if ($p.Path -and $p.Path.StartsWith($publishOut, [System.StringComparison]::OrdinalIgnoreCase)) {
                        Write-Log "      🎯 Kill by path: $($p.Name) PID=$($p.Id)" $C_Gray
                        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                    }
                } catch {}
            }
            Start-Sleep -Milliseconds 500
        }
    }

    # ============================================================
    # BƯỚC 1: XÓA bin / obj / .vs VỚI RETRY + ESCALATION
    #   Tầng 1: Remove-Item trực tiếp
    #   Tầng 2: robocopy /MIR empty → xóa (phá lock OS)
    #   Tầng 3: Escalate kill lại → retry (tối đa 25 giây)
    # ============================================================
    $foldersToClean = @(
        (Join-Path $ProjectDir "bin"),
        (Join-Path $ProjectDir "obj"),
        (Join-Path $ProjectDir ".vs")
    )

    foreach ($folder in $foldersToClean) {
        if (-not (Test-Path $folder)) { continue }

        $maxWaitSec = 25
        $retryDelay = 1
        $totalWait  = 0
        $deleted    = $false

        while (-not $deleted -and $totalWait -lt $maxWaitSec) {

            # ── Tầng 1: Remove-Item & Tầng 2: robocopy /MIR──────────────────────────────
            if (Remove-ItemForce -TargetDir $folder) {
                $deleted = $true
                Write-Log "   ✅ Đã dọn dẹp an toàn: $folder" $C_Gray
                continue
            }

            # ── Tầng 3: Escalate kill → sẽ retry vòng lặp ──────
            Write-Log "   ⚠️ Không xóa được $folder → escalate kill (đã chờ ${totalWait}s)..." $C_Warn
            
            Get-Process | Where-Object { $_.Name -notin $safeList } | ForEach-Object {
            $p = $_
            try {
                # Quét các module (file DLL/EXE) mà process đang nạp
                $isLocked = $false
                foreach ($mod in $p.Modules) {
                    if ($mod.FileName -and $mod.FileName.StartsWith($folder, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $isLocked = $true
                        break
                    }
                }
                
                # Nếu phát hiện khóa, tiêu diệt chính xác process đó
                if ($isLocked) {
                    Write-Log "      🎯 Escalate kill chuẩn xác: $($p.Name) PID=$($p.Id)" $C_Gray
                    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                }
            } catch {
                # Bỏ qua các process hệ thống không có quyền truy cập module
            }
        }
            Start-Sleep -Seconds $retryDelay
            $totalWait += $retryDelay
            $retryDelay = [Math]::Min($retryDelay * 2, 5)
        }

        if (-not $deleted) {
            Write-Log "   ❌ KHÔNG THỂ XÓA: $folder (sau $maxWaitSec giây)." $C_Err
            $userChoice = Read-Host "   Tiếp tục build mà không xóa thư mục này? (y/n)"
            if ($userChoice -ne 'y') {
                Write-Log "❌ Hủy build theo yêu cầu." $C_Err
                exit 1
            }
        }
    }

    # ============================================================
    # BƯỚC 2: DỌN CACHE PHỤ (Xamarin / Android)
    # ============================================================
    $androidCache = Join-Path $env:LOCALAPPDATA "Xamarin\MonoAndroid"
    if (Test-Path $androidCache) {
        try {
            Get-ChildItem $androidCache -Recurse -Include "*.stamp","res.zip.*","__environment__.txt" -EA SilentlyContinue |
                Remove-Item -Force -EA SilentlyContinue
        } catch {}
    }

    Write-Log "✅ [SmartClean] Hoàn tất." $C_Succ
}

# ==================================================================================================
# [SECTION 3] TIẾN TRÌNH BUILD & DEPLOY
# ==================================================================================================

function Invoke-DeviceDebug {
    param([string]$Project, [string]$Tfm)
    $sdk = Get-AndroidSdkPath
    if (!$sdk) { return }
    $adb = Join-Path $sdk "platform-tools\adb.exe"
    if (!(Test-Path $adb)) { return }
    $devices = @(& $adb devices | Select-String -Pattern "\tdevice$")
    if ($devices.Count -eq 0) {
        Write-Log "❌ Không tìm thấy thiết bị Android nào đang kết nối!" $C_Err
        return
    }
    Write-Log "🛠  Đang tối ưu cài đặt cho Xiaomi..." $C_Gray
    & $adb shell settings put global verifier_verify_adb_installs 0 2>&1 | Out-Null
    & $adb shell settings put global package_verifier_enable 0 2>&1 | Out-Null
    
    Write-Host "`n📱 PHÁT HIỆN THIẾT BỊ: $($devices[0].ToString().Trim())" -ForegroundColor $C_Info
    $confirm = Read-Host "`n❓ Bạn có muốn bắt đầu gỡ lỗi trên thiết bị này không? (Y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') { return }
    
    $androidSdk = Get-AndroidSdkPath
    $javaSdk    = Get-JavaSdkPath

    # [FIX v4.2.0] Lấy safe path cho project và các SDK
    $safeProject    = Get-SafePath $Project
    $safeAndroidSdk = Get-SafePath $androidSdk
    $safeJavaSdk    = Get-SafePath $javaSdk

    Write-Log "🚀 Đang triển khai app lên thiết bị..." $C_Succ

    # [FIX v4.2.0] Bỏ bug cũ: $Project bị truyền 2 lần (lần 2 là (Get-SafePath $Project))
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
    $adb = if ($sdk) { Join-Path $sdk "platform-tools\adb.exe" } else { "adb" }
    if (-not (Test-Path $adb) -and $adb -ne "adb") { return }
    
    if (-not (Test-Path $ApkPath)) { return }

    # [FIX v4.2.0] Đảm bảo APK path an toàn trước khi truyền cho adb
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
    # [FIX v4.2.0] Dùng $safeApkPath thay vì $ApkPath trực tiếp
    $installOut = & $adb -s $targetDevice install -r -d -t -g --no-streaming $safeApkPath 2>&1
    
    if ($installOut -match "Success") {
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
        Write-Log "❌ Cài đặt thất bại!" $C_Err
        Write-Log $installOut $C_Warn
    }
}

# ✅ Hàm kill port thông minh — chỉ chạy khi là Web project, tự tìm port
function Invoke-KillByPort {
    param([string]$ProjectDir, [string]$ProjectType)

    # Chỉ áp dụng cho Web/Blazor, các loại khác bỏ qua
    if ($ProjectType -notin @('Web', 'BlazorWasm')) {
        return
    }

    # Thu thập port từ nhiều nguồn
    $portsToKill = [System.Collections.Generic.HashSet[int]]::new()

    # --- Nguồn 1: launchSettings.json (chính xác nhất) ---
    $launchSettings = Join-Path $ProjectDir "Properties\launchSettings.json"
    if (Test-Path $launchSettings) {
        try {
            $ls = Get-Content $launchSettings -Raw | ConvertFrom-Json
            # Duyệt tất cả profiles
            $ls.profiles.PSObject.Properties.Value | ForEach-Object {
                $rawUrls = $_.applicationUrl
                if ($rawUrls) {
                    $rawUrls -split ';' | ForEach-Object {
                        if ($_ -match ':(\d+)') {
                            [void]$portsToKill.Add([int]$matches[1])
                        }
                    }
                }
            }
            Write-Log "   📋 Tìm thấy port từ launchSettings.json: $($portsToKill -join ', ')" $C_Gray
        } catch {
            Write-Log "   ⚠️ Không đọc được launchSettings.json" $C_Warn
        }
    }

    # --- Nguồn 2: appsettings.json (Kestrel config) ---
    foreach ($appSettings in @("appsettings.json", "appsettings.Production.json")) {
        $appSettingsPath = Join-Path $ProjectDir $appSettings
        if (Test-Path $appSettingsPath) {
            try {
                $cfg = Get-Content $appSettingsPath -Raw | ConvertFrom-Json
                $urls = $cfg.Kestrel?.Endpoints?.PSObject.Properties.Value.Url
                if ($urls) {
                    $urls | ForEach-Object {
                        if ($_ -match ':(\d+)') {
                            [void]$portsToKill.Add([int]$matches[1])
                        }
                    }
                }
                # Đọc cả "Urls" key
                if ($cfg.Urls) {
                    $cfg.Urls -split ';' | ForEach-Object {
                        if ($_ -match ':(\d+)') { [void]$portsToKill.Add([int]$matches[1]) }
                    }
                }
            } catch {}
        }
    }

    # --- Nguồn 3: Fallback mặc định ASP.NET nếu không tìm thấy gì ---
    if ($portsToKill.Count -eq 0) {
        Write-Log "   ℹ️ Không tìm thấy port trong config, dùng mặc định ASP.NET (5000, 5001)" $C_Gray
        [void]$portsToKill.Add(5000)
        [void]$portsToKill.Add(5001)
    }

    # --- Kill tất cả process đang giữ các port tìm được ---
    foreach ($port in $portsToKill) {
        try {
            $conns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
            foreach ($conn in $conns) {
                if ($conn.OwningProcess -gt 0) {
                    Write-Log "   🔌 Giải phóng port $port (PID $($conn.OwningProcess))..." $C_Gray
                    Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
                }
            }
        } catch {}
    }
}

function ProcessBuildAndShow {
    param(
        [string]$Project, 
        [string]$Tfm, 
        [string]$OutputSubDir, 
        [string[]]$BuildArgs,
        [string]$ProjectType
    )

    $projectDir = Split-Path $Project -Parent
    # OutputSubDir truyền vào để SmartClean kill luôn EXE publish cũ (Bước 0.7)
    Invoke-SmartClean -ProjectDir $projectDir -OutputSubDir $OutputSubDir

    $rawOut = Join-Path $PSScriptRoot "publish-output\$OutputSubDir"
    $csprojContent = Get-Content $Project -Raw -EA SilentlyContinue
    # Kill theo port (chỉ áp dụng với Web/BlazorWasm)
    Invoke-KillByPort -ProjectDir $projectDir -ProjectType $ProjectType

    # ------------------------------------------------------------
    # KILL TIẾN TRÌNH CŨ + XÓA TOÀN BỘ THƯ MỤC OUTPUT (BẮT BUỘC)
    # ------------------------------------------------------------
    Write-Log "🔍 Đang dừng tiến trình cũ trong $rawOut..." $C_Gray

    $exeBaseName = [System.IO.Path]::GetFileNameWithoutExtension($Project)  # dùng cho Get-Process
    $maxAttempts = 5
    $attempt = 0
    $outputDeleted = $false

    while (-not $outputDeleted -and $attempt -lt $maxAttempts) {
        # Kill theo tên
        Get-Process -Name $exeBaseName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Get-Process | Where-Object {
            try { $_.Path -like "$rawOut\*" } catch { $false }
        } | Stop-Process -Force -ErrorAction SilentlyContinue

        Start-Sleep -Seconds 2

        # Thử xóa thư mục
        if (Remove-ItemForce -TargetDir $rawOut) {
            $outputDeleted = $true
            Write-Log "   ✅ Đã dọn sạch output cũ: $rawOut" $C_Gray
        }

        if (-not $outputDeleted) {
            # Tìm và kill tiến trình đang giữ file trong thư mục (bắt buộc)
            Write-Log "   🔍 Đang quét tiến trình khóa file trong $rawOut..." $C_Gray
            $lockedProcs = Get-Process | Where-Object {
                try {
                    foreach ($mod in $_.Modules) {
                        if ($mod.FileName -like "$rawOut\*") { return $true }
                    }
                } catch {}
                return $false
            }
            if ($lockedProcs) {
                $lockedProcs | Where-Object { $_.Name -notin @('Idle','System','svchost','csrss','winlogon','services','lsass') } |
                    Stop-Process -Force -ErrorAction SilentlyContinue
                Write-Log "   🎯 Đã kill tiến trình khóa file." $C_Warn
            } else {
                Write-Log "   ℹ️ Không tìm thấy tiến trình khóa file. Có thể file bị hệ thống giữ." $C_Gray
            }
            $attempt++
            Write-Log "   🔁 Lần thử $attempt/$maxAttempts..." $C_Gray
            Start-Sleep -Seconds 1
        }
    }

    if (-not $outputDeleted) {
        Write-Log "❌ KHÔNG THỂ XÓA THƯ MỤC OUTPUT SAU $maxAttempts LẦN. Hãy đóng ứng dụng cũ và thử lại." $C_Err
        exit 1
    }

    New-Item -ItemType Directory -Force -Path $rawOut | Out-Null
    Write-Log "   ✅ Thư mục output đã sẵn sàng." $C_Gray

    $dotnetExe = $global:dotnetCmd
    if (-not $dotnetExe) {
        Write-Log "❌ KHÔNG TÌM THẤY SDK .NET!" $C_Err
        exit 1
    }

    # Lấy safe path cho output dir, project và dotnet
    $safeRawOut = Get-SafePath $rawOut
    $safeProject = Get-SafePath $Project

    Write-Log "🐞 Sử dụng dotnet: $dotnetExe" $C_Gray
    Write-Log "🐞 TFM: $Tfm | Output: $rawOut" $C_Gray
    Write-Log "🐞 Loại dự án: $ProjectType" $C_Gray

    # Xác định nền tảng trước để dùng cho kiểm tra
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

    # Xây dựng tham số publish cơ bản
    $params = @(
        "publish", $safeProject,
        "-f", $Tfm,
        "-c", "Release",
        "--output", $safeRawOut
    )

    # Thêm tham số đặc thù theo loại dự án và platform
    switch ($ProjectType) {
        'MAUI' {
            if ($isAndroidPlatform) {
                $params += @("-p:AndroidUseSharedRuntime=false", "-p:EmbedAssembliesIntoApk=true")
            }
        }
        'Web' {
            if (-not $isWindowsPlatform -and -not $isAndroidPlatform -and -not $isApplePlatform) {
                $params += @("-r", "win-x64", "--self-contained", "true")
                if ($BuildArgs -notcontains "-p:PublishSingleFile=false") {
                    $params += @("-p:PublishSingleFile=true", "-p:IncludeAllContentForSelfExtract=true")
                }
            }
        }
        { $_ -in @('WinForms', 'WPF', 'Console', 'WinExe') } {
            $params += @("--self-contained", "true")
            if (-not $isWindowsPlatform) {
                $params += @("-r", "win-x64")
            }
        }
        'BlazorWasm' {
            $params += @("-r", "browser-wasm")
        }
        'Library' {
            Write-Log "⚠️ Dự án dạng Library, chuyển sang build thay vì publish." $C_Warn
            # Xóa bỏ tham số publish, thay bằng build
            $params = @(
                "build", $safeProject,
                "-f", $Tfm,
                "-c", "Release"
            )
            # Không có --output, không tự mở thư mục
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

    $output = & $dotnetExe @params 2>&1 | ForEach-Object {
        $line = $_.ToString().TrimEnd()
        if ([string]::IsNullOrWhiteSpace($line)) { return $line }
        if ($line -match '^\s*Copying file from') { $copyCount++; return $line }
        if      ($line -match '(?i)\serror\s+(CS|MSB|NU|NETSDK|BC)\d+')   { $errCount++;  Write-Host "  ❌ $line" -ForegroundColor $C_Err }
        elseif  ($line -match '(?i)\swarning\s+(CS|MSB|NU|NETSDK|BC)\d+') { $warnCount++; Write-Host "  ⚠️  $line" -ForegroundColor $C_Warn }
        elseif  ($line -match '(Build succeeded|Build FAILED|->\s|Publish:|Done Building|Time Elapsed)') { Write-Host "  ✔  $line" -ForegroundColor $C_Succ }
        elseif  ($line -match '(CoreCompile|ResolveAssembly|GenerateBindingRedirects|CheckForDuplicate)') { <# skip #> }
        else    { Write-Host "    $line" -ForegroundColor $C_Gray }
        $line
    }
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
    if ($IsWindows -and $ProjectType -ne 'Library') {
        Start-Process explorer.exe -ArgumentList "`"$rawOut`""
    }

    # Auto Deploy cho Android APK
    if ($isAndroidPlatform -and $OutputSubDir -eq "apk") {
        $apkFile = Get-ChildItem $rawOut -Filter "*Signed*.apk" -Recurse | Select-Object -First 1
        if (-not $apkFile) { $apkFile = Get-ChildItem $rawOut -Filter "*.apk" -Recurse | Select-Object -First 1 }
        if ($apkFile) {
            $appIdMatch = [regex]::Match($csprojContent, '<ApplicationId>([^<]+)</ApplicationId>')
            $appId      = if ($appIdMatch.Success) { $appIdMatch.Groups[1].Value.Trim() } else { "com.companyname.app" }
            Write-Host "`n" -NoNewline
            Invoke-AutoDeploy -ApkPath $apkFile.FullName -AppId $appId -AndroidSdkPath $androidSdk
        } else {
            Write-Log "⚠️ Không tìm thấy APK để deploy." $C_Warn
            if ($IsWindows) { Start-Process explorer.exe -ArgumentList "`"$rawOut`"" }
        }
    }
}

function Invoke-GitHubBuild([string]$PackageFormat) {
    Write-Log "☁ Đang kết nối GitHub Cloud..." $C_Info
    $gh = if (Get-Command gh -EA SilentlyContinue) { "gh" } else { Get-SafePath "gh.exe" }
    if (-not (Test-Path $gh) -and $gh -ne "gh") { Write-Log "❌ Không tìm thấy gh.exe (GitHub CLI)!" $C_Err; return }
    
    $branch = git branch --show-current 2>$null
    if (-not $branch) { $branch = "main" }
    
    Write-Log "🚀 Đang gửi yêu cầu build $PackageFormat lên nhánh $branch..." $C_Succ
    & $gh workflow run build.yml --ref $branch -f "package_format=$PackageFormat"
    Write-Log "✅ Đã trigger thành công. Vui lòng kiểm tra web GitHub." $C_Info
}

# ==================================================================================================
# HÀM LẤY TARGET FRAMEWORK (TFM) CAO NHẤT
# ==================================================================================================
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

# ==================================================================================================
# [SECTION 4] MAIN FLOW
# ==================================================================================================

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
Draw-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Khởi tạo môi trường"
Write-SubLog "Kiểm tra .NET SDK"

$globalSdksList = $null
if ($global:dotnetCmd) {
    $globalSdksList = @(& $global:dotnetCmd --list-sdks 2>$null)
}
$currentTfm = Get-LatestInstalledTfm -SdksList $globalSdksList

# Cập nhật global.json một lần
if ($globalSdksList) {
    $latestSdk = ($globalSdksList[-1] -split ' ')[0]
    $gJsonPath = Join-Path $PSScriptRoot "global.json"
    $needsUpdate = $true
    if (Test-Path $gJsonPath) {
        try {
            $json = Get-Content $gJsonPath -Raw | ConvertFrom-Json
            if ($json.sdk -and $json.sdk.version -eq $latestSdk) { $needsUpdate = $false }
        } catch {}
    }
    if ($needsUpdate) {
        @{ sdk = @{ version = $latestSdk; rollForward = "latestMajor"; allowPrerelease = $true } } |
            ConvertTo-Json -Depth 3 | Out-File $gJsonPath -Encoding utf8 -Force
    }
}
$sw1.Stop()
Write-Done "SDK: $currentTfm  |  dotnet: $([System.IO.Path]::GetFileName($global:dotnetCmd))" $sw1.Elapsed.TotalSeconds

# ── BƯỚC 2: Quét project ─────────────────────────────────────────────────────────
$StepIndex++
$sw2 = [Diagnostics.Stopwatch]::StartNew()
Draw-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Quét project"
Write-SubLog "Tìm kiếm .csproj"

$csproj = Find-Project
if (-not $csproj) { Write-Fail "Không tìm thấy project!"; exit 1 }
$projPath    = $csproj.FullName
$projectType = Get-ProjectType -csprojPath $projPath
$tfms        = @(Get-CsprojTfms -projPath $projPath)
$androidTfm  = $tfms | Where-Object { $_ -match 'android'      } | Select-Object -First 1
$winTfm      = $tfms | Where-Object { $_ -match 'windows'      } | Select-Object -First 1
$iosTfm      = $tfms | Where-Object { $_ -match 'ios'          } | Select-Object -First 1
$macTfm      = $tfms | Where-Object { $_ -match 'maccatalyst'  } | Select-Object -First 1
$sw2.Stop()
Write-Done "Project: $($csproj.Name)  ($projectType)" $sw2.Elapsed.TotalSeconds

# ── BƯỚC 3: Menu chọn chế độ ─────────────────────────────────────────────────────
$StepIndex++
Draw-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Chọn chế độ (Input)"

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
            if ($iosTfm  -and $IsMacOS) { Write-Host "  [4]  Xuất bản iOS IPA"       -ForegroundColor "Magenta" }
            if ($macTfm  -and $IsMacOS) { Write-Host "  [5]  Xuất bản Mac Catalyst"  -ForegroundColor "Magenta" }
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
        Draw-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Debug: Android Device"
        Write-StepTitle "DEBUG TRỰC TIẾP TRÊN THIẾT BỊ ANDROID"
        if (!$androidTfm -or $projectType -ne 'MAUI') { Write-Fail "Không hỗ trợ!"; exit 1 }
        Invoke-DeviceDebug -Project $projPath -Tfm $androidTfm
    }
    '2' {
        Draw-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang Build: ANDROID APK"
        Write-StepTitle "XUẤT BẢN ANDROID APK" -Color $C_Info
        ProcessBuildAndShow -Project $projPath -Tfm $androidTfm -OutputSubDir "apk" -BuildArgs @("-p:AndroidPackageFormat=apk") -ProjectType $projectType
    }
    '3' {
        Draw-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang Build: ANDROID AAB"
        Write-StepTitle "XUẤT BẢN ANDROID AAB (GOOGLE PLAY)" -Color "Magenta"
        $ks    = Find-AndroidKeystore (Split-Path $projPath)
        $bArgs = @("-p:AndroidPackageFormat=aab")
        if ($ks) {
            $ks = Read-KeystoreInteractive -ks $ks
            if ($ks -and $ks.StorePass) {
                $safeKsPath = Get-SafePath $ks.Path
                $bArgs += "-p:AndroidSigningKeyStore=$safeKsPath"
                $bArgs += "-p:AndroidSigningStorePass=$($ks.StorePass)"
                $bArgs += "-p:AndroidSigningKeyAlias=$($ks.Alias)"
                $bArgs += "-p:AndroidSigningKeyPass=$($ks.KeyPass)"
            }
        }
        ProcessBuildAndShow -Project $projPath -Tfm $androidTfm -OutputSubDir "aab" -BuildArgs $bArgs -ProjectType $projectType
    }
    '4' {
        Draw-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang Build: iOS"
        Write-StepTitle "XUẤT BẢN iOS IPA" -Color "Magenta"
        ProcessBuildAndShow -Project $projPath -Tfm $iosTfm -OutputSubDir "ios" -BuildArgs @("-p:ArchiveOnBuild=true") -ProjectType $projectType
    }
    '5' {
        Draw-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang Build: Mac Catalyst"
        Write-StepTitle "XUẤT BẢN MAC CATALYST" -Color "Magenta"
        ProcessBuildAndShow -Project $projPath -Tfm $macTfm -OutputSubDir "mac" -ProjectType $projectType
    }
    '6' {
        Draw-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang Build: Windows MSIX"
        Write-StepTitle "XUẤT BẢN WINDOWS MSIX" -Color "DarkYellow"
        if ($projectType -eq 'MAUI') {
            $targetTfm = if ($winTfm) { $winTfm } else { "$currentTfm-windows" }
            ProcessBuildAndShow -Project $projPath -Tfm $targetTfm -OutputSubDir "win" -BuildArgs @("-p:WindowsPackageType=None","-p:PublishSingleFile=false","--self-contained","true") -ProjectType $projectType
        }
    }
    '7' {
        if ($projectType -eq 'Web') {
            Draw-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang Build: WEB"
            Write-StepTitle "XUẤT BẢN WEB UI" -Color $C_Info
            $swWeb = [Diagnostics.Stopwatch]::StartNew()
            ProcessBuildAndShow -Project $projPath -Tfm $currentTfm -OutputSubDir "web" -BuildArgs @("-p:PublishSingleFile=false") -ProjectType $projectType
            $webOutDir     = Join-Path $PSScriptRoot "publish-output\web"
            $exePath       = Join-Path $webOutDir ([System.IO.Path]::GetFileNameWithoutExtension($projPath) + ".exe")
            $dynamicPort   = Get-ProjectPort -ProjectDir (Split-Path $projPath)
            $url           = "http://localhost:$dynamicPort"
            if (Test-Path $exePath) {
                Write-SubLog "Khởi chạy ứng dụng ngầm tại $url"
                Start-Process -FilePath (Get-SafePath $exePath) -ArgumentList "--urls=$url" -WorkingDirectory (Get-SafePath $webOutDir) -WindowStyle Hidden -PassThru | Out-Null
                $maxWait = 15; $waited = 0; $portReady = $false
                while ($waited -lt $maxWait) {
                    Start-Sleep -Seconds 1; $waited++
                    if (Get-NetTCPConnection -LocalPort $dynamicPort -State Listen -EA SilentlyContinue) { $portReady = $true; break }
                }
                $swWeb.Stop()
                if ($portReady) {
                    Start-Process $url
                    Write-Done "App đang chạy tại $url" $swWeb.Elapsed.TotalSeconds
                } else {
                    Write-Warn "App phản hồi chậm — kiểm tra tại: $url"
                }
            }
        } elseif ($projectType -eq 'BlazorWasm') {
            Draw-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang Build: Blazor WASM"
            Write-StepTitle "XUẤT BẢN BLAZOR WASM" -Color $C_Info
            ProcessBuildAndShow -Project $projPath -Tfm $currentTfm -OutputSubDir "blazorwasm" -BuildArgs @("-r","browser-wasm") -ProjectType $projectType
        }
    }
    '8' {
        Draw-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang Build: DESKTOP APP"
        Write-StepTitle "XUẤT BẢN DESKTOP APP" -Color "DarkYellow"
        if ($projectType -in @('WinForms','WinExe')) {
            ProcessBuildAndShow -Project $projPath -Tfm $currentTfm -OutputSubDir "winforms" -BuildArgs @("-r","win-x64","--self-contained","true") -ProjectType $projectType
        } elseif ($projectType -eq 'MAUI' -and $winTfm) {
            $targetTfm = if ($winTfm) { $winTfm } else { "$currentTfm-windows" }
            ProcessBuildAndShow -Project $projPath -Tfm $targetTfm -OutputSubDir "win" -BuildArgs @("-p:WindowsPackageType=None","-p:PublishSingleFile=false","--self-contained","true") -ProjectType $projectType
        }
    }
    '9' {
        Draw-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang Build: WPF"
        Write-StepTitle "XUẤT BẢN WPF APP" -Color "DarkYellow"
        if ($projectType -eq 'WPF') {
            ProcessBuildAndShow -Project $projPath -Tfm $currentTfm -OutputSubDir "wpf" -BuildArgs @("-r","win-x64","--self-contained","true") -ProjectType $projectType
        }
    }
    '10' {
        Draw-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang Build: CONSOLE"
        Write-StepTitle "XUẤT BẢN CONSOLE APP" -Color "DarkYellow"
        if ($projectType -eq 'Console') {
            ProcessBuildAndShow -Project $projPath -Tfm $currentTfm -OutputSubDir "console" -BuildArgs @("-r","win-x64","--self-contained","true") -ProjectType $projectType
        }
    }
    '11' {
        Draw-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Build: LIBRARY"
        Write-StepTitle "BUILD LIBRARY" -Color "Gray"
        if ($projectType -eq 'Library') {
            ProcessBuildAndShow -Project $projPath -Tfm $currentTfm -OutputSubDir "lib" -ProjectType $projectType
        }
    }
    '12' {
        Draw-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Build: DEFAULT"
        Write-StepTitle "BUILD MẶC ĐỊNH" -Color "Gray"
        ProcessBuildAndShow -Project $projPath -Tfm $currentTfm -OutputSubDir "default" -ProjectType $projectType
    }
    '13' {
        Draw-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "GitHub Cloud Build"
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