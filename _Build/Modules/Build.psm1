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

    # Bảo vệ: Chỉ kiểm tra thư mục dự án có thực sự tồn tại hay không
    $resolvedProjectDir = try { (Get-Item -Path $projectDir -EA Stop).FullName } catch { $null }
    if (-not $resolvedProjectDir -or -not (Test-Path -Path $resolvedProjectDir)) {
        Write-Log "❌ [SAFETY] Không tìm thấy thư mục dự án hợp lệ ('$projectDir'). Hủy!" $C_Err
        exit 1
    }

    Invoke-SmartClean -ProjectDir $projectDir -OutputSubDir $OutputSubDir -CsprojPath $Project

    $rawOut        = Join-Path $global:ScriptRoot "publish-output" $OutputSubDir
    $csprojContent = Get-Content -Path $Project -Raw -EA SilentlyContinue
    $exeBaseName   = [System.IO.Path]::GetFileNameWithoutExtension($Project)

    Invoke-KillByPort -ProjectDir $projectDir -ProjectType $ProjectType -ExeName $exeBaseName -OutputDir $rawOut

    # Kill thêm các process đang chiếm file trong rawOut (chỉ trên Windows, kiểm tra modules)
    if ($global:OS -eq 'Windows') {
        $suspiciousProcs = Get-Process -Name 'dotnet', $exeBaseName, 'iisexpress' -ErrorAction SilentlyContinue
        $lockedProcs = $suspiciousProcs | Where-Object {
            try { foreach ($mod in $_.Modules) { if ($mod.FileName -like "$rawOut\*") { return $true } } } catch {}
            return $false
        }
        if ($lockedProcs) {
            $lockedProcs | Stop-Process -Force -ErrorAction SilentlyContinue
            Write-Log "   🎯 Đã kill tiến trình khóa file." $C_Warn
        }
    }

    # Dọn artifact output — uỷ quyền hoàn toàn cho Invoke-SmartClean thay vì xử lý inline
    if (-not $Incremental) {
        Invoke-SmartClean -ProjectDir $projectDir -OutputSubDir $OutputSubDir -CsprojPath $Project -CleanOutputDir
    } else {
        Write-Log "⚡ Incremental mode: bỏ qua dọn output." $C_Info
    }

    if (-not (Test-Path -Path $rawOut)) {
        [System.IO.Directory]::CreateDirectory($rawOut) | Out-Null
    }
    Write-Log "   ✅ Thư mục output đã sẵn sàng." $C_Gray

    # ── Kiểm tra nền tảng & dùng global SDK (không gọi lại Get-SmartSdk) ──
    $isAndroidPlatform = $Tfm -match 'android'
    $isApplePlatform   = $Tfm -match '(ios|maccatalyst)'
    $isWindowsPlatform = $Tfm -match 'windows'

    if ($isAndroidPlatform) {
        if (-not $global:androidSdk) { Write-Log "❌ Thiếu Android SDK!" $C_Err; exit 1 }
        if (-not $global:javaSdk)    { Write-Log "❌ Thiếu Java JDK!"    $C_Err; exit 1 }
    }

    $safeRawOut  = Get-SafePath $rawOut
    $safeProject = Get-SafePath $Project

    Write-Log "🐞 dotnet : $($global:dotnetCmd)" $C_Gray
    Write-Log "🐞 TFM    : $Tfm  |  Output: $rawOut" $C_Gray
    Write-Log "🐞 Loại   : $ProjectType" $C_Gray

    # ── Xây dựng tham số publish ──
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
            if ($BuildArgs -notcontains "--self-contained") { $params += "--self-contained" }
            if ($BuildArgs -notcontains "-r") { $params += "-r", (Get-RuntimeIdentifier) }
        }
        'BlazorWasm' { $params += @("-r", "browser-wasm") }
        'Library' {
            Write-Log "⚠️ Library — chuyển sang build thay vì publish." $C_Warn
            $params = @("build", $safeProject, "-f", $Tfm, "-c", "Release")
        }
        default { Write-Log "⚠️ Loại dự án không xác định, dùng publish mặc định." $C_Warn }
    }

    if ($isAndroidPlatform) {
        $params += "-p:AndroidSdkDirectory=$($global:androidSdk)"
        $params += "-p:JavaSdkDirectory=$($global:javaSdk)"
    }

    if ($BuildArgs) { $params += $BuildArgs }
    $params += @("-p:BuildInParallel=true", "-m", "-v", "minimal")

    Write-Host ""
    Write-Sep
    Write-SubLog "dotnet publish  [$Tfm]"
    Write-Sep

    $sw        = [System.Diagnostics.Stopwatch]::StartNew()
    $copyCount = 0; $warnCount = 0; $errCount = 0
    $isProgressActive = $false

    $output = & $global:dotnetCmd @params 2>&1 | ForEach-Object {
        $line = $_.ToString().TrimEnd()
        if ([string]::IsNullOrWhiteSpace($line)) { return $line }
        if ($line -match '^\s*Copying file from') { $copyCount++; return $line }
        if ($line -match '(?i)\berror\b') {
            if ($isProgressActive) { Write-Host ""; $isProgressActive = $false }
            $errCount++; Write-Host "  ❌ $line" -ForegroundColor $C_Err
        } elseif ($line -match '(?i)\bwarning\b') {
            if ($isProgressActive) { Write-Host ""; $isProgressActive = $false }
            $warnCount++; Write-Host "  ⚠️  $line" -ForegroundColor $C_Warn
        } elseif ($line -match '(Build succeeded|Build FAILED|->\s|Publish:|Done Building|Time Elapsed)') {
            if ($isProgressActive) { Write-Host ""; $isProgressActive = $false }
            Write-Host "  ✔  $line" -ForegroundColor $C_Succ
        } else {
            $shortLine = $line.Trim()
            if ($shortLine.Length -gt 70) { $shortLine = $shortLine.Substring(0, 67) + "..." }
            Write-Host "`r   ⚙️ $shortLine$(' ' * 20)" -NoNewline -ForegroundColor DarkGray
            $isProgressActive = $true
        }
        $line
    }

    if ($isProgressActive) { Write-Host "`r$(' ' * 100)`r" -NoNewline }

    $exitCode = $LASTEXITCODE
    $sw.Stop()

    Write-Sep
    Write-SectionBox "KẾT QUẢ BUILD"
    if ($copyCount -gt 0) { _2Col "  📦 Static files" "$copyCount file(s) copied" $C_Gray "DarkGray" }

    if ($exitCode -ne 0) {
        Write-Fail "BUILD THẤT BẠI (exit $exitCode) — $errCount lỗi, $warnCount cảnh báo" $sw.Elapsed.TotalSeconds
        $output | Where-Object { $_ -match '(?i)\serror\s' } |
            ForEach-Object { Write-Host "    >> $_" -ForegroundColor $C_Err }
        exit 1
    }

    Write-Done "File APK/AAB/EXE đã sẵn sàng!" $sw.Elapsed.TotalSeconds
    if ($ProjectType -ne 'Library') { Open-Target $rawOut }

    if ($isAndroidPlatform -and $OutputSubDir -eq "apk") {
        $apkFile = Get-ChildItem -Path $rawOut -Filter "*Signed*.apk" -Recurse | Select-Object -First 1
        if (-not $apkFile) { $apkFile = Get-ChildItem -Path $rawOut -Filter "*.apk" -Recurse | Select-Object -First 1 }
        if ($apkFile) {
            $appIdMatch = [regex]::Match($csprojContent, '<ApplicationId>([^<]+)</ApplicationId>')
            $appId      = if ($appIdMatch.Success) { $appIdMatch.Groups[1].Value.Trim() } else { "com.companyname.app" }
            Write-Host "`n" -NoNewline
            Invoke-AutoDeploy -ApkPath $apkFile.FullName -AppId $appId -AndroidSdkPath $global:androidSdk
        } else {
            Write-Log "⚠️ Không tìm thấy APK để deploy." $C_Warn
            Open-Target $rawOut
        }
    }
}

