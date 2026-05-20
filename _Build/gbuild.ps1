#!/usr/bin/env pwsh
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$GitHub,
    [switch]$NonInteractive,
    [switch]$Incremental,
    [switch]$Clean
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Global:StartTime = Get-Date

# QUAN TRỌNG: ScriptRoot là thư mục LÀM VIỆC HIỆN TẠI (nơi bạn đang đứng)
$global:ScriptRoot = (Get-Location).Path

$modulePath = Join-Path $PSScriptRoot "gbuild.module.psm1"
if (-not (Test-Path $modulePath)) {
    Write-Error "Không tìm thấy gbuild.module.psm1 tại $modulePath"
    exit 1
}
Import-Module -Name $modulePath -Force -Global

Start-GBuild -GitHub:$GitHub -NonInteractive:$NonInteractive -Incremental:$Incremental -Clean:$Clean