#!/usr/bin/env pwsh
# =======================================================================
#  gbuild.ps1  — Build MAUI locally + trigger GitHub Actions
#  Drop vào bất kỳ project MAUI nào, chạy được ngay.
#
#  Dùng lệnh:
#    pwsh ./gbuild.ps1                          # menu tương tác
#    pwsh ./gbuild.ps1 -GitHub                  # kích hoạt GH Actions + download
#    pwsh ./gbuild.ps1 -GitHub -Format aab      # GH Actions, chọn AAB
#    pwsh ./gbuild.ps1 -GitHub -NonInteractive  # dùng trong pipe/CI
# =======================================================================

# --- ĐỊNH NGHĨA THAM SỐ LỆNH VÀ CÁC BIẾN HỆ ĐIỀU HÀNH ---
# Luôn đặt param() ở đầu script, sau shebang.
param(
    [switch]$GitHub,          # Kích hoạt workflow GitHub Actions và tải artifact
    [ValidateSet('apk','aab')][string]$Format, # Định dạng package cho GH Actions (apk hoặc aab)
    [switch]$NonInteractive   # Chạy ở chế độ không tương tác (dùng trong pipe/CI)
)
# --- KẾT THÚC ĐỊNH NGHĨA THAM SỐ VÀ BIẾN OS ---

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop' # Dừng script khi có lỗi

# =======================================================================
# I. HÀM BỔ TRỢ (HELPERS)
# =======================================================================

# 1) Resolve dotnet exe (không bắt buộc có thư mục .sdk)
function Resolve-DotnetExe {
    # Ưu tiên dotnet có sẵn trên PATH
    $cmd = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($cmd) { return "dotnet" }

    # Fallback: thư mục .sdk trong script (nếu có)
    $localDotnet = Join-Path $PSScriptRoot ".sdk\dotnet.exe"
    if (Test-Path $localDotnet) { return $localDotnet }

    return $null # Trả về null nếu không tìm thấy
}

# 2) Get-CsprojTfms: xử lý đa PropertyGroup và trả về mảng TFMs
function Get-CsprojTfms {
    param([string]$ProjPath)
    [xml]$xml = Get-Content -LiteralPath $ProjPath

    # Lấy tất cả các PropertyGroup có TargetFramework hoặc TargetFrameworks
    $tfmList = @()
    $propertyGroups = $xml.SelectNodes("//Project/PropertyGroup[TargetFramework or TargetFrameworks]")

    foreach ($pg in $propertyGroups) {
        if ($pg.TargetFramework) { $tfmList += $pg.TargetFramework }
        if ($pg.TargetFrameworks) { $tfmList += $pg.TargetFrameworks }
    }

    if (-not $tfmList -or $tfmList.Count -eq 0) { return @() }

    # Gom lại các TFM và tách bằng dấu ;
    $joinedTFMs = ($tfmList -join ';').Trim()
    if ([string]::IsNullOrWhiteSpace($joinedTFMs)) { return @() }

    # Tách và làm sạch từng TFM
    $tfms = $joinedTFMs.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() }

    # Đảm bảo trả về một mảng, ngay cả khi chỉ có 1 TFM
    if ($tfms -is [string]) { return @($tfms) } else { return $tfms }
}

# 3) Show-OutputFiles: Hiển thị file output và mở trình duyệt nếu có
function Show-OutputFiles([string]$dir, [string[]]$extensions) {
    $files = Get-ChildItem $dir -File | Where-Object { $_.Extension.ToLower() -in $extensions.ToLower() }
    if (-not $files) {
        Write-Warning "⚠️ Không tìm thấy file output với extension '$($extensions -join ', ')' trong $dir"
        return
    }
    Write-Host "`n📂 Output Dir: $dir" -ForegroundColor Cyan
    foreach ($f in $files) {
        $label = if ($f.Name -match 'Signed|Release' -or $f.Name -match '\.pfx$') { '🔏 SIGNED' } else { '📦 unsigned' }
        Write-Host "  $label  $($f.Name)  [$([math]::Round($f.Length/1MB,2)) MB]" -ForegroundColor Green
    }
    
    # Mở thư mục bằng trình quản lý file mặc định
    if ($IsWindows -and $files) {
        $folderPath = (Resolve-Path $dir).ProviderPath
        Start-Process explorer.exe -ArgumentList $folderPath
    } elseif ($IsMacOS -and $files) {
        $folderPath = (Resolve-Path $dir).ProviderPath
        open $folderPath
    } elseif ($IsLinux -and $files) {
        $folderPath = (Resolve-Path $dir).ProviderPath
        xdg-open $folderPath 2>&1 | Out-Null # Chạy xdg-open, bỏ qua output
    }
}

