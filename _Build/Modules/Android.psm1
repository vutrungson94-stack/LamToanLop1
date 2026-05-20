# ==================================================================================
# Modules/Android.psm1
# ==================================================================================
function Find-AndroidKeystore([string]$projectDir) {
    Write-Log "🔐 Đang tìm kiếm Keystore để ký..." $global:C_Gray
    $propsFile = Join-Path $projectDir 'signing.properties'
    if (Test-Path -Path $propsFile) {
        $props = @{}
        Get-Content -Path $propsFile | ForEach-Object {
            if ($_ -match '^\s*([^#=]+?)\s*=\s*(.+)$') {
                $props[$matches[1].Trim()] = $matches[2].Trim()
            }
        }
        $ksPath = $props['storeFile']
        if ($ksPath -and -not ([System.IO.Path]::IsPathRooted($ksPath))) {
            $ksPath = Join-Path $projectDir $ksPath
        }
        if ($ksPath -and (Test-Path -Path $ksPath)) {
            Write-Log "📝 Đã nạp thông tin từ signing.properties" $global:C_Succ
            $isDebug = $ksPath -match 'debug\.keystore'
            $storePass = if ($props['storePassword']) { $props['storePassword'] } 
                         elseif ($isDebug) { "android" } 
                         else { $null }
            $alias     = if ($props['keyAlias']) { $props['keyAlias'] } 
                         elseif ($isDebug) { "androiddebugkey" } 
                         else { $null }
            $keyPass   = if ($props['keyPassword']) { $props['keyPassword'] } 
                         elseif ($storePass) { $storePass } 
                         else { $null }
            return @{
                Path      = $ksPath
                StorePass = $storePass
                Alias     = $alias
                KeyPass   = $keyPass
                Source    = 'properties'
            }
        }
    }
    $ksFile = Get-ChildItem -Path $projectDir -Recurse -EA SilentlyContinue | 
        Where-Object { $_.Extension -in @('.keystore', '.jks') -and $_.FullName -notmatch '[\\/](obj|bin)[\\/]' } | 
        Select-Object -First 1
    if ($ksFile) {
        $isDebug = $ksFile.Name -eq 'debug.keystore'
        return @{
            Path      = $ksFile.FullName
            StorePass = if ($isDebug) { "android" } else { $null }
            Alias     = if ($isDebug) { "androiddebugkey" } else { $null }
            KeyPass   = if ($isDebug) { "android" } else { $null }
            Source    = 'file'
        }
    }
    return $null
}

function Read-KeystoreInteractive {
    param(
        [hashtable]$ks,
        [switch]$NonInteractive
    )
    if ($null -eq $ks) { return $null }
    if ($NonInteractive) {
        if (-not $ks.StorePass) {
            Write-Fail "NonInteractive: không có mật khẩu keystore, hủy build AAB."
            exit 1
        }
        if (-not $ks.Alias) {
            Write-Fail "NonInteractive: không có key alias, hủy build AAB."
            exit 1
        }
        if (-not $ks.KeyPass) {
            $ks.KeyPass = $ks.StorePass
        }
        return $ks
    }
    Write-Host "`n--- THÔNG TIN KÝ ANDROID ---" -ForegroundColor $global:C_Info
    Write-Host "📍 File: $($ks.Path)" -ForegroundColor $global:C_Gray
    if (-not $ks.StorePass) {
        $sp = Read-Host "🔑 Nhập Store Password (Enter để bỏ qua ký)"
        if ([string]::IsNullOrWhiteSpace($sp)) { return $null }
        $ks.StorePass = $sp
    }
    if (-not $ks.Alias) {
        $ka = Read-Host "🔑 Nhập Key Alias (Ví dụ: androiddebugkey)"
        if ([string]::IsNullOrWhiteSpace($ka)) {
            if ($ks.Path -match 'debug\.keystore') {
                $ks.Alias = 'androiddebugkey'
                Write-Log "⚠️ Dùng alias mặc định cho debug: androiddebugkey" $global:C_Warn
            } else {
                $ks.Alias = 'key0'
                Write-Log "⚠️ Sử dụng alias mặc định 'key0'" $global:C_Warn
            }
        } else { $ks.Alias = $ka }
    }
    if (-not $ks.KeyPass) {
        $kp = Read-Host "🔑 Nhập Key Password (Để trống = giống Store Pass)"
        $ks.KeyPass = if ($kp) { $kp } else { $ks.StorePass }
    }
    return $ks
}

function New-DebugKeystore {
    param([string]$ProjectDir)
    $genPath = Join-Path $ProjectDir "debug.keystore"
    Write-SubLog "Đang khởi tạo Keystore debug via Keytool..."
    $keytoolExe = if ($global:OS -eq 'Windows') { 
        Join-Path $global:javaSdk "bin\keytool.exe" 
    } else { 
        Join-Path $global:javaSdk "bin/keytool" 
    }
    if (-not (Test-Path -Path $keytoolExe)) {
        Write-Fail "Không tìm thấy công cụ keytool trong thư mục JDK ($global:javaSdk)."
        return $null
    }
    try {
        $ktArgs = @(
            "-genkeypair",
            "-v",
            "-keystore", $genPath,
            "-alias", "androiddebugkey",
            "-keyalg", "RSA",
            "-keysize", "2048",
            "-validity", "10000",
            "-storepass", "android",
            "-keypass", "android",
            "-dname", "CN=GBuild Debug, O=Development, C=VN"
        )
        Start-Process -FilePath $keytoolExe -ArgumentList $ktArgs -NoNewWindow -Wait -ErrorAction Stop
        $propsContent = @"
storeFile=debug.keystore
storePassword=android
keyAlias=androiddebugkey
keyPassword=android
"@
        $propsFile = Join-Path $ProjectDir 'signing.properties'
        Set-Content -Path $propsFile -Value $propsContent -Encoding UTF8
        Write-Done "Đã sinh Keystore debug & signing.properties thành công!"
        return @{
            Path      = $genPath
            StorePass = "android"
            Alias     = "androiddebugkey"
            KeyPass   = "android"
            Source    = 'generated'
        }
    }
    catch {
        Write-Fail "Không thể tự động khởi tạo Keystore: $_"
        return $null
    }
}

function Get-AdbDevices {
    param([string]$AdbPath)
    $raw = @(& $AdbPath devices 2>&1)
    return @($raw | Where-Object { $_ -match "\tdevice$" } |
             ForEach-Object { ($_ -split "`t")[0].Trim() })
}

Export-ModuleMember -Function Find-AndroidKeystore, Read-KeystoreInteractive, New-DebugKeystore, Get-AdbDevices