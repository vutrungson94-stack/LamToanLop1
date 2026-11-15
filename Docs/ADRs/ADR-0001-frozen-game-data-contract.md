# ADR-0001 — GameData contract và đặt tên ảnh cute_* là đóng băng (frozen)

- **Status:** Accepted (2026-11-15)
- **Context:** Nhiều AI/người khác nhau tiếp tục sửa project. Các hợp đồng dữ liệu dễ bị "làm lỏng" bởi những thay đổi vô ý: đổi tên key GameData, đổi tên file ảnh, sửa scale động vật, thêm đuôi file khác.

## Decision

1. **Cấu trúc Class `GameData` trong `Models/MathEngine.cs` (section 1) đóng băng**: `List<KeyValuePair<string,string>> AnimalList`, `Dictionary<string,double> AnimalScales`, cùng các method `GetFarmMathLimit`, `StripCon`, `GetAllSpokenTexts`. Không đổi tên member/kiểu/thứ tự khai báo; chỉ sửa entry khi được yêu cầu rõ.
2. **Key trong GameData = tên file ảnh**: `"cute_<x>"` ↔ `Resources/Images/cute_<x>.webp`. (Trước 2026-11-15 là `convat_*`; toàn bộ đã rename sang `cute_*`, nội dung lấy từ `images cute/cute_*.svg` — mỗi SVG bọc PNG base64 — resize ≤512px, WebP q75 + `smartSubsample` + `effort 6`, quality đã kiểm tra mắt thường ở mức zoom 100%.)
3. **Gộp `convat_con_meo` vào `cute_meo_con`** (approved 2026-11-15): cả hai đều là "Con mèo" và nội dung ảnh giống hệt; list còn 73 entry, scale tương ứng 71 entry (`cute_su_tu` và `cute_con_cao` chưa từng có scale — dùng mặc định 1.0, giữ nguyên).
4. **Mọi nơi tạo ImageSource trong app** dùng chuỗi `$"{key}.webp"` (đuôi `.webp` là một phần của hợp đồng). Sửa thêm ảnh: **chỉ thay nội dung** file đã có, không thêm/xóa/đổi tên file ngoài quy trình ADR này.
5. `GetAllSpokenTexts()` là nguồn duy nhất của TTS pre-cache — entry AnimalList mới tự động được quét, không cần sửa tay TTS.

## Consequences

- Thêm/bớt con vật = víệc 4 bước (ADR này + `AGENTS.md` mục 2/4), không được làm rời rạc.
- App build/test phải đi qua vòng `gtest` → `gbuild` → verify emulator (AGENTS.md mục 3); không báo "xong" khi chưa qua đủ.
- Nếu muốn nâng cấp format (vd. SVG thật, `.png`), mở ADR mới thay vì sửa ADR này; Xóa/ghi đè key hiện hành mà không qua ADR là vi phạm hợp đồng.