# 4) Tìm project MAUI tương ứng
function Get-MauiCsproj {
    Write-Host "🔎 Đang tìm project MAUI..." -ForegroundColor DarkGray
    $allCsproj = Get-ChildItem . -Recurse -Filter *.csproj -File |
        Where-Object { $_.FullName -notmatch '[\\/](obj|bin|packages|node_modules)[\\/]' -and $_.Name -notmatch '\.Tests\.' } |
        Sort-Object FullName # Sắp xếp theo đường dẫn để có kết quả nhất quán

    # Ưu tiên project có <UseMaui>true</UseMaui>
    foreach ($c in $allCsproj) {
        $content = Get-Content $c.FullName -Raw -EA SilentlyContinue
        if ($content -match '<UseMaui>\s*true\s*</UseMaui>') {
            Write-Host "✅ Tìm thấy project MAUI (`UseMaui`): $($c.Name)" -ForegroundColor Green
            return $c
        }
    }
    # Nếu không có UseMaui, tìm project có TargetFramework cho MAUI (android, ios, windows, maccatalyst)
    foreach ($c in $allCsproj) {
        $tfms = Get-CsprojTfms $c.FullName
        if ($tfms | Where-Object { $_ -match '^net\d+(\.\d+)?-(android|ios|maccatalyst|windows)' }) {
            Write-Host "✅ Tìm thấy project MAUI (TFM): $($c.Name)" -ForegroundColor Green
            return $c
        }
    }
    
    # Nếu không tìm thấy project MAUI đặc trưng, lấy project đầu tiên
    if ($allCsproj.Count -gt 0) {
        Write-Host "⚠️ Không tìm thấy project MAUI rõ ràng; chọn project đầu tiên: $($allCsproj[0].Name)" -ForegroundColor Yellow
        return $allCsproj[0]
    }
    
    return $null # Không tìm thấy project nào
}

# 5) Phát hiện Keystore Android (cho signing)
function Find-AndroidKeystore([string]$projectDir) {
    Write-Host "🔎 Đang tìm Android Keystore..." -ForegroundColor DarkGray
    # Ưu tiên signing.properties cạnh .csproj
    $propsFile = Join-Path $projectDir 'signing.properties'
    if (Test-Path $propsFile) {
        $props = @{}
        Get-Content $propsFile | ForEach-Object {
            if ($_ -match '^\s*([^#=]+?)\s*=\s*(.+)$') { $props[$matches[1].Trim()] = $matches[2].Trim() }
        }
        $ksPath = $props['storeFile']
        if ($ksPath -and -not ([System.IO.Path]::IsPathRooted($ksPath))) { # Nếu path tương đối, tạo path tuyệt đối
            $ksPath = Join-Path $projectDir $ksPath
        }
        if ($ksPath -and (Test-Path $ksPath)) {
            Write-Host "✅ Phát hiện signing.properties, Keystore: $($props.storeFile)" -ForegroundColor Green
            return @{ KeystorePath = $ksPath; StorePass = $props['storePassword']; KeyAlias = $props['keyAlias']; KeyPass = $props['keyPassword']; Source = 'signing.properties' }
        }
    }

    # Tìm .keystore / .jks trong thư mục root của project (ngoài bin/obj)
    $ksFile = Get-ChildItem $projectDir -Recurse -File |
        Where-Object { $_.Extension -in '.keystore','.jks' -and $_.FullName -notmatch '[\\/](obj|bin)[\\/]' } |
        Select-Object -First 1
    if ($ksFile) {
        Write-Host "✅ Phát hiện file Keystore: $($ksFile.Name)" -ForegroundColor Green
        return @{ KeystorePath = $ksFile.FullName; StorePass = $null; KeyAlias = $null; KeyPass = $null; Source = $ksFile.Name }
    }
    
    Write-Host "⚠️ Không tìm thấy Android Keystore." -ForegroundColor Yellow
    return $null
}

