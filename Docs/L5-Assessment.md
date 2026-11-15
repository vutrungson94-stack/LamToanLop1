# L5 Assessment — LamToanLop1 (self-assessed)

- **Ngày:** 2026-11-15
- **Phạm vi:** project MAUI `LamToanLop1` + chuỗi công cụ SonVuDev mà project này đi qua trên mỗi lần build: `_Build` (gbuild — CMMI L5-oriented), `_Tests` (gtest), `_Sync` (gsync). Đánh giá dựa trên **code + báo cáo build thật đang nằm trong repo** (`build-reports/`), không dựa trên claim của README/docs.
- **Không phải** kết quả SCAMPI và không được trích dẫn như một chứng nhận.

## 1. Bằng chứng (evidence) hiện có

| Gate/cơ chế L5 | Bằng chứng | Trạng thái (2026-11-15) |
|---|---|---|
| Preflight + SDK discovery | log gbuild (Tier-1 chain, SDK 10.0.300) | ✅ |
| Incremental build + content-addressable cache | `.gbuildcache/`, `[Cache] Saved entry` | ✅ |
| Test honesty (không fake test) | project không có `*.Tests.csproj` → gtest in "Skipping dotnet test", exit 0 | ✅ (skip có chủ đích) |
| Security scan 3 phase | `build-reports/security-scan.json` → `Pass=true`, 0 Critical/High/Vulnerability | ✅ |
| SAST (PowerShell) | PSScriptAnalyzer 1.25.0 **vendored** tại `_Build\.tools\Modules\PSScriptAnalyzer\1.25.0\` (pin `ScriptAnalyzerVersion` trong `BuildConstants.psm1`) | ✅ (trước 2026-11-15 bị blocked vì thiếu scanner — đã provision theo đúng thiết kế vendored, không nới policy) |
| SBOM + policy gate | `build-reports/sbom.json` (CycloneDX), `compliance-report.json` → `supplyChain.pass=true`, SbomPolicy=Passed | ✅ |
| Provenance (SLSA/in-toto) | `build-reports/provenance.json` tồn tại (23/08) nhưng run hiện tại: **Skipped** — `GBUILD_GITHUB_REPO` chưa set | ⚠️ skipped |
| Audit ledger (append-only) | gbuild log "[AUDIT] Ledger verified … chain+signatures OK" | ✅ (WORM posture: NotVerified — storage không immutable) |
| Compliance report | `build-reports/compliance-report.json` → `pass=true`, 0 license violation | ✅ |
| Telemetry + auto-tune | `build-reports/telemetry.jsonl`, `autotune-history.jsonl` (DurationSec 412–450s/lần, thất bại 2 lần đều do gate phía ngoài build, không do code) | ✅ |
| CAR records (Corrective Action) | `build-reports/car-records.jsonl` — **2 record Open** (`TransientError` 2026-11-15 16:49 & 17:00, confidence 0.8: lần bị SAST chặn + lần bị hủy theo quyết định của chủ project) | ⚠️ mở, cần review |
| SARIF / JUnit output | `build-reports/sarif/results.sarif`, `build-reports/junit/results.xml` | ✅ |
| In-app self-healing | `Services/SelfHealingService.cs` (crash log + crash count + retry), wire trong `MauiProgram.cs`; `AudioManager` fallback silent chống crash thiết bị không có audio | ✅ |
| Responsive UI / TTS offline pre-cache | `ResponsiveHelper`, `GameData.GetAllSpokenTexts()` + `GoogleTtsService` pre-cache | ✅ |

## 2. Cái thực sự L5-shaped

1. **Gate là code, không phải checklist thủ công.** Build KHÔNG kết thúc xanh nếu SAST chặn — đúng như run 2026-11-15 16:49/17:00 (exit 1) mặc dù APK đã đóng gói xong. Build xanh/đỏ phản ánh trạng thái gate thật.
2. **Floor/ratchet được giữ nguyên, không nới.** Khi gate SAST đỏ, cách xử lý là **provision đúng vendored scanner** (đúng thiết kế `.tools\Modules` + `VendoredToolModuleMap` trong `BuildConstants.psm1`), không hạ `toolUnavailablePolicy`.
3. **Ledger/CAR được giữ lại thay vì xóa dấu vết.** 2 record CAR từ 2 lần build thất bại vẫn còn `Open` — không được che đi bởi lần build xanh sau.
4. **Single source of truth cho defaults.** `BuildConstants.psm1` (ví dụ `ScriptAnalyzerVersion='1.25.0'`, `VendoredToolsDirName='.tools/Modules'`), sharedUtils owner, không copy constants.

## 3. Còn thiếu để gọi là L5 đầy đủ (gaps — trung thực)

1. **Không có appraisal độc lập** (SCAMPI/appraiser bên ngoài). Đây là tự đánh giá của người/AI làm việc với repo.
2. **CI (`.github/workflows/build.yml`) chưa chạy L5 gates** — hiện chỉ `dotnet publish` + artifact + release. Không chạy `gtest`, không SAST, không kiểm tra gate trước khi phát hành artifact.
3. **Provenance chưa được ký/attest** vì `GBUILD_GITHUB_REPO` chưa cấu hình → `predicate` chứa placeholder `${env:GBUILD_GITHUB_REPO}`, `reproducible: false`.
4. **Chưa có incident feed** → không có SLO/MTTR/escape-rate; autotune chỉ đo duration/success cục bộ.
5. **CAR còn Open chưa đóng** — cần quyết định của chủ project: đóng tay (kèm lý do) hoặc để tự quá hạn theo `CarGate` budget.
6. **WORM posture NotVerified** — audit ledger hiện là file append-only, chưa immutable.
7. **Không có UI test tự động** trên app — kiểm chứng emulator là thủ công (xem AGENTS.md bước 6).
8. **Telemetry chỉ local** — chưa có OTLP endpoint (`OTEL_EXPORTER_OTLP_ENDPOINT` chưa set), Prometheus endpoint tắt mặc định.

## 4. Khuyến nghị theo thứ tự ưu tiên

1. **CI**: thêm job chạy `gtest` (validation 6 gate) + gate SAST tối thiểu vào `.github/workflows/build.yml`; chặn artifact nếu gate đỏ.
2. **Provenance**: set `GBUILD_GITHUB_REPO` (và nếu có, ký artifact) để SBOM được attest; regenerate `provenance.json` với dữ liệu thật.
3. **CAR**: review 2 record `TransientError` (2026-11-15); đóng/loại theo quyết định chủ project — không để record rêu rêu.
4. **Incident loop**: map `crash.log` của `SelfHealingService` vào issue tracker để có MTTR/escape-rate thật.
5. **Immutability**: lưu trữ ledger ở nơi append-only/WORM (backup read-only) nếu cần posture Enforced.
6. **UI smoke test tự động** (Appium/Espresso hoặc chụp màn hình so khớp) để giảm bước kiểm chứng thủ công.

## 5. Kết luận

**Self-assessed: L4 (Quantitatively Managed) với nhiều cơ chế L5 đang hoạt động** — đúng mô hình của `_Sync` chứ chưa phải L5 đầy đủ, vì appraisal độc lập và SLO chưa tồn tại; không tuyên bố gì hơn. Khung build/test/verify được khoá trong `AGENTS.md`; mọi thay đổi phải giữ các gate ở mục 1 xanh; không nới gate để cho qua.
