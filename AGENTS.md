# AGENTS.md — WORKFLOW CHO AI (LamToanLop1)
> Đọc file này TRƯỚC KHI sửa bất kỳ dòng code nào của project.
> Mục đích: mọi AI (OpenCode, Roo, Copilot, Claude, Gemini...) sửa project này đều đi đúng hướng, không phá vỡ các hợp đồng dữ liệu, và giữ được các gate L5 của chuỗi công cụ SonVuDev (`_Build` / `_Tests` / `_Sync`).

---

## 0. Dự án là gì

- **Tên app:** "Bé làm toán lớp 1" (ApplicationTitle) — ứng dụng học toán cho **học sinh lớp 1 Việt Nam**.
- **Package:** `com.vutrungson.lamtoanlop1` (`Platforms/Android/AndroidManifest.xml`).
- **Stack:** .NET 10 + .NET MAUI 10 (`net10.0-android` chính; `net10.0-windows10.0.19041.0` chỉ khi build trên Windows), CommunityToolkit.Mvvm 8.4.0, Plugin.Maui.Audio 4.0.0.
- **SDK:** `global.json` pin `10.0.300` (`rollForward: latestMajor`).
- **Repo:** git, branch mặc định `main`. Có sẵn nhiều thay đổi **chưa commit từ trước** (GamePage.xaml.cs, MathEngine.cs, MauiProgram.cs...) — **KHÔNG revert, KHÔNG tự ý commit/push khi chưa được yêu cầu.**
- Ngôn ngữ UI/comment/code: **tiếng Việt** — giữ nguyên.
- Read: `Docs/L5-Assessment.md` + `Docs/ADRs/ADR-0001-frozen-game-data-contract.md` — đánh giá L5 và hợp đồng frozen của GameData/ảnh.

## 1. Bản đồ thư mục & quyền sở hữu file

| Đường dẫn | Vai trò | Lưu ý khi sửa |
|---|---|---|
| `Models/MathEngine.cs` | **Toàn bộ** logic sinh câu hỏi (section 4–6) + **Class game data `GameData` (section 1) — FROZEN** | Sửa đúng vùng được giao. Section 2/3 (interface, factory) chỉ đụng khi được yêu cầu rõ |
| `Pages/GamePage.*` | Màn chơi chính (1000+ dòng) — ảnh load qua `GetImageSourceCachedAsync` | Đọc kỹ trước khi sửa |
| `Pages/AnimalPage.*` | Trang khám phá động vật (AnimalImage 300dp) | Ảnh động vật hiện chính ở đây |
| `Services/GoogleTtsService.cs` | TTS đa nguồn (Edge, Google, Viettel AI, Android TTS) + pre-cache + cache by ID (SHA256) | Thêm câu đọc mới → thêm vào `GameData.GetAllSpokenTexts()`; thêm nguồn TTS → thêm vào fallback chain |


| `Services/SelfHealingService.cs` | **L5 self-healing của app**: crash log + count + retry | Giữ; không tháo niềng |
| `Services/SoundService.cs`, `Services/ITtsService.cs` | Âm thanh (null-safe) | Null-safety là cố ý |
| `Helpers/ResponsiveHelper.cs` | Layout responsive | Dùng helper thay vì số cứng |
| `Resources/Images/` | `cute_*.webp` (con vật — FROZEN tên), `hinhnen_*`, `anhdong_*`, `bieutuong_*` | Chỉ `cute_*.webp` phục vụ game động vật; chỉ thay NỘI DUNG |
| `Resources/Raw/` | `tieng_phao_no.mp3`, `tieng_vo_tay.mp3`, `AboutAssets.txt` | |
| `Resources/Fonts/`, `Resources/Styles/` | Font + Colors/Styles | |
| `Platforms/Android/` | MainActivity, AudioFocusHelper, AndroidManifest | |
| `Docs/` | **L5-Assessment.md**, `ADRs/` | Sửa docs khi thay đổi quyết định kiến trúc |
| `build-reports/` | **Bằng chứng L5 của lần build gần nhất** (sbom, compliance-report, security-scan, car-records, ...) | Do `gbuild` tự sinh — đọc, không sửa tay |
| ~gbuild.ps1~, ~gsync.ps1~ | **DA XOA khoi repo 2026-11-15** (chu project yeu cau: project khong duoc chua file build; xem muc 8) | Tool build/test/sync LUON nam tai D:\HOC_TAP\backup\_Build / _Tests / _Sync. Khong recreate cac file nay vao project |
| `ltl1-upload-key.jks` | **Keystore release — TUYỆT ĐỐI KHÔNG đụng, KHÔNG đọc, KHÔNG log, KHÔNG xóa** | |
| `.gitignore.config.json` | Config gsync | `.gitignore` bị tool tự-append patterns là chuyện bình thường (2026-11-15 gtest thêm `node_modules/ build-reports/ logs/`) |
| `Docs/L5-Assessment.md`, `AGENTS.md`, `WORKFLOW.md` | Workflow + đánh giá | Cập nhật cùng với thay đổi gate/hợp đồng |