# Hàm tương tác để nhập thông tin signing keystore
function Read-SigningInfo([hashtable]$ks) {
    Write-Host "`n🔑 Keystore: $($ks.KeystorePath)" -ForegroundColor Cyan
    Write-Host "   Nguồn   : $($ks.Source)" -ForegroundColor DarkGray

    # Chỉ hỏi nếu thông tin chưa có
    if (-not $ks.StorePass) {
        $sp = Read-Host "🔑 Store password (Nhấn Enter để bỏ qua ký)"
        if ([string]::IsNullOrWhiteSpace($sp)) { return $null } # Trả về null nếu người dùng bỏ qua
        $ks.StorePass = $sp
    }
    if (-not $ks.KeyAlias) {
        $ka = Read-Host "🔑 Key alias (mặc định: key0)"
        $ks.KeyAlias = if ([string]::IsNullOrWhiteSpace($ka)) { 'key0' } else { $ka }
    }
    if (-not $ks.KeyPass) {
        $kp = Read-Host "🔑 Key password (Nhấn Enter = giống store password)"
        $ks.KeyPass = if ([string]::IsNullOrWhiteSpace($kp)) { $ks.StorePass } else { $kp }
    }
    return $ks # Trả về hashtable với đầy đủ thông tin
}

# =======================================================================
# GITHUB ACTIONS — Kích hoạt workflow, theo dõi, và download artifact
# =======================================================================
function Invoke-GitHubBuild([string]$PackageFormat) {
    # Lấy path của gh CLI (nếu có)
    $gh = $null
    if ($IsWindows) {
        $ghExe = Join-Path $PSScriptRoot 'gh.exe'
        $gh    = if (Test-Path $ghExe) { $ghExe } elseif (Get-Command gh -ErrorAction SilentlyContinue) { 'gh' } else { $null }
    } else { # macOS/Linux
        $gh    = if (Get-Command gh -ErrorAction SilentlyContinue) { 'gh' } else { $null }
    }

    if (-not $gh) {
        Write-Host "❌ GitHub CLI (gh) chưa cài đặt hoặc không có trong PATH/thư mục script." -ForegroundColor Red
        Write-Host "   Tải về và cài đặt tại: https://cli.github.com/" -ForegroundColor Yellow
        exit 1
    }

    # Kiểm tra trạng thái đăng nhập của gh CLI
    Write-Host "🔎 Đang kiểm tra trạng thái đăng nhập GitHub CLI..." -ForegroundColor DarkGray
    & $gh auth status *> $null # Chạy gh auth status, bỏ output
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Chưa đăng nhập vào GitHub CLI." -ForegroundColor Red
        Write-Host "   Hãy chạy: gh auth login --scopes workflow" -ForegroundColor Yellow
        exit 1
    }

    # Lấy nhánh hiện tại
    $currentBranch = if (Get-Command git -ErrorAction SilentlyContinue) { git branch --show-current 2>$null } else { $null }
    if (-not $currentBranch) {
        Write-Host "⚠️ Git chưa cài hoặc không tìm thấy repo; dùng nhánh 'main' làm mặc định." -ForegroundColor Yellow
        $currentBranch = 'main'
    }

    # Lấy danh sách các workflow active
    Write-Host "🔎 Đang lấy danh sách các workflow..." -ForegroundColor DarkGray
    $activeWorkflows = @(); try { $activeWorkflows = & $gh workflow list --limit 100 --state active --json id,name,state | ConvertFrom-Json } catch { };
    if (-not $activeWorkflows -or $activeWorkflows.Count -eq 0) {
        Write-Host "❌ Không tìm thấy workflow nào đang active trong repository này." -ForegroundColor Red; exit 1
    }

    # Ưu tiên workflow có tên liên quan đến MAUI/Android Build
    $priorityWF = $activeWorkflows | Where-Object { $_.name -match 'Maui|Build|Android|CI' }
    $selectedWF = $null
    if ($priorityWF.Count -eq 1) {
        $selectedWF = $priorityWF[0]
        Write-Host "✅ Workflow ưu tiên: $($selectedWF.name)" -ForegroundColor Green
    } else {
        Write-Host "`n📋 Danh sách các workflow có sẵn:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $activeWorkflows.Count; $i++) {
            Write-Host "  [$i] $($activeWorkflows[$i].name)"
        }
        $choice = Read-Host "`n👉 Chọn số thứ tự workflow (Enter = 0, tức là workflow đầu tiên)"
        if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '0' }
        if ($choice -notmatch '^\d+$' -or [int]$choice -lt 0 -or [int]$choice -ge $activeWorkflows.Count) {
            Write-Host "❌ Lựa chọn không hợp lệ." -ForegroundColor Red; exit 1
        }
        $selectedWF = $activeWorkflows[[int]$choice]
    }

    # Kích hoạt workflow
    $triggerArgs = @('workflow', 'run', $selectedWF.id, '--ref', $currentBranch)
     # Chỉ thêm parameter package_format nếu nó có giá trị
    if (-not [string]::IsNullOrWhiteSpace($PackageFormat)) {
        $triggerArgs += '-f', "package_format=$PackageFormat"
    }

    Write-Host "🚀 Đang kích hoạt workflow '$($selectedWF.name)' trên nhánh '$currentBranch' với format '$PackageFormat'..." -ForegroundColor Cyan
    & $gh $triggerArgs 2>$null # Chạy gh workflow run, bỏ qua output
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to trigger workflow '$($selectedWF.name)'." -ForegroundColor Red; exit 1
    }
    Write-Host "✅ Workflow đã được kích hoạt thành công." -ForegroundColor Green
    
    # Cố gắng tải artifact từ commit gần nhất
    # Lấy run ID cuối cùng để tải về artifact cho đúng
    $lastRun = $null; $RUN_LIST_RETRY = 5
    for ($r = 0; $r -lt $RUN_LIST_RETRY; $r++) {
        $lastRun = (& $gh run list --workflow $selectedWF.id --limit 1 --json databaseId,runNumber,title | ConvertFrom-Json)
        if ($lastRun) { break }
        Start-Sleep -Seconds 2
    }
    if (-not $lastRun) { Write-Host "⚠️ Không lấy được thông tin run gần nhất." -ForegroundColor Yellow }
    
    $outDir = 'github-artifacts'
    if (Test-Path $outDir) { Remove-Item "$outDir\*" -Recurse -Force -EA SilentlyContinue }
    else { New-Item -ItemType Directory $outDir | Out-Null }

    Write-Host "`n📦 Đang tải artifact về thư mục '$outDir'..." -ForegroundColor Cyan
    if ($lastRun) {
        & $gh run download $lastRun.databaseId --dir $outDir 
        if ($LASTEXITCODE -ne 0) { Write-Host "⚠️ Lỗi khi tải artifact cho run ID $($lastRun.databaseId)." -ForegroundColor Yellow }
    } else {
        & $gh run download --dir $outDir # Fallback
        if ($LASTEXITCODE -ne 0) { Write-Host "⚠️ Lỗi khi tải artifact, có thể không có artifact nào được tạo." -ForegroundColor Yellow }
    }

    # Flatten artifact: đưa tất cả file apk/aab từ các thư mục con lên thư mục chính
    $flattenedCount = 0
    Get-ChildItem $outDir -Recurse -File -Include *.apk,*.aab | ForEach-Object {
        Move-Item -Path $_.FullName -Destination $outDir -Force -EA SilentlyContinue
        $flattenedCount++
    }
    # Xóa các thư mục con rỗng sau khi flatten
    Get-ChildItem $outDir -Directory | Remove-Item -Recurse -Force -EA SilentlyContinue

    if ($flattenedCount -gt 0) {
        Write-Host "Artifact đã được tải và làm phẳng." -ForegroundColor Green
    } else {
        Write-Host "Artifact không tìm thấy hoặc không có file APK/AAB nào." -ForegroundColor Yellow
    }

    # Thông báo về kết quả cuối cùng
    Write-Host "`n📂 Kết quả tải về ($outDir) có thể chứa các file sau:" -ForegroundColor Cyan
    $artifactsExist = Get-ChildItem $outDir -File | Where-Object { $_.Extension.ToLower() -in '.apk','.aab' }
    if ($artifactsExist) {
        $artifactsExist | ForEach-Object {
            $label = if ($_.Name -match 'Signed|Release') { '🔏 SIGNED' } else { '📦 unsigned' }
            Write-Host "  $label  $($_.Name)  [$([math]::Round($_.Length/1MB,2)) MB]" -ForegroundColor Green
        }
        Show-OutputFiles $outDir @('.apk','.aab') # Mở thư mục nếu có file
    } else {
        Write-Host "  Không tìm thấy artifact APK/AAB." -ForegroundColor Yellow
    }
}

