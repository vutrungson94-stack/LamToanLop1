Write-Host "=============================="
Write-Host "  MAUI Android APK Builder  "
Write-Host "=============================="

# 1. Kiểm tra dotnet
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Host "❌ dotnet SDK chưa được cài"
    exit 1
}

# 2. Tìm file csproj
$csproj = Get-ChildItem -Filter *.csproj | Select-Object -First 1
if (-not $csproj) {
    Write-Host "❌ Không tìm thấy file .csproj"
    exit 1
}

Write-Host "📄 Sử dụng project: $($csproj.Name)"

# 3. Đọc TargetFramework Android từ csproj
[xml]$projXml = Get-Content $csproj.FullName

$frameworkNode = $projXml.Project.PropertyGroup.TargetFramework
if (-not $frameworkNode) {
    $frameworkNode = $projXml.Project.PropertyGroup.TargetFrameworks
}

if (-not $frameworkNode) {
    Write-Host "❌ Không tìm thấy TargetFramework trong csproj"
    exit 1
}

$androidFramework = $frameworkNode -split ";" | Where-Object { $_ -match "android" } | Select-Object -First 1

if (-not $androidFramework) {
    Write-Host "❌ Không tìm thấy TargetFramework Android"
    exit 1
}

Write-Host "✅ Android TargetFramework: $androidFramework"

# 4. Build APK
Write-Host "🔧 Đang build APK (Release)..."

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

# 5. Tìm APK
$apk = Get-ChildItem -Recurse -Filter *.apk bin\Release -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $apk) {
    Write-Host "❌ Không tìm thấy file APK"
    exit 1
}

Write-Host "✅ Build APK thành công 🎉"
Write-Host "📦 APK: $($apk.FullName)"
