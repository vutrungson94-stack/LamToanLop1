# Hướng dẫn lấy key TTS — LamToanLop1

> Cập nhật 2026-11-21. Tiêu chí: **miễn phí** (dùng được từ app, không cần thẻ thanh toán khi dùng), **tiếng Việt tự nhiên**, **phù hợp đọc câu toán lớp 1**. Thông tin pricing có thể thay đổi — hãy xác nhận lại trước khi tích hợp.

## 1. Nguồn đang dùng trong app (`Services/GoogleTtsService.cs`)

| Nguồn | Key/token | Cách lấy | Hạn mức free | Lưu trong Preferences |
|---|---|---|---|---|
| **Edge TTS** (ưu tiên, neural 48 kHz) | ❌ Không cần | Dùng endpoint nội bộ `speech.platform.bing.com` + token browser công khai có sẵn trong code | Không giới hạn rõ ràng | — |
| **Google Dịch** (`translate.google.com/translate_tts?client=tw-ob`) | ❌ Không cần | Endpoint nội bộ của Google Translate | ~200 ký tự/request | — |
| **Viettel AI / VTCC.AI** (`hn-quynhanh`) | ✅ Token | Đăng ký tại `https://viettelai.vn` → đăng nhập → menu **Token** → copy token | **50.000 ký tự/tháng** (1 tháng đầu), không cần thẻ | `viettel_ai_api_key` |
| **Google Dịch — endpoint phụ** | ❌ Không cần | `https://translate.googleapis.com/translate_tts?ie=UTF-8&client=gtx&tl=vi&q=...` — dùng khi endpoint chính bị chặn/429 | ~200 ký tự/request | — |

> ⚠️ **Azure và Google Cloud đã bị gỡ bỏ (2026-11-22):** Azure từ chối free account nhưng authorize ~1 USD thẻ; Google Cloud yêu cầu billing mà thẻ nội địa bị từ chối. App chỉ dùng các nguồn **không cần key, không cần thẻ**.

### Về key trong app
Theo `AGENTS.md` mục 3.1, máy khách **không nhập/cấu hình gì**: token Viettel được nhúng sẵn (`VIETTEL_EMBEDDED_KEY`), app chạy ngay sau khi build. Không có màn hình Settings nhập key.

## 2. Các nền tảng đã khảo sát nhưng KHÔNG dùng

| # | Nền tảng | Lý do loại | Cách lấy key (nếu bạn vẫn muốn dùng) |
|---|---|---|---|
| 1 | Narakeet | Free account **cấm dùng Automation API**; API từ 6 USD/30 phút | Mua gói tại `narakeet.com/docs/pricing` → nhận `x-api-key` |
| 3 | Vbee | API là gói trả phí (~49.000đ/120.000 ký tự/tháng); gói Studio free **không có API** | `studio.vbee.vn` → Apps → Tạo ứng dụng → `App ID` + `token` (cần credit) |
| 4 | Narrator's Voice | App tiêu dùng, **không có API** | — |
| 6 | TTSFree.com | API chỉ cho gói **Premium** trả phí | `ttsfree.com/pricing` → mua Premium → `apikey` |
| 6b | ttsfree.online | Free, không key, nhưng giọng là wrapper Google → **robotic** | `api.ttsfree.online/sounds` (không cần key) |
| 7 | Tubekit.win | API cần gói **"Chuyên Nghiệp"** trở lên | `tubekit.win` → menu API KEY → Create |
| 9 | Free Text To Speech (nhiều site) | Giới hạn khắt khe, giọng wrapper/robot, không SLA | kiprio: `POST kiprio.com/v1/tts/demo` (5 req/phút); tts.ai: 5.000 ký tự/ngày/IP |
| 12 | Notevibes | API chỉ mở ở gói **Pro (~40 USD/tháng)** | `notevibes.com/developer/docs/tts` → `Authorization: Bearer nvb_<key>` |
| 15 | Natural Readers | App/web cá nhân, **cấm redistribute audio**; không API công khai ổn định | — |
| 16 | Wideo | Công cụ tạo video, **không phải dịch vụ TTS** | — |
| 17 | ReadSpeaker | Enterprise, **không có free plan** | `readspeaker.com/pricing` → hợp đồng/license |
| 18 | Google Lens | Nhận diện hình ảnh/OCR, **không tạo giọng nói** | — |
| 19 | Voice Aloud Reader | App Android đọc bằng TTS engine có sẵn, **không có API** | — |
| 21 | Talk FREE | App Android, **không có API** | — |
| 22 | T2S: Text to Voice | App Android, **không có API** | — |

## 3. Kết luận
- **Free thật + tự nhiên + dùng ngay:** Edge TTS → Google Dịch → Viettel AI → Android TTS (đã có trong app, không cần key mới).
- **Đã thử nhưng gỡ bỏ:** Azure (từ chối free account + authorize thẻ) và Google Cloud (yêu cầu billing, thẻ nội địa bị từ chối) — xem NOTE ở đầu file. Không nên quay lại các nguồn này.
- Không nên tích hợp các nguồn trả phí hoặc app tiêu dùng vào app học toán lớp 1.