# =======================================================================
# MAIN FLOW: XỬ LÝ BUỔI LÔC VÀ MENU LỰA CHỌN
# =======================================================================

# 1) Tìm project .csproj và thư mục gốc
$csproj = Get-MauiCsproj
if (-not $csproj) {
    Write-Host "❌ Không tìm thấy file .csproj nào trong thư mục hiện tại hoặc thư mục con." -ForegroundColor Red
    exit 1
}
$projectDir = Split-Path $csproj.FullName
Write-Host "📄 Sử dụng project: $($csproj.Name)" -ForegroundColor Cyan

# 2) Đọc Target Frameworks từ .csproj
$tfmsFromCsprojRaw = Get-CsprojTfms -ProjPath $csproj.FullName
$tfms = @() # Mảng chứa tất cả các TFMs đã được xử lý
if ($tfmsFromCsprojRaw) {
    foreach ($t in @($tfmsFromCsprojRaw)) { # Đảm bảo $t là mảng ngay cả khi Get-CsprojTfms trả về 1 string
        if (-not [string]::IsNullOrWhiteSpace($t)) { $tfms += $t.Trim() }
    }
}
$tfms = $tfms | Sort-Object -Unique # Loại bỏ các TFM trùng lặp

# Fallback cho TFM 'net10.0' nếu nó tồn tại
# Logic này map 'net10.0-*' sang TFM hợp lệ hiện có (ví dụ: net8.0-*)
$processedTFMs = @()
$hasNet10TFMs = $false
foreach ($t in $tfms) {
    if ($t -like 'net10.0*') {
        $hasNet10TFMs = $true
        $osPart = $t -replace '^net10\.0-','' # Lấy phần sau net10.0-
        # Tìm TFM hợp lệ có cùng OS part
        $fallbackTfm = $tfms | Where-Object { $_ -match "^net\d+(\.\d+)?-$osPart$" } | Sort-Object { [version]($_.Split('-')[0].Replace('net','')) } -Descending | Select-Object -First 1
        
        if ($fallbackTfm) {
            Write-Host "⚠️ Phát hiện TFM 'net10.0-$osPart'. Sử dụng fallback '$fallbackTfm'." -ForegroundColor Yellow
            $processedTFMs += $fallbackTfm
        } else {
            # Nếu không tìm thấy fallback cụ thể, dùng net8.0-android làm mặc định
            Write-Host "⚠️ Phát hiện TFM 'net10.0-$osPart' nhưng không tìm thấy TFM fallback hợp lệ. Mặc định dùng 'net8.0-android'." -ForegroundColor Yellow
            $processedTFMs += 'net8.0-android'
        }
    } else {
        $processedTFMs += $t # Giữ nguyên TFM nếu không phải net10.0
    }
}
# Cập nhật lại $tfms sau khi có fallback và loại bỏ trùng lặp
$tfms = $processedTFMs | Sort-Object -Unique

