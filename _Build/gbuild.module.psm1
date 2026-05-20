# Đảm bảo các module phụ thuộc được import với -Global để chia sẻ biến
Import-Module "$PSScriptRoot/Modules/Logging.psm1" -Force -Global
Import-Module "$PSScriptRoot/Modules/Environment.psm1" -Force -Global
Import-Module "$PSScriptRoot/Modules/SDK.psm1" -Force -Global
Import-Module "$PSScriptRoot/Modules/Project.psm1" -Force -Global
Import-Module "$PSScriptRoot/Modules/Build.psm1" -Force -Global
Import-Module "$PSScriptRoot/Modules/Android.psm1" -Force -Global
Import-Module "$PSScriptRoot/Modules/Clean.psm1" -Force -Global

# Export hàm chính
function Start-GBuild {
    [CmdletBinding()]
    param(
        [switch]$GitHub,
        [switch]$NonInteractive,
        [switch]$Incremental,
        [switch]$Clean
    )

    # Khởi tạo các biến toàn cục cần thiết (sẽ được định nghĩa trong Environment.psm1 nhưng đảm bảo)
    # Biến $global:StartTime đã được set trong gbuild.ps1? Thực tế nên set ở đây.
    $Global:NonInteractive = $NonInteractive.IsPresent
    $global:StartTime = Get-Date

    # ==================================================================================
    # MAIN FLOW
    # ==================================================================================
    $TotalSteps = 4
    $StepIndex  = 0

    Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║          🚀  MULTI-PURPOSE BUILD TOOL  —  VIP PRO MAX        ║
╚══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor $global:C_Header

    # ── Đồng bộ SDK path vào VS Code workspace settings ──────────────────────────────
    Update-VSCodeDotnetPath -DotnetExePath $global:dotnetCmd

    # ── BƯỚC 2: Quét project ─────────────────────────────────────────────────────────
    $StepIndex++
    $sw2 = [Diagnostics.Stopwatch]::StartNew()
    Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Quét project"
    Write-SubLog "Tìm kiếm .csproj"

    $csproj = Find-Project

    if (-not $csproj) {
        if ($Clean) {
            Show-ProgressBar -Current 50 -Total 100 -Label "Chế độ dọn dẹp độc lập: SMART CLEAN ROOT"
            Write-Warn "Không tìm thấy file .csproj, tiến hành dọn dẹp toàn bộ thư mục gốc dự án."
            $projectDir = $global:ScriptRoot
            
            Invoke-SmartClean -ProjectDir $projectDir -CsprojPath $null
            Write-Done "Đã hoàn tất dọn dẹp sạch sẽ thư mục gốc. Không tiến hành build."
            exit 0
        } else {
            Write-Fail "Không tìm thấy project!"
            exit 1
        }
    }

    $projPath   = $csproj.FullName
    $projectDir = $csproj.DirectoryName

    $meta        = Get-ProjectMetadata -CsprojPath $projPath
    $projectType = $meta.ProjectType
    $tfms        = @($meta.Tfms)

    if ($Clean) {
        Show-ProgressBar -Current 50 -Total 100 -Label "Chế độ dọn dẹp độc lập: SMART CLEAN"
        Write-StepTitle "SMART CLEAN DỰ ÁN" -Color "Yellow"
        Invoke-SmartClean -ProjectDir $projectDir -CsprojPath $projPath
        Write-Done "Dự án đã được dọn dẹp sạch sẽ. Không thực hiện build."
        exit 0
    }

    $winTfm      = ($tfms | Where-Object { $_ -match '-windows$' }) | Select-Object -First 1
    if (-not $winTfm -and ($projectType -in @('WinForms','WPF','WinExe'))) { $winTfm = "$global:currentTfm-windows" }
    $androidTfm  = $tfms | Where-Object { $_ -match 'android'     } | Select-Object -First 1
    $iosTfm      = $tfms | Where-Object { $_ -match 'ios'         } | Select-Object -First 1
    $macTfm      = $tfms | Where-Object { $_ -match 'maccatalyst' } | Select-Object -First 1
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
        Write-Host "  ⌨  Nhập số lựa chọn của bạn..." -ForegroundColor $global:C_Gray
        Write-Host ""
        switch ($projectType) {
            'MAUI' {
                if ($androidTfm) {
                    Write-Host "  [1]  Debug trực tiếp trên thiết bị Android" -ForegroundColor $global:C_Gray
                    Write-Host "  [2]  Xuất bản Android APK"                  -ForegroundColor $global:C_Info
                    Write-Host "  [3]  Xuất bản Android AAB (Google Play)"    -ForegroundColor $global:C_Info
                }
                if ($global:OS -eq 'MacOS') { Write-Host "  [4]  Xuất bản iOS IPA"      -ForegroundColor "Magenta" }
                if ($global:OS -eq 'MacOS') { Write-Host "  [5]  Xuất bản Mac Catalyst" -ForegroundColor "Magenta" }
                if ($winTfm)                { Write-Host "  [6]  Xuất bản Windows MSIX" -ForegroundColor "DarkYellow" }
            }
            'Web' { 
                Write-Host "  [7]  Xuất bản Web UI (EXE + tự khởi chạy)"  -ForegroundColor "Cyan"
                Write-Host "  [W]  Chạy Hot Reload (dotnet watch)"        -ForegroundColor "Cyan" 
            }
            'BlazorWasm' { 
                Write-Host "  [7]  Xuất bản Blazor WASM"                  -ForegroundColor "Cyan"
                Write-Host "  [W]  Chạy Hot Reload (dotnet watch)"        -ForegroundColor "Cyan" 
            }
            'WinForms' { 
                Write-Host "  [8]  Xuất bản WinForms App"                 -ForegroundColor "DarkYellow"
                Write-Host "  [W]  Chạy Hot Reload (dotnet watch)"        -ForegroundColor "Cyan" 
            }
            'WPF' { 
                Write-Host "  [9]  Xuất bản WPF App"                      -ForegroundColor "DarkYellow"
                Write-Host "  [W]  Chạy Hot Reload (dotnet watch)"        -ForegroundColor "Cyan" 
            }
            'Console' { 
                Write-Host "  [10] Xuất bản Console App"                  -ForegroundColor "DarkYellow"
                Write-Host "  [W]  Chạy Hot Reload (dotnet watch)"        -ForegroundColor "Cyan" 
            }
            'Library'    { Write-Host "  [11] Build Library"                         -ForegroundColor "DarkYellow" }
            'WinExe' { 
                Write-Host "  [8]  Xuất bản Windows App"                  -ForegroundColor "DarkYellow"
                Write-Host "  [W]  Chạy Hot Reload (dotnet watch)"        -ForegroundColor "Cyan" 
            }
            default      { Write-Host "  [12] Build mặc định"                        -ForegroundColor "DarkYellow" }
        }
        Write-Host "  [13] ☁  GitHub Cloud Build" -ForegroundColor $global:C_Succ
        Write-Host "  [0]  Thoát"                 -ForegroundColor $global:C_Gray
        Write-Host ""
        $choice = Read-Host "  ►"
        if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }
    }

    # ── BƯỚC 4: Thực thi build ───────────────────────────────────────────────────────
    $StepIndex++

    switch ($choice) {
        '1' {
            Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Debug: Android Device"
            Write-StepTitle "DEBUG TRỰC TIẾP TRÊN THIẾT BỊ ANDROID"
            if (-not $androidTfm -or $projectType -ne 'MAUI') { Write-Fail "Không hỗ trợ!"; exit 1 }
            Invoke-DeviceDebug -Project $projPath -Tfm $androidTfm
        }
        '2' {
            Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang Build: ANDROID APK"
            Write-StepTitle "XUẤT BẢN ANDROID APK" -Color $global:C_Info
            ProcessBuildAndShow -Project $projPath -Tfm $androidTfm -OutputSubDir "apk" -BuildArgs @("-p:AndroidPackageFormat=apk") -ProjectType $projectType -Incremental:$Incremental
        }
        '3' {
            Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang Build: ANDROID AAB"
            Write-StepTitle "XUẤT BẢN ANDROID AAB (GOOGLE PLAY)" -Color "Magenta"

            $ks = $null
            $envPath = $env:ANDROID_KEYSTORE_PATH
            if ($envPath -and (Test-Path $envPath) -and $env:ANDROID_KEYSTORE_PASS) {
                $ks = @{
                    Path      = $envPath
                    StorePass = $env:ANDROID_KEYSTORE_PASS
                    Alias     = if ($env:ANDROID_KEY_ALIAS) { $env:ANDROID_KEY_ALIAS } else { $null }
                    KeyPass   = if ($env:ANDROID_KEY_PASS) { $env:ANDROID_KEY_PASS } else { $env:ANDROID_KEYSTORE_PASS }
                }
            }
            if (-not $ks) {
                $ks = Find-AndroidKeystore -projectDir $projectDir
            }
            if (-not $ks) {
                if ($NonInteractive) {
                    Write-Fail "NonInteractive: không tìm thấy Keystore, hủy build AAB."
                    exit 1
                }
                Write-Warn "Không tìm thấy Keystore."
                $create = Read-Host "Tạo Keystore debug mới? (Y/N)"
                if ($create -eq 'Y') {
                    $ks = New-DebugKeystore -ProjectDir $projectDir
                }
                if (-not $ks) {
                    Write-Fail "Huỷ build AAB do thiếu Keystore."
                    exit 1
                }
            }
            $ks = Read-KeystoreInteractive -ks $ks -NonInteractive:$NonInteractive
            if (-not $ks -or -not $ks.StorePass) {
                Write-Fail "Thiếu mật khẩu keystore."
                exit 1
            }

            Build-AndroidAab -ProjectPath $projPath -Tfm $androidTfm -Keystore $ks -ProjectType $projectType
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
                $targetTfm = if ($winTfm) { $winTfm } else { "$global:currentTfm-windows" }
                ProcessBuildAndShow -Project $projPath -Tfm $targetTfm -OutputSubDir "win" -BuildArgs @("-p:WindowsPackageType=None","-p:PublishSingleFile=false","--self-contained","true") -ProjectType $projectType -Incremental:$Incremental
            }
        }
        '7' {
            if ($projectType -eq 'Web') {
                Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang Build: WEB"
                Write-StepTitle "XUẤT BẢN WEB UI" -Color $global:C_Info
                $swWeb = [Diagnostics.Stopwatch]::StartNew()
                ProcessBuildAndShow -Project $projPath -Tfm $global:currentTfm -OutputSubDir "web" -BuildArgs @("-p:PublishSingleFile=false") -ProjectType $projectType -Incremental:$Incremental
                $webOutDir   = Join-Path $global:ScriptRoot "publish-output" "web"
                $exeBaseName = [System.IO.Path]::GetFileNameWithoutExtension($projPath)
                $exeSuffix   = if ($global:OS -eq 'Windows') { '.exe' } else { '' }
                $exePath     = Join-Path $webOutDir ($exeBaseName + $exeSuffix)
                $dynamicPort = Get-ProjectPort -ProjectDir (Split-Path $projPath)
                $url         = "http://localhost:$dynamicPort"
                if (Test-Path -Path $exePath) {
                    Write-SubLog "Khởi chạy ứng dụng tại $url"
                    $spArgs = @{
                        FilePath         = (Get-SafePath $exePath)
                        ArgumentList     = "--urls=$url"
                        WorkingDirectory = (Get-SafePath $webOutDir)
                        PassThru         = $true
                    }
                    if ($global:OS -eq 'Windows') { $spArgs['WindowStyle'] = 'Hidden' }
                    Start-Process @spArgs | Out-Null
                    $maxWait = 15; $waited = 0; $portReady = $false
                    while ($waited -lt $maxWait) {
                        Start-Sleep -Seconds 1; $waited++
                        if (Test-PortListening -Port $dynamicPort) { $portReady = $true; break }
                    }
                    $swWeb.Stop()
                    if ($portReady) {
                        Open-Target $url
                        Write-Done "App đang chạy tại $url" $swWeb.Elapsed.TotalSeconds
                    } else {
                        Write-Warn "App phản hồi chậm — kiểm tra tại: $url"
                    }
                }
            } elseif ($projectType -eq 'BlazorWasm') {
                Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang Build: Blazor WASM"
                Write-StepTitle "XUẤT BẢN BLAZOR WASM" -Color $global:C_Info
                ProcessBuildAndShow -Project $projPath -Tfm $global:currentTfm -OutputSubDir "blazorwasm" -ProjectType $projectType -Incremental:$Incremental
            }
        }
        'W' {
            $supportedWatch = @('Web', 'BlazorWasm', 'WinForms', 'WPF', 'Console', 'WinExe')
            if (-not ($supportedWatch -contains $projectType)) {
                Write-Fail "❌ Chế độ Hot Reload hiện chỉ hỗ trợ: $($supportedWatch -join ', ')."
                exit 1
            }

            Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang chạy: Hot Reload"
            Write-StepTitle "KHỞI CHẠY CHẾ ĐỘ HOT RELOAD (DOTNET WATCH)" -Color $global:C_Info

            $projectDir  = Split-Path $projPath -Parent
            $exeBaseName = [System.IO.Path]::GetFileNameWithoutExtension($projPath)

            $publishSubDir = if ($projectType -eq 'BlazorWasm') { 'blazorwasm' } else { 'web' }
            $publishOutDir = Join-Path $global:ScriptRoot 'publish-output' $publishSubDir
            if (Test-Path -Path $publishOutDir) {
                Remove-Item -Path $publishOutDir -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "   🗑️ Đã xóa publish output cũ → tránh lỗi BLAZOR106." $global:C_Gray
            }

            Write-Log "🧹 Đang dọn dẹp cache và cấu hình cũ..." $global:C_Gray
            Invoke-SmartClean -ProjectDir $projectDir -CsprojPath $projPath

            Write-Log "🔍 Kiểm tra và giải phóng tài nguyên mạng..." $global:C_Gray
            Invoke-KillByPort -ProjectDir $projectDir -ProjectType $projectType -ExeName $exeBaseName

            Write-Log "🚀 Đang khởi động dotnet watch (Nhấn Ctrl+C để dừng)..." $global:C_Succ
            $safeProject = Get-SafePath $projPath
            & $global:dotnetCmd watch run --project $safeProject
        }
        '8' {
            Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang Build: DESKTOP APP"
            Write-StepTitle "XUẤT BẢN DESKTOP APP" -Color "DarkYellow"
            $targetTfm = if ($winTfm) { $winTfm } elseif ($tfms) { $tfms[0] } else { "$global:currentTfm-windows" }
            if ($projectType -in @('WinForms','WinExe')) {
                ProcessBuildAndShow -Project $projPath -Tfm $targetTfm -OutputSubDir "winforms" -ProjectType $projectType -Incremental:$Incremental
            } elseif ($projectType -eq 'MAUI' -and $winTfm) {
                ProcessBuildAndShow -Project $projPath -Tfm $targetTfm -OutputSubDir "win" -BuildArgs @("-p:WindowsPackageType=None","-p:PublishSingleFile=false","--self-contained","true") -ProjectType $projectType -Incremental:$Incremental
            }
        }
        '9' {
            Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang Build: WPF"
            Write-StepTitle "XUẤT BẢN WPF APP" -Color "DarkYellow"
            if ($projectType -eq 'WPF') {
                ProcessBuildAndShow -Project $projPath -Tfm $global:currentTfm -OutputSubDir "wpf" -BuildArgs @("-r",(Get-RuntimeIdentifier),"--self-contained","true") -ProjectType $projectType -Incremental:$Incremental
            }
        }
        '10' {
            Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Đang Build: CONSOLE"
            Write-StepTitle "XUẤT BẢN CONSOLE APP" -Color "DarkYellow"
            if ($projectType -eq 'Console') {
                ProcessBuildAndShow -Project $projPath -Tfm $global:currentTfm -OutputSubDir "console" -BuildArgs @("-r",(Get-RuntimeIdentifier),"--self-contained","true") -ProjectType $projectType -Incremental:$Incremental
            }
        }
        '11' {
            Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Build: LIBRARY"
            Write-StepTitle "BUILD LIBRARY" -Color "Gray"
            if ($projectType -eq 'Library') {
                ProcessBuildAndShow -Project $projPath -Tfm $global:currentTfm -OutputSubDir "lib" -ProjectType $projectType -Incremental:$Incremental
            }
        }
        '12' {
            Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "Build: DEFAULT"
            Write-StepTitle "BUILD MẶC ĐỊNH" -Color "Gray"
            ProcessBuildAndShow -Project $projPath -Tfm $global:currentTfm -OutputSubDir "default" -ProjectType $projectType -Incremental:$Incremental
        }
        '13' {
            Show-ProgressBar -Current $StepIndex -Total $TotalSteps -Label "GitHub Cloud Build"
            Write-StepTitle "GỬI YÊU CẦU BUILD LÊN GITHUB" -Color $global:C_Succ
            $userInput = Read-Host "  📦 Định dạng (1=apk [mặc định] / 2=aab)"
            $fmt = if ($userInput -eq "2") { "aab" } else { "apk" }
            Write-SubLog "Kích hoạt GitHub Actions — $fmt"
            Invoke-GitHubBuild -PackageFormat $fmt
            Write-Done "Đã trigger GitHub Actions ($fmt)"
        }
        '0' { Write-Info "Đã thoát."; exit 0 }
        default { Write-Fail "Lựa chọn không hợp lệ: '$choice'"; exit 1 }
    }

    $totalSec = [math]::Round(((Get-Date) - $global:StartTime).TotalSeconds, 1)
    Write-Host ""
    Write-Sep
    _2Col "  🏁 HOÀN TẤT" "Tổng thời gian: ${totalSec}s" $global:C_Succ "DarkGray"
    Write-Sep
}

# Export hàm để bên ngoài có thể gọi
Export-ModuleMember -Function Start-GBuild