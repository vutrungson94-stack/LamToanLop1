Write-Host "🚀 Trigger GitHub Actions build APK..."

.\gh.exe workflow run "Build MAUI Android APK"

Write-Host "⏳ Đang đợi build hoàn tất..."
.\gh.exe run watch --exit-status

Write-Host "📦 Tải APK về máy..."
.\gh.exe run download --name android-apk --dir apk-output

Write-Host "✅ APK đã nằm trong thư mục apk-output"