if ($hasNet10TFMs -and $tfms.Count -eq 0) {
     Write-Host "❌ Lỗi: Sau khi xử lý fallback cho net10.0, không còn TFM hợp lệ nào." -ForegroundColor Red
     exit 1
}

# Phân loại các TFMs đã xử lý theo nền tảng
$androidTfmCandidates = $tfms | Where-Object { $_ -match '^net\d+(\.\d+)?-android$' }
$iosTfmCandidates     = $tfms | Where-Object { $_ -match '^net\d+(\.\d+)?-ios$' }
$macTfmCandidates     = $tfms | Where-Object { $_ -match '^net\d+(\.\d+)?-maccatalyst$' }
$winTfmCandidates     = $tfms | Where-Object { $_ -match '^net\d+(\.\d+)?-windows(\d+\.\d+\.\d+)?$' }

# Chọn TFM mặc định cho từng nền tảng (ưu tiên bản mới nhất nếu có nhiều)
$androidTfm = $androidTfmCandidates | Sort-Object { [version]($_.Split('-')[0].Replace('net','')) } -Descending | Select-Object -First 1
$iosTfm     = $iosTfmCandidates     | Sort-Object { [version]($_.Split('-')[0].Replace('net','')) } -Descending | Select-Object -First 1
$macTfm     = $macTfmCandidates     | Sort-Object { [version]($_.Split('-')[0].Replace('net','')) } -Descending | Select-Object -First 1
$winTfm     = $winTfmCandidates     | Sort-Object { [version]($_.Split('-')[0].Replace('net','')) } -Descending | Select-Object -First 1

# Thông báo về các TFM đã tìm được
Write-Host "`nProject TFMs found: $($tfms -join ', ')" -ForegroundColor DarkGray
if ($androidTfm) { Write-Host "  > Android TFM selected: $androidTfm" } else { Write-Host "  > Android TFM not found." -ForegroundColor Yellow }
if ($iosTfm)     { Write-Host "  > iOS TFM selected: $iosTfm" } else { Write-Host "  > iOS TFM not found." -ForegroundColor Yellow }
if ($macTfm)     { Write-Host "  > Mac Catalyst TFM selected: $macTfm" } else { Write-Host "  > Mac Catalyst TFM not found." -ForegroundColor Yellow }
if ($winTfm)     { Write-Host "  > Windows TFM selected: $winTfm" } else { Write-Host "  > Windows TFM not found." -ForegroundColor Yellow }

$publishDir = Join-Path $PSScriptRoot 'publish-output' # Thư mục output chung