function Invoke-DeviceDebug {
    param([string]$Project, [string]$Tfm)

    # Dùng global — đã được Get-SmartSdk khởi tạo 1 lần lúc startup
    if (-not $global:androidSdk) { Write-Log "❌ Không tìm thấy Android SDK!" $C_Err; return }

    # Get-SdkExePath tự suy tên exe theo OS, không cần kiểm tra OS thủ công tại callsite
    $adb = Get-SdkExePath -SdkRoot $global:androidSdk -ToolType 'Android'
    if (-not (Test-Path -Path $adb)) { Write-Log "❌ Không tìm thấy adb!" $C_Err; return }

    # Dùng Get-AdbDevices thay vì parse inline
    $devices = Get-AdbDevices -AdbPath $adb
    if ($devices.Count -eq 0) {
        Write-Log "❌ Không tìm thấy thiết bị Android nào đang kết nối!" $C_Err
        return
    }

    $manufacturer = & $adb shell getprop ro.product.manufacturer 2>&1 | Out-String
    if ($manufacturer.Trim() -eq 'Xiaomi') {
        Write-Log "🛠  Thiết bị Xiaomi – tối ưu cài đặt..." $C_Gray
        & $adb shell settings put global verifier_verify_adb_installs 0 2>&1 | Out-Null
        & $adb shell settings put global package_verifier_enable 0 2>&1 | Out-Null
    } else {
        Write-Log "ℹ️  Thiết bị không phải Xiaomi, bỏ qua tối ưu." $C_Gray
    }

    Write-Host "`n📱 PHÁT HIỆN THIẾT BỊ: $($devices[0].ToString().Trim())" -ForegroundColor $C_Info
    $confirm = Read-Host "`n❓ Bạn có muốn bắt đầu gỡ lỗi trên thiết bị này không? (Y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') { return }

    $safeProject    = Get-SafePath $Project
    $safeAndroidSdk = Get-SafePath $global:androidSdk
    $safeJavaSdk    = Get-SafePath $global:javaSdk

    Write-Log "🚀 Đang triển khai app lên thiết bị..." $C_Succ
    & $global:dotnetCmd @(
        "build", $safeProject,
        "-t:Run",
        "-f", $Tfm,
        "-p:AndroidSdkDirectory=$safeAndroidSdk",
        "-p:JavaSdkDirectory=$safeJavaSdk"
    )
}

