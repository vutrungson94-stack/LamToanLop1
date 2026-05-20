# ==================================================================================
# Modules/Project.psm1
# ==================================================================================
$global:NonInteractive = $false

function Get-ProjectMetadata {
    param([string]$CsprojPath, [string]$FallbackTfm = $global:currentTfm)
    $default = [PSCustomObject]@{ ProjectType = 'Unknown'; Tfms = @($FallbackTfm) }
    if (-not (Test-Path -Path $CsprojPath)) { return $default }
    try {
        [xml]$xml = Get-Content -Path $CsprojPath -Raw
        $sdk = $xml.Project.Sdk
        $projectType = if ($xml.SelectSingleNode("//*[local-name()='UseMaui' and text()='true']")) {
            'MAUI'
        } elseif ($sdk -eq 'Microsoft.NET.Sdk.Web') {
            'Web'
        } elseif ($sdk -eq 'Microsoft.NET.Sdk.BlazorWebAssembly') {
            'BlazorWasm'
        } elseif ($xml.SelectSingleNode("//*[local-name()='UseWindowsForms' and text()='true']")) {
            'WinForms'
        } elseif ($xml.SelectSingleNode("//*[local-name()='UseWPF' and text()='true']")) {
            'WPF'
        } else {
            $outputType = $xml.SelectSingleNode("//*[local-name()='OutputType']") | Select-Object -ExpandProperty InnerText
            if     ($outputType -eq 'Exe')    { 'Console' }
            elseif ($outputType -eq 'WinExe') { if ($sdk -eq 'Microsoft.NET.Sdk.WindowsDesktop') { 'WinForms' } else { 'WinExe' } }
            else                              { 'Library' }
        }
        $tfms = @()
        $nodes = $xml.SelectNodes("//*[local-name()='TargetFramework' or local-name()='TargetFrameworks']")
        foreach ($node in $nodes) {
            $tfms += $node.InnerText.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() }
        }
        if ($tfms.Count -eq 0) { $tfms = @($FallbackTfm) }
        return [PSCustomObject]@{ ProjectType = $projectType; Tfms = $tfms }
    } catch { return $default }
}

function Find-Project {
    Write-Log "📂 Đang quét tìm file project..." $global:C_Gray

    $searchRoot = $PWD.ProviderPath
    Write-Log "   🔍 Thư mục gốc: $searchRoot" $global:C_Gray

    # Dùng Get-ChildItem trực tiếp, không qua hàm trung gian (giống code gốc)
    $allProjects = @(Get-ChildItem -Path $searchRoot -Recurse -Filter *.csproj -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/](obj|bin|node_modules|\.sdk)[\\/]' } |
        Sort-Object FullName)

    Write-Log "   📄 Tìm thấy $($allProjects.Count) project(s)" $global:C_Gray

    if ($allProjects.Count -eq 0) { return $null }
    if ($allProjects.Count -eq 1) { return $allProjects[0] }

    # Nếu có nhiều project, ưu tiên project trong thư mục gốc script
    $scriptDirProjects = @($allProjects | Where-Object { $_.DirectoryName -eq $global:ScriptRoot })
    if ($scriptDirProjects.Count -eq 1) { return $scriptDirProjects[0] }

    # NonInteractive mode
    if ($global:NonInteractive) {
        Write-Warn "Chế độ NonInteractive: Tự động chọn project đầu tiên -> $($allProjects[0].Name)"
        return $allProjects[0]
    }

    # Tương tác chọn project
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

function Get-LaunchSettingsPorts {
    param([string]$ProjectDir)
    $ports  = [System.Collections.Generic.HashSet[int]]::new()
    $lsPath = Join-Path $ProjectDir "Properties" "launchSettings.json"
    if (Test-Path -Path $lsPath) {
        try {
            $ls = Get-Content -Path $lsPath -Raw | ConvertFrom-Json
            $ls.profiles.PSObject.Properties.Value | ForEach-Object {
                $_.applicationUrl -split ';' | ForEach-Object {
                    if ($_ -match ':(\d+)') { [void]$ports.Add([int]$matches[1]) }
                }
            }
        } catch {}
    }
    return $ports
}

function Get-ProjectPort {
    param([string]$ProjectDir)
    $ports = Get-LaunchSettingsPorts -ProjectDir $ProjectDir
    if ($ports.Count -gt 0) { return @($ports)[0] }
    return 5000
}

Export-ModuleMember -Function Get-ProjectMetadata, Find-Project, Get-LaunchSettingsPorts, Get-ProjectPort