## 2. CÁC HỢP ĐỒNG BẤT BIẾN (invariants)

1. **Class game data `GameData` trong `Models/MathEngine.cs` (section 1) GIỮ NGUYÊN CẤU TRÚC** (ADR-0001): `List<KeyValuePair<string,string>> AnimalList`, `Dictionary<string,double> AnimalScales`, `ShapeList`, `BlockShapeList`, `GetFarmMathLimit`, `StripCon`, `GetAllSpokenTexts`.
   - Không đổi tên class/member/key, không đổi kiểu dữ liệu, không tách file.
   - Thêm/sửa entry chỉ khi được yêu cầu rõ, theo đúng 4 bước: (a) ảnh `cute_<key>.webp`, (b) entry `AnimalList`, (c) scale `AnimalScales`, (d) TTS tự quét qua `GetAllSpokenTexts()` — không sửa tay.
   - `cute_su_tu` và `cute_con_cao` **chưa từng có** trong `AnimalScales` (dùng fallback 1.0 trong `GenerateRandomAnimals`) — giữ nguyên, đừng tự thêm.
2. **Đặt tên ảnh = hợp đồng**: `GameData.AnimalList[].Key` ↔ tên file `Resources/Images/cute_*.webp` ↔ chuỗi `$"{key}.webp"` trong code (AnimalPage.xaml.cs, GamePage.xaml.cs). **Chỉ thay NỘI DUNG file; không đổi tên, không đổi đuôi, không xóa file, không thêm đuôi khác.**
   - `convat_*` **không còn tồn tại** (rename hoàn tất 2026-11-15, xem PHỤ LỤC A). Nếu gặp tham chiếu `convat_*` trong code/docs — đó là lỗi thời, sửa thành `cute_*`.
   - Gộp `convat_con_meo` vào `cute_meo_con` (cả hai đều là "Con mèo", ảnh giống hệt — đã duyệt 2026-11-15). List giờ **73 entry**.
3. **App chỉ dạy TOÁN LỚP 1** — semester 1 (phạm vi 10/20), semester 2 (20/50/100) như `QuestionFactory.Create`. Không tự ý thêm dạng bài lớp 2+.
4. **`ImageSource.FromFile` trong app này nhận tên file CÓ đuôi** — khác convention MAUI chuẩn. Đừng "sửa" chỗ này.
5. **`GetAllSpokenTexts()`** là nguồn duy nhất cho pre-cache TTS offline.
6. **Không tạo project test giả** để "gỡ đỏ" gtest. Project **không có** `*.Tests.csproj` — gtest validation PASS + "Skipping dotnet test" (exit 0) là kết quả mong đợi.
7. **Không sửa** nội dung ảnh không phải `cute_*`/`convat_*` (`hinhnen_*`, `anhdong_*`, `bieutuong_*`).
8. **Không nới gate L5 để cho xanh** (xem mục 8). Gate đỏ → sửa nguyên nhân hoặc báo lại; tuyệt đối không đổi policy thành `warn|skip` chỉ vì muốn qua.