# --- Lựa chọn Flow: Menu hay GitHub Actions ---
$selectedOption = $null
if ($GitHub -or $NonInteractive) {
    # --- Flow GitHub Actions ---
    $selectedOption = '6' # Chế độ CI GitHub Actions
    $packageFormatForCI = $Format
    if (-not $packageFormatForCI) { $packageFormatForCI = 'apk' } # Mặc định là apk nếu không chỉ định
    if ($NonInteractive -and -not $PSBoundParameters.ContainsKey('Format')) { Write-Host "⚠️ NonInteractive mode: defaulting GitHub Actions to format 'apk'." -ForegroundColor Yellow }
} else {
    # --- Flow Menu Tương Tác ---
    Write-Host "`n"
    Write-Host "╔═══════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host " 🔨  MAUI BUILD TOOL — VIP PRO           " -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════╝`n" -ForegroundColor Cyan

    Write-Host "  [0] Thoát chương trình"
    Write-Host "  [1] Android — APK  (local build)"
    Write-Host "  [2] Android — AAB  (local build)"
    if ($IsMacOS) {
        if ($iosTfm) { Write-Host "  [3] iOS            (local build on macOS)" } else { Write-Host "  [3] iOS            (local build on macOS) - Bỏ qua (Không tìm thấy TFM)", -ForegroundColor Gray }
        if ($macTfm) { Write-Host "  [4] Mac Catalyst   (local build on macOS)" } else { Write-Host "  [4] Mac Catalyst   (local build on macOS) - Bỏ qua (Không tìm thấy TFM)", -ForegroundColor Gray }
    }
    if ($IsWindows) {
        if ($winTfm) { Write-Host "  [5] Windows MSIX   (local build on Windows)" } else { Write-Host "  [5] Windows MSIX   (local build on Windows) - Bỏ qua (Không tìm thấy TFM)", -ForegroundColor Gray }
    }
    Write-Host "  [6] ☁  GitHub Actions — Trigger + Download"

    # Lấy lựa chọn từ người dùng
    $choice = Read-Host "`n👉 Chọn tùy chọn (Enter = 0)"
    $selectedOption = if ([string]::IsNullOrWhiteSpace($choice)) { '0' } else { $choice }
}

