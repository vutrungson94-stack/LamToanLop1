# Bé làm toán lớp 1

Ứng dụng học toán cho học sinh lớp 1 Việt Nam. .NET 10 + .NET MAUI 10.

## Tính năng
- Học toán: số, phép toán, sắp xếp số, so sánh
- Khám phá động vật (73 con vật)
- Giọng đọc TTS đa nguồn, **ưu tiên giọng tự nhiên**: Edge TTS (neural) → Viettel AI → Google Dịch (dự phòng) → Android TTS. Cache offline tách riêng giọng thật / giọng dự phòng
- Máy khách **chỉ cài là dùng** — không cần nhập key/token (AGENTS.md mục 3.1)
- Chọn giọng đọc trên MenuPage; preload TTS chạy background sau 2s — app mở nhanh
- CI có job `l5-gates` (6 gate) — artifact/release chỉ phát hành khi gate xanh

## Quy trình cho AI / cộng tác viên
Đọc [AGENTS.md](AGENTS.md) trước khi sửa code. Workflow chuẩn: `_Tests` → `_Build` → `_Sync` (3 hệ thống trong `D:\HOC_TAP\backup`).

## Build
```powershell
pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "D:\HOC_TAP\backup\_Tests\gtest.ps1" -Project "." -NonInteractive
pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "D:\HOC_TAP\backup\_Build\gbuild.ps1" -Project "." -NonInteractive -Target 1
pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "D:\HOC_TAP\backup\_Sync\gsync.ps1" -Project "." -Yes -NonInteractive
```