## 3. QUY TRÌNH CHUẨN — `_Tests` → `_Build` → `_Sync` (bắt buộc cho MỖI LẦN SỬA)

> Workflow này áp dụng cho **mọi lần sửa** của project (nhỏ nhất cũng phải qua đủ 3 gate).
> Ba bước `_Tests` → `_Build` → `_Sync` đều bắt buộc — **không** được báo "xong" khi thiếu hay bỏ qua bước nào.
> 3 hệ thống build/test/sync luôn nằm trong thư mục `D:\HOC_TAP\backup` (`_Tests`, `_Build`, `_Sync`), **KHÔNG** recreate vào project.

```
PHÂN TÍCH → SỬA NHỎ NHẤT → _Tests (ALL PASS) → _Build (L5 xanh) → _Sync → BÁO CÁO
```

1. **Phân tích:** đọc file liên quan trước khi sửa. `git status --short` để biết trạng thái nền (project có nhiều thay đổi cũ chưa commit — không đụng vào ngoài phạm vi).
2. **Sửa nhỏ nhất có thể:** đúng phạm vi được giao; không refactor/format lan man.
3. **`_Tests` (gtest) — ALL PASS mới được đi tiếp:**
   ```powershell
   pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "D:\HOC_TAP\backup\_Tests\gtest.ps1" -Project "D:\HOC_TAP\Android\LamToanLop1\LamToanLop1" -NonInteractive
   ```
   - Bắt buộc in ra `Summary: 6/6 passed, 0 failed` và `=== Exit code: 0 ===`.
   - (Lưu ý khi project sau này có `*.Tests.csproj`: `dotnet test` sẽ chạy thật và cũng phải xanh.)
   - Bước này PHẢI XANH trước khi gọi `_Build` — không có ngoại lệ.
4. **`_Build` (gbuild) — toàn bộ gate L5 xanh (mục 8):** Security (3 phase) + Supply chain/SBOM + SAST + **Policy check**. Nếu một gate đỏ → sửa nguyên nhân (không nới gate), rồi chạy lại `_Tests` → `_Build`.
   - Build nhanh cho mỗi lần sửa UI/code (mặc định, dùng `-Target 1`):
   ```powershell
   pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "D:\HOC_TAP\backup\_Build\gbuild.ps1" -Project "D:\HOC_TAP\Android\LamToanLop1\LamToanLop1" -NonInteractive -Target 1
   ```
   ⚠️ `-Target 1` có thể KHÔNG cài APK lên emulator dù log báo "Deploying app to device...". Sau mỗi lần Target 1 **kiểm chứng bắt buộc**:
   ```powershell
   & "C:\Program Files\Android\platform-tools\adb.exe" -s emulator-5554 shell dumpsys package com.vutrungson.lamtoanlop1 | Select-String lastUpdateTime
   ```
   Nếu `lastUpdateTime` không khớp thời điểm build → deploy thủ công (đã xác nhận 2026-11-16 00:15:51):
   ```powershell
   dotnet build "D:\HOC_TAP\Android\LamToanLop1\LamToanLop1\LamToanLop1.csproj" -t:Run -f net10.0-android -p:AndroidSdkDirectory="C:\Program Files\Android" -p:JavaSdkDirectory="C:\Program Files\Microsoft\jdk-21.0.11.10-hotspot"
   ```
   - Build đầy đủ: `-Incremental` (giống gate, chậm hơn). `-Target 1` chỉ thay bước đóng gói/cài — gate L5 vẫn chạy đủ.
   - APK: `publish-output\apk\com.vutrungson.lamtoanlop1-Signed.apk` (gbuild cố deploy + mở app trên emulator đang kết nối, nhưng luôn kiểm `lastUpdateTime`).