# --- Xử lý lựa chọn ---
switch ($selectedOption) {
    '0' { Write-Host 'Đã thoát.' -ForegroundColor Gray; exit 0 }
    
    '1' { # Android APK (local)
        if (-not $androidTfm) { Write-Host "❌ Lỗi: Không thể build Android APK do không tìm thấy TFM Android hợp lệ." -ForegroundColor Red; exit 1 }
        ProcessBuildAndShow -Project $csproj.FullName -Tfm $androidTfm -OutputSubDir 'android-apk' -BuildArgs @("-p:AndroidPackageFormat=apk")
        Show-OutputFiles (Join-Path $publishDir 'android-apk') @('.apk')
        Write-Host "`n✅ Build Android APK hoàn tất." -ForegroundColor Green
    }
    '2' { # Android AAB (local)
        if (-not $androidTfm) { Write-Host "❌ Lỗi: Không thể build Android AAB do không tìm thấy TFM Android hợp lệ." -ForegroundColor Red; exit 1 }
        $buildArgs = @("-p:AndroidPackageFormat=aab")
        
        # Xử lý signing cho AAB
        $ksInfo = Find-AndroidKeystore $projectDir
        if ($ksInfo) {
            if ($NonInteractive) {
                Write-Host "⚠️ NonInteractive: Không thể hỏi password Keystore. Build có thể thất bại nếu cần ký." -ForegroundColor Yellow
                Write-Host "   Ensure 'signing.properties' is set up or use CI variables." -ForegroundColor Yellow
            } else {
                $ksInfo = Read-SigningInfo $ksInfo
            }
        }
        if ($ksInfo -and $ksInfo.StorePass) {
            Write-Host "🔏 Ký package với Keystore..." -ForegroundColor Green
            $buildArgs += @(
                "-p:AndroidSigningKeyStore=$($ksInfo.KeystorePath)",
                "-p:AndroidSigningStorePass=$($ksInfo.StorePass)",
                "-p:AndroidSigningKeyAlias=$($ksInfo.KeyAlias)",
                "-p:AndroidSigningKeyPass=$($ksInfo.KeyPass)"
            )
        } else {
            Write-Host "⚠️ Không có thông tin Keystore hoặc người dùng bỏ qua → build unsigned." -ForegroundColor Yellow
        }
        
        ProcessBuildAndShow -Project $csproj.FullName -Tfm $androidTfm -OutputSubDir 'android-aab' -BuildArgs $buildArgs
        Show-OutputFiles (Join-Path $publishDir 'android-aab') @('.aab')
        Write-Host "`n✅ Build Android AAB hoàn tất." -ForegroundColor Green
    }
    '3' { # iOS (macOS)
        if (-not $IsMacOS) { Write-Host "❌ Lỗi: Build iOS cần chạy trên macOS." -ForegroundColor Red; exit 1 }
        if (-not $iosTfm) { Write-Host "❌ Lỗi: Không tìm thấy TFM iOS hợp lệ trong .csproj." -ForegroundColor Red; exit 1 }
        # Build for release and create an archive for distribution
        $buildArgs = @("-p:ArchiveOnBuild=true", "-p:RuntimeIdentifier=ios-arm64") 
        ProcessBuildAndShow -Project $csproj.FullName -Tfm $iosTfm -OutputSubDir 'ios-ipa' -BuildArgs $buildArgs
        Show-OutputFiles (Join-Path $publishDir 'ios-ipa') @('.ipa', '.app')
        Write-Host "`n✅ Build iOS IPA hoàn tất." -ForegroundColor Green
    }
    '4' { # Mac Catalyst (macOS)
        if (-not $IsMacOS) { Write-Host "❌ Lỗi: Build Mac Catalyst cần chạy trên macOS." -ForegroundColor Red; exit 1 }
        if (-not $macTfm) { Write-Host "❌ Lỗi: Không tìm thấy TFM Mac Catalyst hợp lệ trong .csproj." -ForegroundColor Red; exit 1 }
        $buildArgs = @("-p:RuntimeIdentifier=maccatalyst-x64") # Hoặc maccatalyst-arm64
        ProcessBuildAndShow -Project $csproj.FullName -Tfm $macTfm -OutputSubDir 'maccatalyst-bundle' -BuildArgs $buildArgs
        Show-OutputFiles (Join-Path $publishDir 'maccatalyst-bundle') @('.pkg', '.dmg', '.app')
        Write-Host "`n✅ Build Mac Catalyst Bundle hoàn tất." -ForegroundColor Green
    }
    '5' { # Windows MSIX (local)
        if (-not $IsWindows) { Write-Host "❌ Lỗi: Build Windows MSIX chỉ có thể chạy trên Windows." -ForegroundColor Red; exit 1 }
        if (-not $winTfm) { Write-Host "❌ Lỗi: Không tìm thấy TFM Windows hợp lệ trong .csproj." -ForegroundColor Red; exit 1 }
        $buildArgs = @("-p:WindowsPackageType=MSIX", "-p:GenerateAppxPackageOnBuild=true")

        # Tự động phát hiện PFX cert cho Windows, sau đó hỏi pass nếu cần
        $pfxFile = Get-ChildItem $projectDir -Recurse -File -Filter *.pfx |
            Where-Object { $_.FullName -notmatch '[\\/](obj|bin)[\\/]' } |
            Select-Object -First 1
        $signed = $false
        if ($pfxFile) {
            if ($NonInteractive) {
                Write-Host "⚠️ NonInteractive: Không thể hỏi pass PFX. Build có thể thất bại nếu cần ký." -ForegroundColor Yellow
            } else {
                $pfxPass = Read-Host "🔑 PFX password ($($pfxFile.Name) - Enter để bỏ qua ký)"
                if (-not [string]::IsNullOrWhiteSpace($pfxPass)) {
                    Write-Host "🔏 Build với PFX cert → SIGNED MSIX" -ForegroundColor Green
                    $buildArgs += @("-p:PackageCertificateKeyFile=$($pfxFile.FullName)", "-p:PackageCertificatePassword=$pfxPass")
                    $signed = $true
                }
            }
        }
        if (-not $signed) {
            Write-Host "⚠️ Không có PFX cert hoặc người dùng bỏ qua → build unsigned MSIX." -ForegroundColor Yellow
        }
        
        ProcessBuildAndShow -Project $csproj.FullName -Tfm $winTfm -OutputSubDir 'windows-msix' -BuildArgs $buildArgs
        Show-OutputFiles (Join-Path $publishDir 'windows-msix') @('.msix', '.msixbundle', '.appx')
        Write-Host "`n✅ Build Windows MSIX hoàn tất." -ForegroundColor Green
    }
    '6' { # GitHub Actions
        Write-Host "`n╔═══════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host " ☁  GITHUB ACTIONS BUILD                 " -ForegroundColor Cyan
        Write-Host "╚═══════════════════════════════════════╝`n" -ForegroundColor Cyan

        $packageFormatForCI = $Format
        if (-not $GitHub -and -not $NonInteractive -and -not $PSBoundParameters.ContainsKey('Format')) {
            Write-Host "  [1] APK  [2] AAB" -ForegroundColor Cyan
            $p = Read-Host "👉 Chọn định dạng cho GitHub Actions (Enter = APK)"
            $packageFormatForCI = if ($p -eq '2') { 'aab' } else { 'apk' }
        } elseif (-not $packageFormatForCI) {
            $packageFormatForCI = 'apk' # Mặc định nếu NonInteractive hoặc chỉ định ở CLI
            if ($NonInteractive) { Write-Host "⚠️ NonInteractive mode: sử dụng format '$packageFormatForCI' mặc định cho GitHub Actions." -ForegroundColor Yellow }
        }
        Invoke-GitHubBuild -PackageFormat $packageFormatForCI
        Write-Host "`n🎉 Quá trình GitHub Actions hoàn tất." -ForegroundColor Green
        # Thoát script sau khi hoàn tất GH Actions
        exit 0
    }
    default {
        Write-Host "❌ Lựa chọn không hợp lệ: '$selectedOption'. Vui lòng chọn từ [0-6]." -ForegroundColor Red
        exit 1
    }
}

