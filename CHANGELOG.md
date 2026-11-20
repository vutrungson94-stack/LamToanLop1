# Changelog

## [0.2.0] - 2026-11-20

### Thêm mới
- **TTS đa nguồn** (multi-source fallback): Edge TTS (48kHz/192kbps) → Google TTS (24kHz/64kbps) → FPT AI (cô giáo Ban Mai) → Viettel AI (cô giáo Quỳnh Anh) → Android TTS (thiết bị, miễn phí, offline)
- **Nút "CHỌN GIỌNG ĐỌC"** trên MenuPage — action sheet 6 lựa chọn, lưu preference, phát thử
- **Cache by ID** — SHA256 hash (text + version) = tên file cache. Mỗi câu hỏi có ID duy nhất
- **Android TTS fallback** — miễn phí, không cần key, offline. Khách hàng chỉ việc dùng
- **Splash screen background preload** — app mở nhanh (500ms), preload TTS chạy nền

### Thay đổi
- TTS priority: Edge TTS ưu tiên (chất lượng cao, khớp sample rate host 48kHz) trước Google TTS
- Volume TTS: Edge → 0.6, các nguồn khác → 0.5 (giảm clipping/distortion)
- SSML đơn giản hóa: bỏ prosody artificial (pitch/rate/volume) → giọng neural tự nhiên hơn
- Cache version: v5 → v8 (v8-multi-source-tts)
- PreCache song song: SemaphoreSlim(2) → SemaphoreSlim(4)
- FPT AI header: `api_key` → `api-key` (theo sample code FPT)
- Giọng FPT AI: `banmai` (cô giáo miền Bắc)
- Giọng Viettel AI: `hn-quynhanh` (cô giáo miền Bắc)

### Sửa lỗi
- Tiếng dè trên emulator: giảm volume + ưu tiên Edge TTS 48kHz (khớp host sample rate)
- Tiếng robot: đơn giản hóa SSML, bỏ prosody artificial
- App không mở (stuck splash): preload chuyển sang background, app navigate ngay
- Fast Deployment crash: cài APK đầy đủ thay vì fast deploy

## [0.1.0] - 2026-09-15

- Phiên bản đầu tiên
