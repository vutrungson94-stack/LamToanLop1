Write-Host "=============================="
Write-Host "  MAUI Android APK Builder  "
Write-Host "=============================="

# Kiểm tra dotnet
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Host "❌ dotnet SDK chưa được cài"
    exit 1
}

# Tìm csproj
$csproj = Get-ChildItem -Filter *.csproj | Select-Object -First 1
if (-not $csproj) {
    Write-Host "❌ Không tìm thấy file .csproj"
    exit 1
}
Write-Host "📄 Project: $($csproj.Name)"

# ---- PHẦN SỬA LỖI QUAN TRỌNG ----
[xml]$projXml = Get-Content $csproj.FullName

$allFrameworks = @()
foreach ($pg in $projXml.Project.PropertyGroup) {
    if ($pg.TargetFramework) { $allFrameworks += $pg.TargetFramework }
    if ($pg.TargetFrameworks) { $allFrameworks += ($pg.TargetFrameworks -split ';') }
}

$allFrameworks = $allFrameworks | ForEach-Object { $_.Trim() } |
    Where-Object { $_ } | Select-Object -Unique

$androidFramework = $allFrameworks | Where-Object { $_ -match "android" } | Select-Object -First 1
if (-not $androidFramework) {
    Write-Host "❌ Không tìm thấy TargetFramework Android"
    Write-Host "👉 Các framework tìm được:"
    $allFrameworks | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "✅ Android TargetFramework: $androidFramework"
# --------------------------------

# Build APK
Write-Host "🔧 Đang build APK..."
dotnet publish `
    $csproj.FullName `
    -f $androidFramework `
    -c Release `
    -p:AndroidPackageFormat=apk `
    -p:PublishTrimmed=true

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Build APK thất bại"
    exit 1
}

$apk = Get-ChildItem -Recurse -Filter *.apk bin\Release | Select-Object -First 1
Write-Host "✅ Build thành công"
Write-Host "📦 APK: $($apk.FullName)"