5. **`_Sync` (gsync) — đồng bộ repo, chỉ chạy khi 3+4 đã xanh:**
   ```powershell
   pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "D:\HOC_TAP\backup\_Sync\gsync.ps1" -Project "D:\HOC_TAP\Android\LamToanLop1\LamToanLop1" -Yes -NonInteractive
   ```
   - Gsync tự phát hiện thay đổi, stage + commit + push lên remote `origin` theo `.gitignore.config.json`.
   - **Gsync stage MỌI thay đổi trong worktree** — gồm cả thay đổi cũ chưa commit (chủ project đã chốt workflow này); file nhạy cảm (`*.jks`, `*.key`, `.env*`) và file lớn bị chặn theo config (`.gitignore` đã thêm `release/`, `.gbuildcache/`, `.gbuild-state.gbuildstate*`).
   - Nên `-DryRun` trước khi sync thật nếu batch thay đổi lớn hoặc vừa sửa config sync.
   - Nếu gate này FAIL (conflict / auth / large file / sensitive file) → xử lý theo đúng thông báo của gsync; **không** xóa file, **không** force push, **không** bỏ qua và báo "xong".
6. **VERIFY emulator** (cho thay đổi ảnh/UI/gameplay — song song với sync, không thay thế `_Sync`):
   ```powershell
   Start-Process "C:\Users\TSV\Desktop\Android Emulator - Pixel 8 (API 37).lnk"
   $adb = "C:\Program Files\Android\platform-tools\adb.exe"
   & $adb wait-for-device; do { Start-Sleep 5 } until ((& $adb shell getprop sys.boot_completed) -match '1')
   & $adb install -r "<apk mới nhất>"
   & $adb shell monkey -p com.vutrungson.lamtoanlop1 -c android.intent.category.LAUNCHER 1
    # KHÔNG dùng exec-out rồi pipe ra file — PowerShell mã hóa lại bytes (xác nhận 2026-11-15)
    & $adb -s emulator-5554 shell screencap -p /sdcard/verify.png
    & $adb -s emulator-5554 pull /sdcard/verify.png "$env:TEMP\ltl1_verify.png"
   ```
   Boot lần đầu mất 1–3 phút. Nút trên màn hình lấy bounds qua `uiautomator dump` rồi `input tap <x> <y>` (ví dụ nút "KHÁM PHÁ ĐỘNG VẬT": bounds `[121,1311][961,1507]` → tap `541 1409`).
   - **Kiểm tra chất lượng âm thanh:** sau khi cài xong, mở app vào màn có giọng đọc (số/con vật/câu hỏi), người dùng **ghi âm chất lượng âm thanh bằng phần mềm máy tính** (ví dụ Audacity) khi lắng nghe trên emulator/máy thật, và so sánh trước/sau khi giảm volume TTS (`GoogleTtsService.cs` 0.9 → 0.75). AI CLI không có thiết bị âm thanh vật lý nên không tự thực hiện bước ghi âm này.
7. **BÁO CÁO:** `git status --short`/`git diff --stat`, kết quả `_Tests` + `_Build` (kèm đường dẫn APK + gate nào đỏ nếu có) + kết quả `_Sync` (commit/push OK hay lỗi gì) + screenshot verify. **Không báo "xong" khi chưa qua đủ bước 3→5.**

### 3.1 Hardcode được chấp nhận (quy định 2026-11-22)
- **Máy khách chỉ việc dùng**: APK sau khi build phải chạy ngay, **không bắt người dùng nhập key/token/cấu hình gì**. Vì vậy các giá trị không thể loại bỏ được phép hardcode trong source.
- Trường hợp hiện tại: `VIETTEL_EMBEDDED_KEY` trong `Services/GoogleTtsService.cs` — token dùng chung, nhúng sẵn để mọi bản cài đều đọc được giọng Viettel. Ghi rõ lý do ngay tại chỗ khai báo.
- Gate L5 **không bị nới**: secret scan vẫn chạy đủ. Nếu scanner báo finding cho hardcode đã được chấp nhận, xử lý bằng **exception có tên + lý do cụ thể** trong cấu hình scan, **không** đổi policy thành `warn|skip` và không tắt gate.
- Không lạm dụng: chỉ các giá trị thực sự cần thiết để app chạy ngay mới được hardcode; mọi secret khác vẫn phải dùng `${env:…}`/Preferences.

## 4. Thủ tục thay/nén ảnh con vật (trạng thái hiện tại sau 2026-11-15)

