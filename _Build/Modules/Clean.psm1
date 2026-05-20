# ==================================================================================================
# Modules/Clean.psm1
# ==================================================================================================
function Invoke-SmartClean {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)] [string]$ProjectDir,
        [string]$OutputSubDir  = "",
        [string]$CsprojPath    = "",
        [switch]$CleanOutputDir
    )
    $absProjectDir = try { [System.IO.Path]::GetFullPath($ProjectDir) } catch { return }
    if (-not (Test-Path -Path $absProjectDir -PathType Container)) { return }

    $pathCmp   = if ($global:OS -eq 'Windows') { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    $rootPrefix = $absProjectDir.TrimEnd([System.IO.Path]::DirectorySeparatorChar,
                                          [System.IO.Path]::AltDirectorySeparatorChar) +
                  [System.IO.Path]::DirectorySeparatorChar

    function Assert-SafePath {
        param([string]$Target)
        if ([string]::IsNullOrWhiteSpace($Target)) { return $false }
        $canonical = try { [System.IO.Path]::GetFullPath($Target) } catch { return $false }
        return $canonical.StartsWith($rootPrefix, $pathCmp) -or
               [string]::Equals($canonical, $absProjectDir.TrimEnd(
                   [System.IO.Path]::DirectorySeparatorChar,
                   [System.IO.Path]::AltDirectorySeparatorChar), $pathCmp)
    }

    $csprojContent = ""
    if ($CsprojPath -and (Test-Path -Path $CsprojPath -PathType Leaf)) {
        $csprojContent = Get-Content -Path $CsprojPath -Raw -EA SilentlyContinue
    }
    $isWeb  = $csprojContent -match 'Sdk\s*=\s*"Microsoft\.NET\.Sdk\.(Web|BlazorWebAssembly)"'
    $isMaui = $csprojContent -match '<UseMaui>\s*true\s*</UseMaui>'

    $targetsToClean = [System.Collections.Generic.List[string]]::new()

    function Add-CleanTarget {
        param([string]$Path)
        if ([string]::IsNullOrWhiteSpace($Path)) { return }
        if (-not (Test-Path -Path $Path -PathType Container)) { return }
        if (-not (Assert-SafePath $Path)) { return }
        $item = Get-Item -Path $Path -Force -EA SilentlyContinue
        if ($item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            Write-Log "   ⚠️  Bỏ qua symlink: $Path" $global:C_Warn; return
        }
        $targetsToClean.Add($Path)
    }

    foreach ($name in @('bin', 'obj'))                       { Add-CleanTarget (Join-Path $absProjectDir $name) }
    foreach ($name in @('.vs', '.idea', '.fleet', '.cache')) { Add-CleanTarget (Join-Path $absProjectDir $name) }

    if ($isWeb) {
        foreach ($pair in @(@('wwwroot','_framework'), @('wwwroot','_content'), @('.vite'), @('node_modules'))) {
            Add-CleanTarget ([System.IO.Path]::Combine(@($absProjectDir) + $pair))
        }
    }
    if ($isMaui) {
        foreach ($name in @('.maui', 'MauiAssets')) { Add-CleanTarget (Join-Path $absProjectDir $name) }
        $platformsDir = Join-Path $absProjectDir 'Platforms'
        if (Test-Path -Path $platformsDir -PathType Container) {
            Get-ChildItem -Path $platformsDir -Directory -EA SilentlyContinue | ForEach-Object {
                Add-CleanTarget (Join-Path $_.FullName 'bin')
                Add-CleanTarget (Join-Path $_.FullName 'obj')
            }
        }
    }

    $objDir     = Join-Path $absProjectDir "obj"
    $assetsFile = Join-Path $objDir "project.assets.json"
    if (Test-Path -Path $assetsFile -PathType Leaf) {
        if ($PSCmdlet.ShouldProcess("File: project.assets.json", "Xóa file cache")) {
            try { Remove-Item -Path $assetsFile -Force -EA Stop
                  Write-Log "   🗑️  Đã xóa project.assets.json" $global:C_Gray } catch {}
        }
    }
    
    if (Test-Path -Path $objDir -PathType Container) {
        Get-ChildItem -Path $objDir -Recurse -File -EA SilentlyContinue |
            Where-Object { $_.Extension -in @('.nuspec', '.cache') -or
                           $_.Name -in @('project.nuget.cache', 'project.assets.json') } |
            Where-Object { Assert-SafePath $_.FullName } |
            ForEach-Object { 
                if ($PSCmdlet.ShouldProcess("File: $($_.Name)", "Xóa nuget cache file")) {
                    try { 
                        Remove-Item -Path $_.FullName -Force -EA Stop 
                    } catch {
                        Write-Warning "   ⚠️ Không thể xóa cache: $($_.Name) (Có thể đang bị IDE hoặc trình biên dịch khóa)"
                    } 
                }
            }
    }

    function Remove-SafeFolder {
        param([string]$FolderPath)
        if (-not (Test-Path -Path $FolderPath)) { return $true }
        if (-not (Assert-SafePath $FolderPath)) {
            Write-Warn "   ⛔ Bỏ qua path ngoài project: $FolderPath"; return $false
        }
        $item = Get-Item -Path $FolderPath -Force -EA SilentlyContinue
        if ($item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            Write-Log "   ⚠️  Gỡ symlink/junction: $(Split-Path $FolderPath -Leaf)" $global:C_Warn
            try {
                if ($global:OS -eq 'Windows') { & cmd.exe /c rmdir "`"$FolderPath`"" }
                else                          { & unlink $FolderPath }
                return (-not (Test-Path -Path $FolderPath))
            } catch { Write-Warn "   ⚠️  Không gỡ được: $FolderPath"; return $false }
        }
        $maxRetries = 3; $delaySec = 1
        for ($i = 0; $i -lt $maxRetries; $i++) {
            try { Remove-Item -Path $FolderPath -Recurse -Force -EA Stop; return $true }
            catch {
                if ($i -lt ($maxRetries - 1)) { Start-Sleep -Seconds $delaySec; $delaySec *= 2 }
                else { Write-Warn "   ⚠️  Bị khóa/thiếu quyền: $(Split-Path $FolderPath -Leaf)"; return $false }
            }
        }
        return $false
    }

    Write-Log "🧹 [SmartClean] Dọn cache..." $global:C_Info
    Write-Log "   📂 Root: $absProjectDir" $global:C_Gray
    $cleanedCount = 0; $failedCount = 0
    foreach ($folder in $targetsToClean) {
        $label = $folder.Replace($absProjectDir, '').TrimStart([System.IO.Path]::DirectorySeparatorChar,
                                                                [System.IO.Path]::AltDirectorySeparatorChar)
        if ($PSCmdlet.ShouldProcess("Thư mục: $folder", "Xóa vĩnh viễn")) {
            Write-Host "   🗑️  $label" -NoNewline -ForegroundColor DarkGray
            if (Remove-SafeFolder $folder) { Write-Host "  ✅" -ForegroundColor Green; $cleanedCount++ }
            else                           { Write-Host "  ⚠️" -ForegroundColor Yellow; $failedCount++ }
        }
    }
    
    if ($cleanedCount -eq 0 -and $failedCount -eq 0) {
        Write-Log "ℹ️  [SmartClean] Không có mục nào cần dọn." $global:C_Gray
    } elseif ($failedCount -eq 0) {
        Write-Log "✅ [SmartClean] Hoàn tất. Đã dọn $cleanedCount mục." $global:C_Succ
    } else {
        Write-Log "⚠️  [SmartClean] Hoàn tất với $failedCount lỗi." $global:C_Warn
    }

    if ($CleanOutputDir -and $OutputSubDir) {
        $rawOut = Join-Path $global:ScriptRoot "publish-output" $OutputSubDir
        if (Test-Path -Path $rawOut) {
            if ($PSCmdlet.ShouldProcess("Thư mục Output: $rawOut", "Dọn dẹp Artifact cũ")) {
                $artifactExtensions = @(
                    '.dll', '.exe', '.pdb', '.deps.json', '.runtimeconfig.json',
                    '.xml', '.staticwebassets.runtime.json', '.so', '.dylib',
                    '.apk', '.aab', '.msix', '.appxbundle', '.pkg', '.ipa',
                    '.wasm', '.blat', '.dat', '.map'
                )
                # 1. Xóa file artifact
                Get-ChildItem -Path $rawOut -Recurse -File -Force -EA SilentlyContinue |
                    Where-Object { $_.Extension -in $artifactExtensions } |
                    ForEach-Object {
                        try {
                            Remove-Item -Path $_.FullName -Force -EA Stop
                        } catch {
                            Write-Warning "   ⚠️ Không thể xóa artifact cũ: $($_.Name) (Hãy chắc chắn tiến trình đang không chạy)"
                        }
                    }

                # 2. Xóa các thư mục hệ thống của Web/Maui
                foreach ($folderName in @('wwwroot', 'bin', 'obj', '_framework')) {
                    $fp = Join-Path $rawOut $folderName
                    if (Test-Path -Path $fp) {
                        try {
                            Remove-Item -Path $fp -Recurse -Force -EA Stop
                        } catch {
                            Write-Warning "   ⚠️ Không thể xóa thư mục: $folderName"
                        }
                    }
                }
                
                # 3. Dọn dẹp thư mục rỗng
                Get-ChildItem -Path $rawOut -Directory -Recurse -Force -EA SilentlyContinue |
                    Where-Object { @(Get-ChildItem -Path $_.FullName -Force -EA SilentlyContinue).Count -eq 0 } |
                    ForEach-Object {
                        try {
                            Remove-Item -Path $_.FullName -Force -EA Stop
                        } catch {
                            Write-Host "   ⚠️ Không dọn được thư mục rỗng: $($_.Name)" -ForegroundColor DarkYellow
                        }
                    }

                Write-Log "   ✅ Đã dọn artifact output cũ tại: $OutputSubDir" $global:C_Gray
            }
        }
    }
}

Export-ModuleMember -Function Invoke-SmartClean