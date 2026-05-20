# ==================================================================================
# Modules/SDK.psm1
# ==================================================================================
$BinExt    = if ($global:OS -eq 'Windows') { '.exe' } else { '' }

$SDK_Config = @{
    'Dotnet'  = @{
        Exe               = "dotnet$BinExt"
        Bin               = '.'
        Validator         = { param($p) & $p --list-sdks 2>&1 | Select-String '\d+\.\d+' }
        Label             = '.NET SDK'
        GetHome           = { param($p) Split-Path $p -Parent }
        SetEnv            = {
            param($h)
            if ($env:PATH -notlike "*$h*") {
                $sep = if ($global:OS -eq 'Windows') { ';' } else { ':' }
                $escapedHome = $h -replace '"', '""'
                $env:PATH = "`"$escapedHome`"$sep" + $env:PATH
            }
            $env:DOTNET_ROOT = $h
            $env:DOTNET_MSBUILD_SDK_RESOLVER_CLI_DIR = $h
        }
        EnvHome           = { if ($env:DOTNET_ROOT) { $env:DOTNET_ROOT } else { $null } }
        DirectoryPatterns = @('*dotnet*', '*sdk*')
        ExeRelativePath   = "dotnet$BinExt"
        PriorityPaths     = {
            param($OS)
            $paths = @(
                (Join-Path $global:ScriptRoot ".sdk"),
                (Join-Path (Join-Path $global:ScriptRoot "..") ".sdk"),
                (Join-Path (Get-Location).Path ".sdk")
            )
            if ($OS -eq 'Windows') {
                if ($env:ProgramFiles) { $paths += Join-Path $env:ProgramFiles "dotnet" }
            } elseif ($OS -eq 'MacOS') {
                $paths += "/usr/local/share/dotnet"
            } elseif ($OS -eq 'Linux') {
                $paths += "/usr/share/dotnet"
            }
            return $paths
        }
    }
    'JDK'     = @{
        Exe               = "javac$BinExt"
        Bin               = 'bin'
        Validator         = { param($p) & $p -version 2>&1 }
        Label             = 'Java JDK'
        GetHome           = { param($p) Split-Path (Split-Path $p -Parent) -Parent }
        SetEnv            = { param($h) $env:JAVA_HOME = $h }
        EnvHome           = { if ($env:JAVA_HOME) { $env:JAVA_HOME } else { $null } }
        DirectoryPatterns = @('*jdk*', '*jre*', '*java*', '*openjdk*', '*zulu*', '*graalvm*')
        ExeRelativePath   = Join-Path "bin" "javac$BinExt"
        PriorityPaths     = {
            param($OS)
            $paths = @(
                (Join-Path $global:ScriptRoot ".sdk"),
                (Join-Path (Join-Path $global:ScriptRoot "..") ".sdk"),
                (Join-Path (Get-Location).Path ".sdk")
            )
            if ($OS -eq 'Windows') {
                $pf = $env:ProgramFiles; $pf86 = ${env:ProgramFiles(x86)}; $localAppData = $env:LOCALAPPDATA
                if ($pf) { $paths += Join-Path $pf "Java"; $paths += Join-Path (Join-Path $pf "Android") "Android Studio\jbr" }
                if ($pf86) { $paths += Join-Path $pf86 "Java" }
                if ($localAppData) { $paths += Join-Path (Join-Path $localAppData "Android") "Android Studio\jbr" }
            } elseif ($OS -eq 'MacOS') {
                $paths += @("/Library/Java/JavaVirtualMachines", (Join-Path $env:HOME "Library/Java/JavaVirtualMachines"))
            } elseif ($OS -eq 'Linux') {
                $paths += @("/usr/lib/jvm", "/usr/local/lib/jvm")
            }
            return $paths
        }
    }
    'Android' = @{
        Exe               = if ($global:OS -eq 'Windows') { 'sdkmanager.bat' } else { 'sdkmanager' }
        Bin               = 'cmdline-tools/latest/bin'
        Validator         = { param($p) & $p --list 2>&1 }
        Label             = 'Android SDK'
        GetHome           = { param($p) Split-Path (Split-Path $p -Parent) -Parent }
        SetEnv            = {
            param($h)
            $env:ANDROID_HOME = $h
            $env:ANDROID_SDK_ROOT = $h
        }
        EnvHome           = { if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $env:ANDROID_SDK_ROOT } }
        DirectoryPatterns = @('*android*', '*sdk*')
        ExeRelativePath   = if ($global:OS -eq 'Windows') { 'cmdline-tools/latest/bin/sdkmanager.bat' } else { 'cmdline-tools/latest/bin/sdkmanager' }
        PriorityPaths     = {
            param($OS)
            $paths = @(
                (Join-Path $global:ScriptRoot ".sdk"),
                (Join-Path (Join-Path $global:ScriptRoot "..") ".sdk"),
                (Join-Path (Get-Location).Path ".sdk")
            )
            if ($OS -eq 'Windows') {
                $pf = $env:ProgramFiles; $localAppData = $env:LOCALAPPDATA
                if ($localAppData) { $paths += Join-Path (Join-Path $localAppData "Android") "Sdk" }
                if ($pf) { $paths += Join-Path (Join-Path $pf "Android") "android-sdk" }
                if ($env:SystemDrive) { $paths += Join-Path (Join-Path $env:SystemDrive "Android") "android-sdk" }
            } elseif ($OS -eq 'MacOS') {
                $paths += Join-Path (Join-Path $env:HOME "Library") "Android/sdk"
            } elseif ($OS -eq 'Linux') {
                $paths += @((Join-Path (Join-Path $env:HOME "Android") "Sdk"), "/opt/android-sdk")
            }
            return $paths
        }
    }
}

function Get-SdkExePath {
    param([string]$SdkRoot, [string]$ToolType)
    $cfg = $SDK_Config[$ToolType]
    if (-not $cfg) { throw "Lỗi: Không tìm thấy cấu hình cho ToolType '$ToolType'" }
    return Join-Path (Join-Path $SdkRoot $cfg.Bin) $cfg.Exe
}

function Test-SdkValidity {
    param([string]$ExePath, [string]$ToolType)
    $cfg = $SDK_Config[$ToolType]
    if (-not $cfg) { return $false }
    try { return [bool](& $cfg.Validator $ExePath) } catch { return $false }
}

function Invoke-SmartScan {
    param(
        [string]$RootPath,
        [string]$Filter,
        [scriptblock]$ValidateScript,
        [int]$MaxDepth = 4,
        [string]$Label = ""
    )
    # CHỈ IN LOG KHI LABEL CÓ CHỮ (Tránh làm tràn màn hình/tạo dòng trống)
    $shouldLog = -not [string]::IsNullOrWhiteSpace($Label)
    if ($shouldLog) {
        Write-Host "`r   🔎 $Label ...$(' ' * 20)" -NoNewline -ForegroundColor DarkGray
    }

    $found = Invoke-CompatibleChildItem -Path $RootPath -File -Filter $Filter -Recurse -Depth $MaxDepth -EA SilentlyContinue |
        Where-Object { & $ValidateScript $_.FullName } |
        Select-Object -First 1

    if ($shouldLog) {
        Write-Host "`r$(' ' * 80)`r" -NoNewline
    }
    if ($null -ne $found) { return $found.FullName }
    return $null
}

function Find-SdkByDirectory {
    param(
        [string]$RootPath,
        [int]$MaxDepth,
        [string[]]$DirectoryPatterns,
        [string]$ExeRelativePath,
        [string]$Label,
        [scriptblock]$ValidateScript
    )
    Write-Host "`r   🔎 $Label ...$(' ' * 20)" -NoNewline -ForegroundColor DarkGray

    $allDirs = @(Get-ChildItem -Path $RootPath -Directory -Recurse -Depth $MaxDepth -EA SilentlyContinue)
    $priorityDirs = [System.Collections.Generic.List[PSCustomObject]]::new()
    $otherDirs    = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($dir in $allDirs) {
        $isMatch = $false
        foreach ($p in $DirectoryPatterns) { if ($dir.Name -like $p) { $isMatch = $true; break } }
        if ($isMatch) { $priorityDirs.Add($dir) } else { $otherDirs.Add($dir) }
    }

    $exeName = Split-Path $ExeRelativePath -Leaf
    $levels = ($ExeRelativePath -split '[\\/]').Count
    foreach ($dir in (@($priorityDirs) + @($otherDirs))) {
        $found = Invoke-CompatibleChildItem -Path $dir.FullName -File -Filter $exeName -EA SilentlyContinue |
                 Where-Object { & $ValidateScript $_.FullName } |
                 Select-Object -First 1
        if ($found) {
            Write-Host "`r$(' ' * 80)`r" -NoNewline
            $sdkRoot = $found.FullName
            for ($i = 0; $i -lt $levels; $i++) { $sdkRoot = Split-Path $sdkRoot -Parent }
            return $sdkRoot
        }
    }
    Write-Host "`r$(' ' * 80)`r" -NoNewline
    return $null
}

function Get-CachedSdk {
    param([string]$SdkName)
    if (-not (Test-Path -Path $global:CacheFile)) { return $null }
    try {
        $cache = Get-Content -Path $global:CacheFile -Raw | ConvertFrom-Json
        $validUntil = [datetime]$cache.ValidUntil
        if ((Get-Date) -lt $validUntil -and $cache.OS -eq $global:OS) {
            $path = $cache.$SdkName
            if (-not [string]::IsNullOrEmpty($path) -and (Test-Path -Path $path)) {
                Write-Log "⚡ Dùng cache cho ${SdkName}: $path" "DarkGray"
                return $path
            }
        }
    } catch {}
    return $null
}

function Set-CachedSdk {
    param([string]$SdkName, [string]$Path)
    $cache = [ordered]@{}
    if (Test-Path -Path $global:CacheFile) {
        try { 
            $parsed = Get-Content -Path $global:CacheFile -Raw | ConvertFrom-Json 
            if ($null -ne $parsed) {
                $parsed.PSObject.Properties | ForEach-Object { $cache[$_.Name] = $_.Value }
            }
        } catch {}
    }
    $needsReset = -not $cache.Contains('ValidUntil') -or -not $cache.Contains('OS') -or (((Get-Date) -ge ([datetime]$cache['ValidUntil'])) -or ($cache['OS'] -ne $global:OS))
    if ($needsReset) {
        $cache = [ordered]@{
            ValidUntil = (Get-Date).AddDays(30).ToString("o")
            OS         = $global:OS
        }
    }
    $cache[$SdkName] = $Path
    Save-JsonSafe -Path $global:CacheFile -Data $cache
}

function Get-SmartSdk {
    param(
        [ValidateSet('Dotnet', 'JDK', 'Android')]
        [string]$ToolType
    )
    $cfg       = $SDK_Config[$ToolType]
    $exeName   = $cfg.Exe
    $labelName = $cfg.Label

    $getHomeBlock = $cfg.GetHome
    $setEnvBlock  = $cfg.SetEnv

    $cachedPath = Get-CachedSdk -SdkName $ToolType
    if ($cachedPath) {
        $testExe = Get-SdkExePath -SdkRoot $cachedPath -ToolType $ToolType
        if ((Test-Path -Path $testExe) -and (Test-SdkValidity -ExePath $testExe -ToolType $ToolType)) {
            Write-Host "✅ [CACHE] Đã nạp $labelName từ: $cachedPath" -ForegroundColor Green
            $safeHome = Get-SafePath $cachedPath
            & $setEnvBlock $safeHome
            return $(if ($ToolType -eq 'Dotnet') { $testExe } else { $safeHome })
        }
    }

    Write-Host "🔍 Kiểm tra $labelName sẵn có trong hệ thống..." -ForegroundColor Cyan

    $envHome = & $cfg.EnvHome
    if ($envHome -and (Test-Path -Path $envHome)) {
        $testExe = Get-SdkExePath -SdkRoot $envHome -ToolType $ToolType
        if ((Test-Path -Path $testExe) -and (Test-SdkValidity -ExePath $testExe -ToolType $ToolType)) {
            $hPath = & $getHomeBlock $testExe
            $safeHome = Get-SafePath $hPath
            Write-Host "✅ Tìm thấy $labelName từ biến môi trường: $safeHome" -ForegroundColor Green
            Set-CachedSdk -SdkName $ToolType -Path $hPath
            & $setEnvBlock $safeHome
            return $(if ($ToolType -eq 'Dotnet') { $testExe } else { $safeHome })
        }
    }

    $sysCmd = Get-Command $exeName -ErrorAction SilentlyContinue
    if ($sysCmd) {
        $testExe = $sysCmd.Source
        if ($testExe -and (Test-Path -Path $testExe) -and (Test-SdkValidity -ExePath $testExe -ToolType $ToolType)) {
            $hPath = & $getHomeBlock $testExe
            $safeHome = Get-SafePath $hPath
            Write-Host "✅ Tìm thấy $labelName trong PATH hệ thống: $safeHome" -ForegroundColor Green
            Set-CachedSdk -SdkName $ToolType -Path $hPath
            & $setEnvBlock $safeHome
            return $(if ($ToolType -eq 'Dotnet') { $testExe } else { $safeHome })
        }
    }

    $priorityPaths = & $cfg.PriorityPaths -OS $global:OS
    foreach ($path in $priorityPaths) {
        if ($path -and (Test-Path -Path $path)) {
            $foundExe = Get-ChildItem -Path $path -File -Filter $exeName -Recurse -Depth 3 -EA SilentlyContinue |
                Where-Object { Test-SdkValidity -ExePath $_.FullName -ToolType $ToolType } |
                Select-Object -First 1
            if ($foundExe) {
                $hPath = & $getHomeBlock $foundExe.FullName
                $safeHome = Get-SafePath $hPath
                Write-Host "✅ Tìm thấy $labelName tại thư mục ưu tiên: $safeHome" -ForegroundColor Green
                Set-CachedSdk -SdkName $ToolType -Path $hPath
                & $setEnvBlock $safeHome
                return $(if ($ToolType -eq 'Dotnet') { $foundExe.FullName } else { $safeHome })
            }
        }
    }

    $currentDir = (Get-Location).ProviderPath
    Write-Host "🔍 Quét thư mục dự án hiện tại (độ sâu 3)..." -ForegroundColor Cyan
    $validator   = $cfg.Validator
    $validateBlock = { param($p) & $validator $p }.GetNewClosure()
    $res = Invoke-SmartScan -RootPath $currentDir -Filter $exeName -MaxDepth 3 -Label "Quét thư mục dự án" -ValidateScript $validateBlock
    if ($res) {
        $hPath = & $getHomeBlock $res
        $safeHome = Get-SafePath $hPath
        Write-Host "💾 Đã tìm thấy và lưu vị trí $labelName vào cache: $safeHome" -ForegroundColor Green
        Set-CachedSdk -SdkName $ToolType -Path $hPath
        & $setEnvBlock $safeHome
        return $(if ($ToolType -eq 'Dotnet') { $res } else { $safeHome })
    }

    if ($global:OS -eq 'Windows') {
        $projectDrive = [System.IO.Path]::GetPathRoot($currentDir).TrimEnd('\', '/')
        $allDrives = Get-AvailableDrives
        $depthX = ($currentDir.TrimEnd([System.IO.Path]::DirectorySeparatorChar).Split([System.IO.Path]::DirectorySeparatorChar) | Where-Object { $_ -ne "" }).Count
        $searchDepth = $depthX + 3

        $orderedDrives = @($projectDrive)
        if ($allDrives) {
            $orderedDrives += @($allDrives | Where-Object { $_ -ne $projectDrive })
        }

        $directoryPatterns = $cfg.DirectoryPatterns
        $exeRelativePath   = $cfg.ExeRelativePath

        foreach ($drive in $orderedDrives) {
            $targetRoot = $drive + [System.IO.Path]::DirectorySeparatorChar
            $sdkRoot = Find-SdkByDirectory -RootPath $targetRoot -MaxDepth $searchDepth `
                           -DirectoryPatterns $directoryPatterns `
                           -ExeRelativePath $exeRelativePath `
                           -Label "Quét ổ đĩa $drive" `
                           -ValidateScript $validateBlock
            if ($sdkRoot) {
                $safeHome = Get-SafePath $sdkRoot
                Write-Host "✅ Tìm thấy $labelName tại: $safeHome" -ForegroundColor Green
                Set-CachedSdk -SdkName $ToolType -Path $sdkRoot
                & $setEnvBlock $safeHome
                return $(if ($ToolType -eq 'Dotnet') { Join-Path $sdkRoot $exeName } else { $safeHome })
            }
        }
    }

    return $null
}

# Khởi tạo các biến global SDK ngay khi module được import
Write-Log "🔄 Đang khởi tạo SDK toàn cục..." $global:C_Gray
$global:dotnetCmd = Get-SmartSdk -ToolType 'Dotnet'
if (-not $global:dotnetCmd) {
    Write-Host "❌ Không có SDK .NET, không thể tiếp tục." -ForegroundColor Red
    exit 1
}

$global:javaSdk = Get-SmartSdk -ToolType 'JDK'
if (-not $global:javaSdk) {
    Write-Warn "Không tìm thấy Java JDK — các build Android/MAUI sẽ thất bại."
}

$global:androidSdk = Get-SmartSdk -ToolType 'Android'
if (-not $global:androidSdk) {
    Write-Warn "Không tìm thấy Android SDK — các build Android/MAUI sẽ thất bại."
}

$global:currentTfm = $null
$global:latestSdkVersion = $null

# Sau khi có dotnetCmd, lấy version
if ($global:dotnetCmd) {
    $sdksList = @(& $global:dotnetCmd --list-sdks 2>$null)
    if ($sdksList.Count -gt 0) {
        $latestSdkRaw = $sdksList[-1]
        $global:latestSdkVersion = ($latestSdkRaw -split ' ')[0]
        if ($global:latestSdkVersion -match '^(\d+)\.(\d+)') {
            $global:currentTfm = "net$($Matches[1]).$($Matches[2])"
        }
        Write-Done "Đã ghim .NET SDK: $global:latestSdkVersion ➔ TFM: $global:currentTfm"
    } else {
        Write-Warn "Không đọc được version từ SDK này. Sử dụng fallback TFM: $global:currentTfm"
        $global:currentTfm = "net8.0"
    }
}

# Xóa global.json nếu có
$gJsonPath = Join-Path $global:ScriptRoot 'global.json'
if (Test-Path -Path $gJsonPath) {
    try {
        Remove-Item -Path $gJsonPath -Force -ErrorAction Stop
        Write-Log "🗑️  Đã dọn dẹp file global.json (Môi trường đã được quản lý live)" $global:C_Gray
    } catch { Write-Warn "Không thể tự động xóa global.json: $_" }
}

Export-ModuleMember -Function Get-SmartSdk, Get-SdkExePath