function Invoke-AutoDeploy {
    param(
        [string]$ApkPath,
        [string]$AppId,
        [string]$AndroidSdkPath = ""
    )
    # Ưu tiên tham số truyền vào, fallback về global
    $sdk = if ($AndroidSdkPath) { $AndroidSdkPath } else { $global:androidSdk }
    # Get-SdkExePath tự suy tên exe theo OS, không cần kiểm tra OS thủ công tại callsite
    $adb = if ($sdk) { Get-SdkExePath -SdkRoot $sdk -ToolType 'Android' } else { "adb" }
    if (-not (Test-Path -Path $adb) -and $adb -ne "adb") { return }
    if (-not (Test-Path -Path $ApkPath)) { return }

    $safeApkPath = Get-SafePath $ApkPath

    # Dùng Get-AdbDevices thay vì parse inline
    $allDevices = Get-AdbDevices -AdbPath $adb
    if ($allDevices.Count -eq 0) { return }

    $realDevices  = @($allDevices | Where-Object { $_ -notmatch "^emulator-" -and $_ -notmatch "^127\.0\.0\." })
    $emulators    = @($allDevices | Where-Object { $_ -match "^emulator-" -or $_ -match "^127\.0\.0\." })
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
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$ProjectDir,
        [string]$ProjectType,
        [string]$ExeName,
        [string]$OutputDir = ""
    )
    $supportedTypes = @('Web', 'BlazorWasm', 'Console', 'WPF', 'WinForms', 'WinExe')
    if ($ProjectType -notin $supportedTypes) { return }

    Write-Log "🔍 Đang giải phóng tài nguyên cho: $ProjectType..." $C_Gray
    $pathCmp = if ($global:OS -eq 'Windows') {
        [System.StringComparison]::OrdinalIgnoreCase
    } else {
        [System.StringComparison]::Ordinal
    }

    # ── 1. Kill theo đường dẫn OutputDir ──
    if (-not [string]::IsNullOrWhiteSpace($OutputDir) -and (Test-Path -Path $OutputDir)) {
        Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.Path -and $_.Path.StartsWith($OutputDir, $pathCmp)
        } | ForEach-Object {
            # --- BỌC BẰNG SHOULDPROCESS ---
            if ($PSCmdlet.ShouldProcess("Tiến trình: $($_.ProcessName) (PID: $($_.Id))", "Kill tiến trình khóa thư mục OutputDir")) {
                Stop-Process -InputObject $_ -Force -ErrorAction SilentlyContinue
                Write-Log "   ✅ Đã giải phóng tiến trình: $($_.ProcessName)." $C_Succ
            }
        }
    }

    if ($ProjectType -notin @('Web', 'BlazorWasm')) { return }

    $portsToKill = Get-LaunchSettingsPorts -ProjectDir $ProjectDir
    foreach ($cfgFile in @("appsettings.json", "appsettings.Production.json")) {
        $cfgPath = Join-Path $ProjectDir $cfgFile
        if (Test-Path -Path $cfgPath) {
            try {
                $cfg = Get-Content -Path $cfgPath -Raw | ConvertFrom-Json
                if ($cfg.Kestrel -and $cfg.Kestrel.Endpoints) {
                    $cfg.Kestrel.Endpoints.PSObject.Properties.Value | ForEach-Object {
                        if ($_.Url -match ':(\d+)') { [void]$portsToKill.Add([int]$matches[1]) }
                    }
                }
                if ($cfg.Urls) {
                    $cfg.Urls -split ';' | ForEach-Object {
                        if ($_ -match ':(\d+)') { [void]$portsToKill.Add([int]$matches[1]) }
                    }
                }
            } catch {}
        }
    }

    if ($portsToKill.Count -eq 0) { return }

    Write-Log "   📋 Port cần giải phóng: $($portsToKill -join ', ')" $C_Gray
    foreach ($port in $portsToKill) {
        if ($global:OS -eq 'Windows') {
            $conns = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
            foreach ($conn in $conns) {
                if ($conn.OwningProcess -le 0) { continue }
                try {
                    $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
                    if (-not $proc) { continue }
                    $inOutputDir = (-not [string]::IsNullOrWhiteSpace($OutputDir)) -and
                                   $proc.Path -and
                                   $proc.Path.StartsWith($OutputDir, $pathCmp)
                    $isExeMatch  = $proc.ProcessName -eq $ExeName
                    
                    if ($inOutputDir -or $isExeMatch) {
                        # --- BỌC BẰNG SHOULDPROCESS ---
                        if ($PSCmdlet.ShouldProcess("Tiến trình $($proc.ProcessName) (PID $($conn.OwningProcess))", "Kill tiến trình đang giữ Port $port")) {
                            Write-Log "   🔌 Port $port → kill PID $($conn.OwningProcess) ($($proc.ProcessName))" $C_Gray
                            Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
                        }
                    }
                } catch {}
            }
        } else {
            # Bọc tương đối cho Unix/macOS
            if ($PSCmdlet.ShouldProcess("Port $port (Unix)", "Kill mọi tiến trình đang giữ Port")) {
                if ($global:OS -eq 'MacOS') { & sh -c "lsof -t -iTCP:$port -sTCP:LISTEN | xargs kill -9 2>/dev/null" }
                else                        { & sh -c "fuser -k ${port}/tcp 2>/dev/null" }
            }
        }
    }
}

