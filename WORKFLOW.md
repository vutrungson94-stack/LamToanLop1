# WORKFLOW

Quy trình bắt buộc cho AI/người sửa project này nằm ở **[AGENTS.md](AGENTS.md)** — đọc file đó trước khi động vào bất kỳ file nào.

Tóm tắt: SỬA NHỎ NHẤT → `_Tests\gtest.ps1 -Project . -NonInteractive` (PASS) → `_Build\gbuild.ps1 -Project . -NonInteractive -Incremental` (**qua hết gate L5**: Security + SAST + SupplyChain/SBOM — xem AGENTS.md mục 8) → chạy thử trên emulator Pixel 8 (API 37) → báo cáo.

Hợp đồng frozen: Class game data `GameData` trong `Models/MathEngine.cs` giữ nguyên cấu trúc; chỉ thay **nội dung** `Resources/Images/cute_*.webp`, không đổi tên/đuôi. Chi tiết: `Docs/ADRs/ADR-0001-frozen-game-data-contract.md`, đánh giá L5: `Docs/L5-Assessment.md`.