- **Nguồn sự thật:** `D:\HOC_TAP\Android\HinhAnh\LamToanLop1\cac con vat\images cute\cute_*.svg` (73 file) — mỗi SVG **bọc một PNG base64** (không có path vector).
- **Cách tạo file đúng:** giải mã base64 lấy PNG gốc → `sharp` resize `{ width: 512, height: 512, fit: 'inside', withoutEnlargement: true }` → `.webp({ quality: 75, alphaQuality: 100 (mặc định), effort: 6, smartSubsample: true })` với alpha giữ nguyên. Tổng dung lượng 73 ảnh: ~1.87 MB (2026-11-15).
- **Luôn re-encode từ PNG gốc trong SVG, KHÔNG nén lại từ .webp hiện có** (tránh generation loss).
- **Kiểm tra chất lượng khi đổi quality:** render ra ảnh so sánh (như `logs\` hoặc temp) và xem mắt ở 100% zoom; mắt người là gate cuối, không chỉ số KB.
- Máy này **không có** Python/cairosvg/ImageMagick/Inkscape — dùng Node + `sharp` (`npm install sharp` trong thư mục tạm).

## 5. Lỗi thường gặp (gotchas)

- **Ảnh không hiện / key sai:** kiểm tra từng ký tự giữa key GameData và tên file (`cute_huou_sao` giờ đã đúng chính tả — typo `huu_sao` biến mất khi rename). Code `.ToLower()` key trước khi load.
- Cac file tool build (gbuild.ps1, gsync.ps1, .gbuildcache/, .gbuild-state.gbuildstate*, .sdkcache.json) da bi xoa khoi project tu 2026-11-15 theo yeu cau chu project; tool dung chung o D:\HOC_TAP\backup\_Build / _Tests / _Sync. _Build tu sinh .gbuild-state.gbuildstate*/.gbuildcache/ khi chay - chung da duoc them vao .gitignore; xoa chung khi khong con process build chay.
- **Artifacts của tool không còn nằm trong project (từ 2026-11-15):** `.gbuildcache/` và `.gbuild-state.gbuildstate` không sinh trong project nữa — bản `_Build` trong `D:\HOC_TAP\backup\_Build` đã được sửa để đặt runtime data per-project vào thư mục tool tree: `.gbuildcache/<projectKey>` và `.gbuildstate/<projectKey>` (projectKey = tên thư mục + SHA256 của path tuyệt đối). Muốn quay về layout cũ: set `build.cacheDirectory` / `paths.stateDirectory` = `project` trong `gbuild.config.json` (constant BuildConstants `CacheDir` / `StateDirectory`).
- **Emulator Pixel 8 (`Pixel8Launcher`):** audio đã được bật lại từ 2026-11-15 (trước đó `-no-audio` khiến mọi app trên emulator im — root cause của "toàn bộ project bị tắt tiếng"). Đừng khôi phục `-no-audio` nếu không được chủ project yêu cầu.
- **Audio "dè" trên emulator — nguyên nhân ĐÃ RÕ (2026-11-22, đối chiếu source AOSP):** KHÔNG phải app/file MP3, KHÔNG phải emulator bản 37 tự đổi backend (code audio `audio.c`/`winaudio.c`/`dsoundaudio.c` giống hệt bản 34→37; HAL goldfish & audio policy giống hệt API 15→17). Chuỗi gây dè: MP3/Guest **48 kHz** → HAL goldfish 48 kHz → **QEMU fixed DAC 44,1 kHz / S16** (`conf.fixed_out`, comment *"AEMU can only operate on a fixed configuration"*) → DirectSound/WinMM → **Windows endpoint**. `dumpsys media.audio_flinger underrun=0` **không thấy** được đoạn nằm dưới AudioFlinger. Thêm nữa `hw.audioInput=yes` (micro host bật) làm endpoint đổi duplex (Google cảnh báo giảm chất lượng). ⚠️ **Thử nghiệm thực tế 2026-11-22:** ép `QEMU_AUDIO_DAC_FIXED_FREQ=48000` làm tiếng **dè hơn** → đã **bỏ override**, quay về DAC mặc định 44,1 kHz/S16; Windows endpoint đặt **16-bit / 44100 Hz** để khớp (chỉ còn 1 lần resample do QEMU làm). Không dùng 24-bit.
- **Cấu hình máy ảo đã tối ưu cho máy này (2026-11-22):** `C:\Users\TSV\AndroidLauncher\Pixel8Launcher\Program.cs` (shortcut Desktop) — **KHÔNG override DAC QEMU** (thử ép 48 kHz thấy dè hơn); launcher tự kill emulator offline + xoá `*.lock` khi mở lại; dùng `-no-snapshot-load -no-snapshot-save` (snapshot hỏng do kill cứng là nguyên nhân shortcut treo). `Pixel_8_API_37.avd/config.ini`: `hw.audioInput=no`, giữ `hw.audioOutput=yes`. Windows Sound → Advanced → Default Format = **16 bit, 44100 Hz**, tắt **Enable audio enhancements**. Verify: 2 lần mở shortcut boot 30s/25s, không treo.
- **Không dùng flag `-audio <backend>`** cho Android Emulator (QEMU2 fork đã deprecated) và **không override `QEMU_AUDIO_DAC_FIXED_*`** (thử nghiệm làm dè hơn). Không khôi phục `-no-audio`.
- **TTS đa nguồn (cập nhật 2026-11-22) — ƯU TIÊN GIỌNG THẬT, KHÔNG ROBOT:** thứ tự Edge TTS (neural 48 kHz) → Viettel AI (cô giáo Quỳnh Anh, giọng tự nhiên) → Google Dịch (endpoint chính + phụ, **chỉ dự phòng**) → Android TTS. Cache được **tách 2 loại**: `<hash>.mp3` = giọng thật, `<hash>_fb.mp3` = giọng máy — cache giọng máy **không bao giờ chặn** việc tải lại giọng thật. `CACHE_VERSION = v9-natural-voice` (đổi từ v8 để xóa cache giọng robot cũ). Nút "CHỌN GIỌNG ĐỌC" trên MenuPage cho phép chọn giọng.
- **Azure / Google Cloud đã gỡ bỏ (2026-11-22):** Azure từ chối free account nhưng authorize ~1 USD thẻ; Google Cloud yêu cầu billing mà thẻ nội địa bị từ chối. **Không thêm lại** các nguồn cần thẻ/key — máy khách chỉ cài là dùng.
- **FPT AI đã bị gỡ (2026-11-21):** họ ngừng cung cấp API cho tài khoản cá nhân. Không khôi phục nguồn này; pref cũ `"fpt"` được tự đổi về `"auto"`.
- **Viettel AI voice:** `hn-quynhanh` (cô giáo miền Bắc). Token nhúng sẵn `VIETTEL_EMBEDDED_KEY` → máy khách không nhập gì (Preferences "viettel_ai_api_key" chỉ dùng để override).
- **Volume TTS (giảm 2026-11-22 để hạn chế tiếng dè trên emulator):** Edge TTS → 0.5, các nguồn khác → 0.45. SoundService volume 0.7. ⚠️ Tiếng "dè" trên emulator chủ yếu do đường audio host (QEMU → WASAPI) resample 48 kHz — không phải lỗi file; phải **ghi âm trên máy thật** để đánh giá đúng (xem mục 6).
- **SSML:** Đơn giản hóa — bỏ prosody artificial (pitch/rate/volume). Để neural voice tự xử lý intonation tự nhiên.
- **Splash screen:** app navigate sau 300ms; preload TTS chạy background sau đó 2s (fire-and-forget), không chặn navigation và không cập nhật progress sau khi rời splash. Lần đầu sau khi đổi `CACHE_VERSION` sẽ tải lại cache (để đổi sang giọng thật) — đây là ngoại lệ có chủ đích, sau đó preload bỏ qua file đã có.
- **Fast Deployment crash:** `dotnet build -t:Run` dùng Fast Deployment → crash khi launch thủ công. Dùng APK đầy đủ từ `bin/Release/net10.0-android/` hoặc gbuild Target 1 + `adb install`.
- **Deploy của gbuild im lặng thất bại** (mục 3 bước 4): luôn kiểm `lastUpdateTime` — Target 1 có thể không cài gì.
- **Launcher activity thật:** `com.vutrungson.lamtoanlop1/crc6445a82788cff09539.MainActivity` — **không phải** `.MainActivity` (báo `Error type 3 / Activity class does not exist`). Khôi phục tên đầy đủ: `& $adb -s emulator-5554 shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER com.vutrungson.lamtoanlop1`.
- **NumberPage không có nút back dạng text** — dùng `& $adb -s emulator-5554 shell input keyevent KEYCODE_BACK`; back liên tiếp nhiều lần ở trang con sẽ thoát app (đã xảy ra 2026-11-16).
- **Kéo file binary từ emulator:** KHÔNG `adb exec-out ... > file` qua PowerShell (bytes bị mã hóa lại; MP3 pull ra 0 byte). Dùng `screencap -p /sdcard/x.png` + `adb pull`, hoặc `Start-Process adb -RedirectStandardOutput <file>`.
- **gtest tự-append** vào `.gitignore`: `node_modules/`, `build-reports/`, `logs/` — bình thường.
- **Emulator không thấy device:** `& $adb kill-server; & $adb devices` rồi mở lại shortcut; đợi `sys.boot_completed=1`.
- **App crash ngay khi mở:** xem `crash.log` (`SelfHealingService`) + `adb logcat`; không tháo fallback `AudioManager` trong `MauiProgram.cs`.

## 6. Checklist bàn giao (dán vào phản hồi cuối)

- [ ] `git status --short` — chỉ chứa file(s) dự định đổi
- [ ] `gtest` → **PASS** (đính kèm output)
- [ ] `gbuild` → **qua hết các gate L5** (xem mục 8 — Security/SAST/SupplyChain/Compliance), đường dẫn APK
- [ ] Target 1: `lastUpdateTime` == thời điểm build (hoặc đã deploy thủ công) + screenshot verify
- [ ] `build-reports/security-scan.json` → `Pass=true`; `build-reports/compliance-report.json` → `pass=true`; không có CAR record `Open` mới ngoài records cũ đã được chủ project chấp nhận (2 record 2026-11-15)
- [ ] Emulator: app cài & mở được, screenshot đính kèm (màn chính + ít nhất 1 màn có ảnh động vật)
- [ ] `git diff -- Models/MathEngine.cs` — chỉ chứa thay đổi được yêu cầu; section 1 (GameData) đúng 73 entry, đúng cấu trúc
- [ ] Không động tới `ltl1-upload-key.jks`, ảnh khác `cute_*`, thay đổi cũ chưa commit

## 7. Báo cáo

Trả lời bằng tiếng Việt (project & chủ project là người Việt): liệt kê file đã đổi, output TEST/BUILD, ảnh chụp verify, và mọc mọi gate chưa xanh + lý do + đề xuất. Không im lặng bỏ qua gate đỏ.

---

## 8. L5 — hướng build của project (chuỗi SonVuDev)

Project này build/verify bằng chính chuỗi công cụ L5 (CMMI L5 Optimizing hướng tới) mà SonVuDev dùng cho `_Build`/`_Sync`/`_Tests`. Khi nói "hướng L5", nghĩa là:

**Nguyên tắc**
- **Gate là code, không phải checklist thủ công.** Build đỏ = không được tuyên bố xong, dù APK đã đóng gói.
- **Không nới gate, không fake test.** Thiếu scanner → provision đúng cách (xem dưới), không chuyển policy sang `warn|skip`.
- **Ledger/CAR được giữ lại** — thất bại không được xóa dấu vết.
- **Single source of truth** — `BuildConstants.psm1` (`_Build`), không copy hằng số.

**Luồng L5 thực tế khi chạy `gbuild` với project này (theo thứ tự, từ log)**

1. `Start-GBuild` → preflight, SDK discovery (`dotnet 10.0.300`), `[Auto-tune]`, `[Supply chain]`.
2. Build `net10.0-android` (Release) + incremental cache → APK trong `publish-output\apk\`.
3. Gbuild chạy bước deploy + launch trên `emulator-*` đang kết nối nhưng **có thể im lặng KHÔNG cài APK** (mục 3 bước 4) — sau Target 1 luôn kiểm `lastUpdateTime` và deploy thủ công nếu cần.
4. `Test` step: detect `*.Tests.csproj` — không có → skip (không fake).
5. `[Security] Phase 1/3` secret scan → `security-scan.json`; `Phase 2/3` vulnerable packages; `Phase 3/3` license compliance → `compliance-report.json`.
6. `[Supply chain]` → `sbom.json` (CycloneDX) + policy gate (`SbomPolicy=Passed`); provenance hiện **Skipped** (`GBUILD_GITHUB_REPO` chưa set).
7. `[Static analysis]` SAST → **cần `Invoke-ScriptAnalyzer`**; bằng chứng: run 2026-11-15 16:49/17:00 bị chặn chỉ vì scanner chưa được provision → **đã vendor PSScriptAnalyzer 1.25.0** vào `D:\HOC_TAP\backup\_Build\.tools\Modules\PSScriptAnalyzer\1.25.0\` (đường dẫn + pin version gbuild tự tìm qua `Resolve-VendoredToolModule` / `VendoredToolModuleMap` / `ScriptAnalyzerVersion` trong `BuildConstants.psm1` — đây là cách cài đúng thiết kế, không phải sửa tool).
8. Audit ledger append-only (`[AUDIT] Ledger verified …`), telemetry → `build-reports/telemetry.jsonl`, `metrics-baseline.json`, SARIF/JUnit trong `build-reports/sarif|junit/`.
9. `car-records.jsonl` — mở CAR record khi gate fail; budget 14 ngày (`CarGate` rule).

**App-side L5 (những gì đang là thành viên của hệ sinh thái)**
- `SelfHealingService` — crash log + recovery; `AudioManager` fallback silent.
- `GetAllSpokenTexts()` + `GoogleTtsService` pre-cache — thiết kế chống mất mạng (correctness offline).
- `ResponsiveHelper` — nhất quán đa màn hình.

**Đánh giá trung thực hiện tại:** xem `Docs/L5-Assessment.md` — tự đánh giá **L4 với nhiều cơ chế L5 đang hoạt động** (không phải SCAMPI, không phải appraisal độc lập). Gaps: CI chưa chạy L5 gates, provenance chưa attest, CAR còn Open (2 record 2026-11-15), không có incident feed/SLO, WORM chưa Enforced, UI verify thủ công, telemetry local-only.

---

## Phụ lục A — Ảnh con vật sau 2026-11-15 (lịch sử + trạng thái)

- Điều gì đã làm: thay 74 file `convat_*.webp` (~4.6MB, có 1 file `convat_su_tu` 3.4MB) bằng **73 file `cute_*.webp` (~1.87MB)** lấy từ bộ `images cute/*.svg` (bọc PNG base64, giải mã → resize ≤512px → WebP q75 + `smartSubsample` + `effort 6`).
- Rename hoàn tất: `convat_*` → tên cute tương ứng (`convat_buom → cute_con_buom`, `convat_cho_soi → cute_soi_con`, `convat_con_khi → cute_khi_con`, `convat_con_tho → cute_tho_con`, `convat_con_voi → cute_voi_con`, `convat_huu_sao → cute_huou_sao` [typo được sửa], `convat_cu_meo → cute_chim_cu_meo`, ...).
- Gộp mèo: `convat_meo` + `convat_con_meo` (cả hai "Con mèo", ảnh giống nhau) → 1 file `cute_meo_con.webp`; `AnimalList`/`AnimalScales` bỏ entry `convat_con_meo`; `AnimalScales` giữ `cute_meo_con: 0.75`.
- GameData: **cấu trúc giữ nguyên**; 73 entry AnimalList; AnimalScales 71 entry (`cute_su_tu`, `cute_con_cao` chưa từng có scale — fallback 1.0).
- Không còn file/tham chiếu `convat_*` nào hợp lệ — gặp là sửa.
