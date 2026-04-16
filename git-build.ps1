Write-Host "🚀 Trigger GitHub Actions build APK..."

.\gh.exe workflow run "Build MAUI Android APK"

Write-Host "⏳ Đang đợi build hoàn tất..."
.\gh.exe run watch --exit-status

.\gh.exe run download --name android-apk --dir apk-output

if ($LASTEXITCODE -ne 0) {
    Write-Error "❌ Không tải được APK vì build CI thất bại"
    exit 1
}

Write-Host "✅ APK đã nằm trong thư mục apk-output"