function Build-AndroidAab {
    param(
        [string]$ProjectPath,
        [string]$Tfm,
        [hashtable]$Keystore,
        [string]$ProjectType
    )

    Write-Log "🚀 Sẵn sàng build AAB với Keystore: $($Keystore.Path) (Alias: $($Keystore.Alias))" $C_Succ

    $signingArgs = @(
        "-p:AndroidKeyStore=true",
        "-p:AndroidSigningKeyStore=`"$($Keystore.Path)`"",
        "-p:AndroidSigningStorePass=`"$($Keystore.StorePass)`"",
        "-p:AndroidSigningKeyAlias=`"$($Keystore.Alias)`"",
        "-p:AndroidSigningKeyPass=`"$($Keystore.KeyPass)`""
    )

    ProcessBuildAndShow -Project $ProjectPath -Tfm $Tfm `
        -OutputSubDir "aab" `
        -BuildArgs ($signingArgs + @("-p:AndroidPackageFormat=aab")) `
        -ProjectType $ProjectType
}

function Invoke-GitHubBuild([string]$PackageFormat) {
    Write-Log "☁ Đang kết nối GitHub Cloud..." $C_Info
    $ghCmd = Get-Command gh -EA SilentlyContinue
    if (-not $ghCmd) {
        Write-Log "❌ Không tìm thấy GitHub CLI (gh). Cài tại: https://cli.github.com" $C_Err
        return
    }
    $branch = git branch --show-current 2>$null
    if (-not $branch) { $branch = "main" }
    Write-Log "🚀 Trigger build $PackageFormat trên nhánh $branch..." $C_Succ
    & $ghCmd.Source workflow run build.yml --ref $branch -f "package_format=$PackageFormat"
    
     if ($LASTEXITCODE -ne 0) {
        Write-Fail "❌ Trigger thất bại (exit code $LASTEXITCODE). Kiểm tra xác thực gh."
        return
    }

    Write-Log "✅ Đã trigger thành công. Kiểm tra tại GitHub." $C_Info
}