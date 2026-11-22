# Changelog

## [0.2.2] - 2026-11-22

### Thay đổi
- **Ưu tiên giọng thật, không robot**: thứ tự fallback đổi thành Edge TTS (neural) → Viettel AI → Google Dịch (chỉ dự phòng) → Android TTS. Cache tách thành `<hash>.mp3` (giọng thật) và `<hash>_fb.mp3` (giọng máy) — cache giọng máy không chặn việc tải lại giọng thật. `CACHE_VERSION` v8 → `v9-natural-voice` để xóa cache giọng robot cũ.
- **Gỡ Azure và Google Cloud TTS**: Azure từ chối free account nhưng authorize ~1 USD thẻ; Google Cloud yêu cầu billing nhưng thẻ nội địa bị từ chối. Thay bằng endpoint phụ của Google Dịch (`translate.googleapis.com?client=gtx`, không key/thẻ, đã kiểm chứng trả MP3 thật).
- **Không cần cấu hình trên máy khách**: token Viettel nhúng sẵn (`VIETTEL_EMBEDDED_KEY`), bỏ ô nhập key. `AGENTS.md` mục 3.1 ghi nhận hardcode được chấp nhận; gate L5 không nới.

## [0.2.1] - 2026-11-21

### Thay đổi
- **Gỡ FPT AI TTS**: họ ngừng cung cấp API cho tài khoản cá nhân. Fallback giờ là Edge TTS → Google TTS → Viettel AI → Android TTS. Pref cũ `"fpt"` tự đổi về `"auto"`; giữ nguyên `CACHE_VERSION` để không ép tải lại cache.
- **Tối ưu tốc độ load**: splash navigate sau 300ms, trì hoãn preload TTS 2s để MenuPage render trước; bỏ progress dispatch sau khi rời splash; giảm báo tiến độ theo bước 5%; `TryRecover` chỉ xóa file tạm `*.part`/`*.tmp` thay vì toàn bộ cache; sửa 3 tham chiếu ảnh `.png` → `.webp` trong GamePage.
- **CI L5 enterprise**: thêm job `l5-gates` (6 gate: compile, secret scan, vulnerable packages, SBOM+policy, provenance, compliance) — mọi job build/release phải chờ gate xanh. Cấu hình nằm trong workflow, không thêm file config của tool vào project (các project độc lập, không chứa nhau).

## [0.2.0] - 2026-11-20

### Thêm mới
- **TTS đa nguồn** (multi-source fallback): Edge TTS (48kHz/192kbps) → Google TTS (24kHz/64kbps) → Viettel AI (cô giáo Quỳnh Anh) → Android TTS (thiết bị, miễn phí, offline)
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
- Giọng Viettel AI: `hn-quynhanh` (cô giáo miền Bắc)

### Sửa lỗi
- Tiếng dè trên emulator: giảm volume + ưu tiên Edge TTS 48kHz (khớp host sample rate)
- Tiếng robot: đơn giản hóa SSML, bỏ prosody artificial
- App không mở (stuck splash): preload chuyển sang background, app navigate ngay
- Fast Deployment crash: cài APK đầy đủ thay vì fast deploy

## [0.1.0] - 2026-09-15

- Phiên bản đầu tiên
