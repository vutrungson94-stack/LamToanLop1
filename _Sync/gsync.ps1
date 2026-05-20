#!/usr/bin/env pwsh
# ==============================================================================
# gsync.ps1 — Git Sync VIP PRO  |  Entry Point
# Hỗ trợ: MAUI · Blazor · ASP.NET · Angular · React · Vue · Python · Go · Java
# Chạy được: Windows · Linux · macOS  |  PowerShell 5.1+ / pwsh 7+
# ==============================================================================
# CÁCH DÙNG:
#   ./gsync.ps1                       – Chạy bình thường (có hỏi)
#   ./gsync.ps1 -Yes                  – Tự động "có" mọi câu hỏi (CI/CD)
#   ./gsync.ps1 -No                   – Tự động "không" mọi câu hỏi (dry-run)
#   ./gsync.ps1 -NonInteractive       – Dùng Default của từng prompt, không hỏi
#   ./gsync.ps1 -DryRun               – Chạy thử, không thay đổi gì
#   ./gsync.ps1 -ConfigPath ./my.json – Chỉ định config khác
#   ./gsync.ps1 -RepoUrl <url>        – Clone/init repo nếu chưa có
# ==============================================================================
[CmdletBinding()]
param(
    [switch]$NonInteractive,
    [switch]$Yes,
    [switch]$No,
    [switch]$DryRun,
    [string]$ConfigPath = (Join-Path (Get-Location) '.gitignore.config.json'),
    [string]$RepoUrl    = '',
    [string]$RemoteName = ''
)

# ── Validate tham số sớm (trước khi import module) ───────────────────────────
if ($Yes -and $No) {
    Write-Host '❌ Không thể dùng -Yes và -No cùng lúc.' -ForegroundColor Red
    exit 1
}

# ── Import module ─────────────────────────────────────────────────────────────
$moduleFile = Join-Path $PSScriptRoot 'gsync.module.psm1'
if (-not (Test-Path $moduleFile)) {
    Write-Host "❌ Không tìm thấy module: $moduleFile" -ForegroundColor Red
    Write-Host '   Đảm bảo gsync.module.psm1 nằm cùng thư mục với gsync.ps1.' -ForegroundColor Yellow
    exit 1
}

try {
    Import-Module $moduleFile -Force -ErrorAction Stop
} catch {
    Write-Host "❌ Không thể load module: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ── Gọi hàm chính ─────────────────────────────────────────────────────────────
$params = @{
    NonInteractive = $NonInteractive
    Yes            = $Yes
    No             = $No
    DryRun         = $DryRun
    ConfigPath     = $ConfigPath
}
if ($RepoUrl)    { $params['RepoUrl']    = $RepoUrl }
if ($RemoteName) { $params['RemoteName'] = $RemoteName }

Start-GSync @params