# --- HÀM PHỤ GIÚP CHO VIỆC BUILD VÀ HIỂN THỊ OUTPUT ---
function ProcessBuildAndShow {
    param(
        [string]$Project,
        [string]$Tfm,
        [string]$OutputSubDir,
        [string[]]$BuildArgs
    )
    
    $publishDir = Join-Path $PSScriptRoot 'publish-output'
    $fullOutputFolder = Join-Path $publishDir $OutputSubDir

    # Loại bỏ thư mục output cũ nếu có
    if (Test-Path $fullOutputFolder) {
        Write-Host "🧹 Xóa thư mục output cũ: $fullOutputFolder" -ForegroundColor DarkGray
        Remove-Item $fullOutputFolder -Recurse -Force -EA SilentlyContinue
    }
    New-Item -ItemType Directory $fullOutputFolder | Out-Null # Tạo lại thư mục output

    # Lấy dotnet executable
    $dotnetExe = Resolve-DotnetExe
    if (-not $dotnetExe) {
        Write-Host "❌ Lỗi: Không tìm thấy dotnet.exe. Vui lòng cài đặt .NET SDK hoặc thêm vào PATH/thư mục .sdk." -ForegroundColor Red
        exit 1
    }

    # Chuẩn bị các tham số cho lệnh dotnet publish
    $dotnetArgs = @(
        'publish', $Project,
        '-f', $Tfm,
        '-c', 'Release', # Build ở mode Release
        "--output", $fullOutputFolder,
        '-p:UseMaui=true',
        '-p:SingleProject=true' 
    )
    
    # Thêm các tùy chọn build cụ thể (từ $BuildArgs)
    $dotnetArgs += $BuildArgs

    # Thêm các biến môi trường cho signing nếu cần (ví dụ: cho CI/CD)
    # # Example for Android signing in CI with env variables:
    # if ($env:MY_ANDROID_KEYSTORE) {
    #     $dotnetArgs += "-p:AndroidSigningKeyStore=$env:MY_ANDROID_KEYSTORE"
    #     $dotnetArgs += "-p:AndroidSigningStorePass=$env:MY_ANDROID_STORE_PASS"
    #     $dotnetArgs += "-p:AndroidSigningKeyAlias=$env:MY_ANDROID_KEY_ALIAS"
    #     $dotnetArgs += "-p:AndroidSigningKeyPass=$env:MY_ANDROID_KEY_PASS"
    # }
    
    # Thực thi lệnh build
    Write-Host "`n🚀 Bắt đầu build..." -ForegroundColor Cyan
    Write-Host "   Lệnh: $dotnetExe $($dotnetArgs -join ' ')" -ForegroundColor DarkGray
    
    # Chạy lệnh dotnet publish
    # Sử dụng Start-Process để có thể bắt output tốt hơn, hoặc pwsh -Command
    try {
        $process = Start-Process -FilePath $dotnetExe -ArgumentList $dotnetArgs -Wait -NoNewWindow -PassThru
        if ($process.ExitCode -ne 0) {
            Write-Host "❌ Lỗi trong quá trình build .NET. Exit code: $($process.ExitCode)" -ForegroundColor Red
            exit 1
        }
        Write-Host "Build thành công." -ForegroundColor Green
    } catch {
        Write-Host "❌ Lỗi khi thực thi lệnh build: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# --- THÔNG BÁO KẾT THÚC SCRIPT ---
Write-Host "`nScript gbuild.ps1 hoàn tất." -ForegroundColor Green