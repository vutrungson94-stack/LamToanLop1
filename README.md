# Bé làm toán lớp 1

Ứng dụng học toán cho học sinh lớp 1 Việt Nam. .NET 10 + .NET MAUI 10.

## Tính năng
- Học toán: số, phép toán, sắp xếp số, so sánh
- Khám phá động vật (73 con vật)
- Giọng đọc TTS đa nguồn (Edge TTS, Google TTS, FPT AI, Viettel AI, Android TTS) với cache offline
- Chọn giọng đọc trên MenuPage
- Preload TTS ở background — app mở nhanh

## Quy trình cho AI / cộng tác viên
Đọc [AGENTS.md](AGENTS.md) trước khi sửa code. Workflow chuẩn: `_Tests` → `_Build` → `_Sync` (3 hệ thống trong `D:\HOC_TAP\backup`).

## Build
```powershell
pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "D:\HOC_TAP\backup\_Tests\gtest.ps1" -Project "." -NonInteractive
pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "D:\HOC_TAP\backup\_Build\gbuild.ps1" -Project "." -NonInteractive -Target 1
pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "D:\HOC_TAP\backup\_Sync\gsync.ps1" -Project "." -Yes -NonInteractive
```
