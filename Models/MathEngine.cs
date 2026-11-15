namespace LamToanLop1.Models
{
    // ==========================================
    // 1. CƠ SỞ DỮ LIỆU (DATA)
    // ==========================================
    public static class GameData
    {
        public static readonly List<KeyValuePair<string, string>> AnimalList =
        [
            new("cute_su_tu", "Sư tử"), new("cute_bach_tuoc", "Bạch tuộc"), new("cute_bo_canh_cam", "Bọ cánh cam"), new("cute_con_buom", "Con bướm"),
            new("cute_ca_he", "Cá hề"), new("cute_ca_heo", "Cá heo"), new("cute_ca_map", "Cá mập"),
            new("cute_ca_sau", "Cá sấu"), new("cute_ca_voi", "Cá voi"), new("cute_cao_tuyet", "Cáo tuyết"),
            new("cute_chau_chau", "Châu chấu"), new("cute_chim_canh_cut", "Chim cánh cụt"), new("cute_cho_con", "Chó con"),
            new("cute_soi_con", "Chó sói"), new("cute_chon_hoi", "Chồn hôi"), new("cute_chuot_chui", "Chuột chũi"),
            new("cute_chuot_tui", "Chuột túi"), new("cute_con_ca", "Con cá"), new("cute_con_cao", "Con cáo"),
            new("cute_con_chuot", "Con chuột"), new("cute_con_cong", "Con công"), new("cute_con_cuu", "Con cừu"),
            new("cute_con_de", "Con dê"), new("cute_con_ho", "Con hổ"), new("cute_khi_con", "Con khỉ"),
            new("cute_con_luoi", "Con lười"), new("cute_con_nhai", "Con nhái"),
            new("cute_con_qua", "Con quạ"), new("cute_con_ran", "Con rắn"), new("cute_tho_con", "Con thỏ"),
            new("cute_con_tom", "Con tôm"), new("cute_con_trau", "Con trâu"), new("cute_con_vet", "Con vẹt"),
            new("cute_con_vit", "Con vịt"), new("cute_voi_con", "Con voi"), new("cute_chim_cu_meo", "Chim cú mèo"),
            new("cute_con_cua", "Con cua"), new("cute_dai_bang", "Đại bàng"), new("cute_con_doi", "Con dơi"),
            new("cute_con_ech", "Con ếch"), new("cute_ga_con", "Gà con"), new("cute_ga_mai", "Gà mái"),
            new("cute_ga_trong", "Gà trống"), new("cute_gau_bac_cuc", "Gấu bắc cực"), new("cute_gau_nau", "Gấu nâu"),
            new("cute_gau_truc", "Gấu trúc"), new("cute_gau_truc_do", "Gấu trúc đỏ"), new("cute_ha_ma", "Hà mã"),
            new("cute_hai_cau", "Hải cẩu"), new("cute_hai_ly", "Hải ly"), new("cute_hong_hac", "Hồng hạc"),
            new("cute_huou_cao_co", "Hươu cao cổ"), new("cute_huou_sao", "Hươu sao"), new("cute_lac_da", "Lạc đà"),
            new("cute_linh_cau", "Linh cẩu"), new("cute_lon_con", "Lợn con"), new("cute_meo_con", "Con mèo"),
            new("cute_nai_sung_tam", "Nai sừng tấm"), new("cute_ngua_van", "Ngựa vằn"), new("cute_con_nhim", "Con nhím"),
            new("cute_oc_sen", "Ốc sên"), new("cute_con_ong", "Con ong"), new("cute_ong_bap_cay", "Ong bắp cày"),
            new("cute_con_rua", "Con rùa"), new("cute_sao_bien", "Sao biển"), new("cute_sau_buom", "Sâu bướm"),
            new("cute_con_soc", "Con sóc"), new("cute_soc_nau", "Sóc nâu"), new("cute_tac_ke_hoa", "Tắc kè hoa"),
            new("cute_con_tatu", "Con tatu"), new("cute_te_giac", "Tê giác"), new("cute_te_te", "Con tê tê"),
            new("cute_tuan_loc", "Tuần lộc")
        ];

        public static readonly Dictionary<string, double> AnimalScales = new()
        {
            { "cute_bach_tuoc", 0.8 }, { "cute_bo_canh_cam", 0.45 }, { "cute_con_buom", 0.45 }, { "cute_ca_he", 0.5 },
            { "cute_ca_heo", 1.4 }, { "cute_ca_map", 1.6 }, { "cute_ca_sau", 1.1 }, { "cute_ca_voi", 2.0 },
            { "cute_cao_tuyet", 0.8 }, { "cute_chau_chau", 0.45 }, { "cute_chim_canh_cut", 0.8 }, { "cute_cho_con", 0.5 },
            { "cute_soi_con", 0.8 }, { "cute_chon_hoi", 0.6 }, { "cute_con_chuot", 0.46 }, { "cute_chuot_chui", 0.48 },
            { "cute_chuot_tui", 1.1 }, { "cute_con_ca", 0.5 }, { "cute_con_cong", 1.15 }, { "cute_con_cuu", 1.1 },
            { "cute_con_de", 1.1 }, { "cute_con_ho", 1.3 }, { "cute_khi_con", 0.85 }, { "cute_con_luoi", 0.85 },
            { "cute_con_nhai", 0.45 }, { "cute_con_qua", 0.5 }, { "cute_con_ran", 0.55 },
            { "cute_tho_con", 0.7}, { "cute_con_tom", 0.45 }, { "cute_con_trau", 1.3 }, { "cute_con_vet", 0.5 },
            { "cute_con_vit", 0.6 }, { "cute_voi_con", 1.8 }, { "cute_chim_cu_meo", 0.7 }, { "cute_con_cua", 0.46 },
            { "cute_dai_bang", 0.65 }, { "cute_con_doi", 0.45 }, { "cute_con_ech", 0.45 }, { "cute_ga_con", 0.45 },
            { "cute_ga_mai", 0.48 }, { "cute_ga_trong", 0.49 }, { "cute_gau_bac_cuc", 1.4 }, { "cute_gau_nau", 1.4 },
            { "cute_gau_truc", 1.3 }, { "cute_gau_truc_do", 1.0 }, { "cute_ha_ma", 1.6 }, { "cute_hai_cau", 1.6 },
            { "cute_hai_ly", 0.8 }, { "cute_hong_hac", 0.9 }, { "cute_huou_cao_co", 1.8 }, { "cute_huou_sao", 1.1 },
            { "cute_lac_da", 1.4 }, { "cute_linh_cau", 1.25 }, { "cute_lon_con", 0.75 }, { "cute_meo_con", 0.75 },
            { "cute_nai_sung_tam", 1.5 }, { "cute_ngua_van", 1.45 }, { "cute_con_nhim", 0.6 }, { "cute_oc_sen", 0.45 },
            { "cute_con_ong", 0.45 }, { "cute_ong_bap_cay", 0.46 }, { "cute_con_rua", 0.8 }, { "cute_sao_bien", 0.5 },
            { "cute_sau_buom", 0.45 }, { "cute_con_soc", 0.6 }, { "cute_soc_nau", 0.6 }, { "cute_tac_ke_hoa", 0.47 },
            { "cute_con_tatu", 0.7 }, { "cute_te_giac", 1.7 }, { "cute_te_te", 0.65 }, { "cute_tuan_loc", 1.3 }
        };

        // Hình khối dùng trong bài Tìm hình (2D + 3D cho lớp 1)
        public static readonly string[] ShapeList = ["TRÒN", "VUÔNG", "TAM GIÁC", "CHỮ NHẬT"];
        public static readonly string[] BlockShapeList = ["KHỐI HỘP", "KHỐI LẬP PHƯƠNG"];

        // Giới hạn số lượng bạn nhỏ trong bài "Có a bạn nhỏ, nếu thêm/bớt b bạn..." theo mức
        public static int GetFarmMathLimit(int level) => level == 1 ? 6 : (level == 2 ? 12 : 18);

        // Bỏ tiền tố "Con " để đọc tên động vật trong câu hỏi (khớp với code sinh câu hỏi)
        public static string StripCon(string name)
            => string.IsNullOrWhiteSpace(name)
                ? name
                : (name.StartsWith("Con ", StringComparison.OrdinalIgnoreCase) ? name[4..].Trim() : name);

        // Liệt kê MỌI chuỗi mà game có thể đọc giọng (số, con vật, câu hỏi/đáp án, đồng hồ).
        // Đây là nguồn dữ liệu duy nhất cho việc pre-cache để khi mất mạng vẫn đọc được hết.
        public static List<string> GetAllSpokenTexts()
        {
            var list = new List<string>();

            // 1. Số 0-100 (đáp án số, thẻ số)
            list.AddRange(Enumerable.Range(0, 101).Select(n => n.ToString()));

            // 2. Tên con vật + câu "Bé hãy tìm tất cả bạn X nhé!"
            foreach (var animal in AnimalList)
            {
                list.Add(animal.Value);
                list.Add($"Bé hãy tìm tất cả bạn {StripCon(animal.Value)} nhé!");
            }

            // 3. Hình khối + câu "Bé hãy tìm tất cả hình X nhé!"
            foreach (var shape in ShapeList)
                list.Add($"Bé hãy tìm tất cả hình {shape} nhé!");

            // 4. Tiêu đề câu hỏi cố định
            list.AddRange([
                "Sắp xếp các số từ BÉ đến LỚN",
                "Sắp xếp các số từ LỚN đến BÉ",
                "Có tất cả bao nhiêu bạn nhỏ?",
                "Bạn nào LỚN NHẤT?",
                "Bạn nào BÉ NHẤT?",
                "Bên nào nhiều hơn?",
                "Hình nào còn thiếu?",
                "Số nào còn thiếu?",
                "Điền dấu thích hợp ( >, <, = )",
                "Tính nhẩm: ",
                "Tìm số thích hợp",
                "Kết quả bằng mấy?",
                "Phép tính này bằng mấy?",
                "Đồng hồ chỉ mấy giờ?"
            ]);

            // 5. Câu hỏi "Có a bạn nhỏ, nếu thêm/bớt b bạn..." — mọi tổ hợp theo giới hạn từng mức
            foreach (int limit in new[] { GetFarmMathLimit(1), GetFarmMathLimit(2), GetFarmMathLimit(3) })
            {
                for (int a = 1; a < limit; a++)
                    for (int b = 1; b <= limit - a; b++)
                        list.Add($"Có {a} bạn nhỏ, nếu thêm {b} bạn thì có tất cả bao nhiêu bạn?");

                for (int a = 2; a <= limit; a++)
                    for (int b = 1; b < a; b++)
                        list.Add($"Có {a} bạn nhỏ, nếu bớt {b} bạn thì có tất cả bao nhiêu bạn?");
            }

            // 6. Đồng hồ: "1 giờ" ... "12 giờ", "1 giờ 30" ... "12 giờ 30"
            for (int h = 1; h <= 12; h++)
            {
                list.Add($"{h} giờ");
                list.Add($"{h} giờ 30");
            }

            // 7. Dạng mới lớp 1: Tách/gộp, liền trước/sau, đo độ dài
            list.AddRange(["Tách số", "Số liền trước", "Số liền sau", "Thanh nào dài hơn?", "Trái", "Phải"]);
            for (int n = 3; n <= 18; n++)
            {
                for (int p = 1; p < n; p++)
                    list.Add($"{n} gồm {p} và mấy?");
            }
            for (int n = 1; n <= 20; n++)
            {
                list.Add($"Số liền trước của {n} là mấy?");
                list.Add($"Số liền sau của {n} là mấy?");
            }

            return list.Distinct().ToList();
        }
    }

    // ==========================================
    // 2. CẤU TRÚC CƠ BẢN
    // ==========================================
    public interface IQuestion
    {
        string Title { get; }
        string CorrectAnswer { get; }
        List<string> Options { get; }
        string VisualType { get; }
        object Data { get; }
    }

    public abstract class QuestionBase
    {
        protected static readonly Random _rnd = new();
        protected static List<string> CreateOptions(string correct, int min, int max)
        {
            var opts = new HashSet<string> { correct };
            int safe = 0;
            while (opts.Count < 4 && safe < 50)
            {
                int val;
                if (int.TryParse(correct, out int correctVal))
                    val = _rnd.Next(Math.Max(min, correctVal - 5), Math.Min(max, correctVal + 6));
                else
                    val = _rnd.Next(min, max + 1);
                opts.Add(val.ToString());
                safe++;
            }
            while (opts.Count < 4) 
                opts.Add(_rnd.Next(10, 99).ToString());
            return [.. opts.OrderBy(_ => _rnd.Next())];
        }

        protected static List<GameItem> GenerateRandomAnimals(int count)
        {
            var list = new List<GameItem>();
            for (int i = 0; i < count; i++)
            {
                var animal = GameData.AnimalList[_rnd.Next(GameData.AnimalList.Count)];
                double s = GameData.AnimalScales.TryGetValue(animal.Key, out double val) ? val : 1.0;
                list.Add(new GameItem { Key = animal.Key, Value = animal.Value, Scale = s });
            }
            return list;
        }
    }

    public class GameItem
    {
        public string Key { get; set; } = "";
        public string Value { get; set; } = "";
        public bool IsTarget { get; set; }
        public double Scale { get; set; } = 1.0;
        public string ColorHex { get; set; } = "#FFFFFF";
        public int NumberValue { get; set; }
        public bool IsMissingSlot { get; set; } = false;
    }

    public class ShapeItem
    {
        public string Type { get; set; } = "";
        public bool IsTarget { get; set; }
        public string ColorHex { get; set; } = "#000000";
        public double Scale { get; set; } = 1.0;
    }

    // ==========================================
    // 3. NHÀ MÁY SẢN XUẤT CÂU HỎI (FACTORY)
    // ==========================================
    public static class QuestionFactory
    {
        private static readonly Random _rnd = new();
        private static int _lastType = -1;
        public static IQuestion Create(int semester, int level)
        {
            // semester: 1 = CƠ BẢN (Phạm vi 10), 2 = NÂNG CAO (Phạm vi lớn hơn)
            // level: 1 = Dễ, 2 = Vừa, 3 = Khó

            int range;
            var types = new List<int>();

            if (semester == 1) // CƠ BẢN
            {
                if (level == 1)
                {
                    // DỄ: Nhận biết - Tìm và đếm trong 10 (đầu HK1)
                    range = 10;
                    types.AddRange([0, 1, 2]); // Tìm thú, Tìm hình, Đếm tổng
                }
                else if (level == 2)
                {
                    // VỪA: So sánh trực quan + sắp xếp 3 số trong 10 (giữa HK1)
                    range = 10;
                    types.AddRange([3, 4, 5]); // So sánh kích thước, So sánh số lượng, Sắp xếp
                }
                else
                {
                    // KHÓ: Vận dụng - cộng hình trong 20 + Tách/gộp số (cuối HK1, số 0-20)
                    range = 20;
                    types.AddRange([4, 8, 11]); // VisualCompare 1-10, FarmMath limit6, SplitNumber
                }
            }
            else // NÂNG CAO
            {
                if (level == 1)
                {
                    // DỄ: Số 0-20, tính nhẩm + liền trước/sau + giờ đúng (đầu HK2)
                    range = 20;
                    types.AddRange([9, 12, 10]); // TextMath, PrevNext, Clock (giờ đúng)
                }
                else if (level == 2)
                {
                    // VỪA: Số 0-50, tìm 12, sắp xếp 4 số, điền số thiếu, bài toán lời văn
                    range = 50;
                    types.AddRange([0, 1, 5, 7]); // Tìm thú/hình 12, Sắp xếp, Điền số
                }
                else
                {
                    // KHÓ: Số 0-100, tổng hợp + đo độ dài/khối
                    range = 100;
                    types.AddRange([7, 8, 9, 13]); // Điền số (tăng), FarmMath limit18, TextMath, LengthCompare
                }
            }

            // Chọn ngẫu nhiên dạng bài trong danh sách cho phép
            // Logic tránh lặp lại bài vừa làm
            int choice; 
            int safe = 0;
            do { choice = types[_rnd.Next(types.Count)]; safe++; }
            while (choice == _lastType && types.Count > 1 && safe < 10);
            _lastType = choice;

            // Mapping ID sang Loại câu hỏi
            return choice switch
            {
                0 => new ScatterQuest(level, mode: 0, range), // Tìm Con Vật
                1 => new ScatterQuest(level, mode: 1, range), // Tìm Hình
                2 => new ScatterQuest(level, mode: 3, range), // Đếm Tổng Số
                3 => new ScatterQuest(level, mode: 4, range), // So Sánh Kích Thước
                4 => new ScatterQuest(level, mode: 5, range), // So Sánh Số Lượng
                5 => new ScatterQuest(level, mode: 2, range), // Sắp Xếp Số
                6 => new SequenceQuest(level, mode: 0),       // Quy Luật Hình (ABAB/AAB)
                7 => new SequenceQuest(level, mode: 1),       // Điền Số Thiếu (chỉ tăng)
                8 => new ScatterQuest(level, mode: 6, range), // Phép Tính Hình (FarmMath)
                9 => new TextMathQuest(range, level),         // Phép Tính Số (2 số hạng)
                10 => new ClockQuest(level),                  // Đồng Hồ
                11 => new SplitNumberQuest(level),            // Tách/Gộp số (mới)
                12 => new PrevNextQuest(level),               // Liền trước/sau (mới)
                13 => new LengthCompareQuest(level),          // So sánh độ dài (mới)
                _ => new ScatterQuest(1, 3)
            };
        }
    }

    // ==========================================
    // 4. SCATTER QUEST (CÁC BÀI TOÁN RẢI HÌNH)
    // ==========================================
    public class ScatterQuest : QuestionBase, IQuestion
    {
        public string Title { get; set; }
        public string CorrectAnswer { get; set; }
        public List<string> Options { get; set; } = [];
        public string VisualType { get; set; }
        public object Data { get; set; }

        public ScatterQuest(int level, int mode, int maxRange = 10)
        {
            Title = ""; CorrectAnswer = ""; VisualType = ""; Data = new List<GameItem>();
            string[] colors = ["#F44336", "#2196F3", "#4CAF50", "#FFEB3B", "#9C27B0", "#FF9800"];

            // [TỐI ƯU] Sử dụng switch-case để chọn chế độ nhanh hơn
            switch (mode)
            {

                case 0: // TÌM CON VẬT
                case 1: // TÌM HÌNH KHỐI
                    VisualType = "FindItem";
                    bool isAnimal = (mode == 0);
                    List<KeyValuePair<string, string>> source;
                    if (isAnimal) source = GameData.AnimalList;
                    else
                    {
                        source = [.. GameData.ShapeList.Select(s => new KeyValuePair<string, string>("", s))];
                    }

                    var targetPair = source[_rnd.Next(source.Count)];
                    CorrectAnswer = isAnimal ? targetPair.Key : targetPair.Value;

                    string tName = GameData.StripCon(targetPair.Value);
                    Title = isAnimal ? $"Bé hãy tìm tất cả bạn {tName} nhé!" : $"Bé hãy tìm tất cả hình {tName} nhé!";

                    // [FIX] Scale thật của loài vật (Voi=1.8, Chuột=0.46...)
                    double tScale = (isAnimal && GameData.AnimalScales.TryGetValue(targetPair.Key, out double s)) ? s : 1.0;
                    
                    // Số lượng mục tiêu
                    int tCount = (level == 1) ? 3 : (level == 2 ? 5 : 8);
                    // Tổng số vật thể trên màn hình
                    int totalCount = (level == 1) ? 7 : (level == 2 ? 12 : 20);

                    // [FIX] Logic scale cho Hình Học: Ít hình thì to hơn, nhiều hình thì bé hơn
                    double shapeScale = 1.0;
                    if (!isAnimal)
                    {
                        // Nếu total > 15 thì shapeScale giảm xuống 0.6, nếu < 10 thì giữ nguyên 1.0
                        shapeScale = Math.Clamp(1.0 - (totalCount - 10) * 0.03, 0.60, 1.2);
                    }

                    var items = new List<GameItem>();
                    // Thêm các mục tiêu
                    for (int i = 0; i < tCount; i++) 
                        items.Add(new GameItem { 
                            Key = targetPair.Key, 
                            Value = targetPair.Value, 
                            Scale = isAnimal ? tScale : shapeScale, 
                            IsTarget = true, 
                            ColorHex = isAnimal ? "" : RandomColor() 
                        });

                    // Thêm các vật thể nhiễu
                    for (int i = 0; i < Math.Max(3, totalCount - tCount); i++)
                    {
                        var o = source[_rnd.Next(source.Count)];
                        while ((isAnimal && o.Key == targetPair.Key) || (!isAnimal && o.Value == targetPair.Value)) 
                            o = source[_rnd.Next(source.Count)];
                        
                        double os = (isAnimal && GameData.AnimalScales.TryGetValue(o.Key, out double _s)) ? _s : 1.0;
                        items.Add(new GameItem { 
                            Key = o.Key, 
                            Value = o.Value, 
                            Scale = isAnimal ? os : shapeScale, 
                            IsTarget = false, 
                            ColorHex = isAnimal ? "" : RandomColor() 
                        });
                    }
                    Data = items.OrderBy(static _ => _rnd.Next()).ToList();
                    break;

                // --- CASE 2: SẮP XẾP SỐ ---
                case 2: // SẮP XẾP SỐ
                    VisualType = "Ordering";
                    bool asc = _rnd.Next(0, 2) == 0;
                    // Đảm bảo số lượng số tạo ra khớp với level (3, 4 hoặc 5 số)
                    int count = level == 1 ? 3 : (level == 2 ? 4 : 5);
                    var nums = new HashSet<int>();
                    while (nums.Count < count) 
                        nums.Add(_rnd.Next(1, maxRange + 1));

                    var sortedList = asc ? nums.OrderBy(x => x).ToList() : [.. nums.OrderByDescending(x => x)];
                    CorrectAnswer = string.Join(", ", sortedList);
                    Title = asc ? "Sắp xếp các số từ BÉ đến LỚN" : "Sắp xếp các số từ LỚN đến BÉ";

                    var numItems = new List<GameItem>();
                    foreach (var n in nums)
                        numItems.Add(new GameItem { NumberValue = n, Value = n.ToString(), ColorHex = colors[n % colors.Length], Scale = 1.0 });
                    Data = numItems;
                    break;
                case 3: // ĐẾM TỔNG SỐ
                    VisualType = "TotalCount";
                    Title = "Có tất cả bao nhiêu bạn nhỏ?";
                    int maxCount = level == 1 ? 8 : (level == 2 ? 12 : 20);
                    int total = _rnd.Next(3, maxCount + 1);
                    CorrectAnswer = total.ToString();
                    Data = GenerateRandomAnimals(total);
                    Options = CreateOptions(CorrectAnswer, 1, maxCount + 3);
                    break;

                case 4: // SO SÁNH KÍCH THƯỚC
                    VisualType = "SizeCompare";
                    bool findBig = _rnd.Next(0, 2) == 0;
                    Title = findBig ? "Bạn nào LỚN NHẤT?" : "Bạn nào BÉ NHẤT?";
                    CorrectAnswer = findBig ? "Lớn nhất" : "Bé nhất";

                    int cmpCount = level == 1 ? 2 : (level == 2 ? 4 : 5);
                    List<GameItem> cmpItems = [];
                    int safe = 0;

                    // Bây giờ item.Scale sẽ giữ nguyên giá trị thật từ GameData (Voi=1.8, Chuột=0.46...)
                    do
                    {
                        cmpItems = GenerateRandomAnimals(cmpCount);
                        double minS = cmpItems.Min(x => x.Scale);
                        double maxS = cmpItems.Max(x => x.Scale);
                        if (maxS - minS >= 0.3) break; // Chênh lệch đủ lớn thì OK
                        safe++;
                    } while (safe < 10);

                    double targetScale = findBig ? cmpItems.Max(x => x.Scale) : cmpItems.Min(x => x.Scale);

                    // Xác định đáp án đúng (có thể có nhiều con cùng to nhất)
                    foreach (var item in cmpItems) if (Math.Abs(item.Scale - targetScale) < 0.001) item.IsTarget = true;
                    Data = cmpItems;
                    break;

                case 5: // SO SÁNH SỐ LƯỢNG
                    VisualType = "VisualCompare";
                    Title = "Bên nào nhiều hơn?";
                    Options.AddRange([">", "<", "="]);

                    int maxCmp = level == 1 ? 5 : (level == 2 ? 10 : 15);
                    int left = _rnd.Next(1, maxCmp + 1);
                    int right = _rnd.Next(1, maxCmp + 1);
                    if (level == 1 && left == right) right = (right % maxCmp) + 1;

                    CorrectAnswer = left > right ? ">" : (left < right ? "<" : "=");
                    Data = new Tuple<List<GameItem>, List<GameItem>>(GenerateRandomAnimals(left), GenerateRandomAnimals(right));
                    break;

                case 6: // PHÉP TÍNH HÌNH ẢNH (THÊM/BỚT)
                    VisualType = "FarmMath";
                    int limit = GameData.GetFarmMathLimit(level);
                    bool isAdd = _rnd.Next(2) == 0;
                    int a, b;
                    
                    if (isAdd)
                    {
                        // PHÉP CỘNG: Có a bạn, thêm b bạn → Tổng = a + b
                        a = _rnd.Next(1, limit);
                        b = _rnd.Next(1, limit - a + 1);
                    }
                    else
                    {
                        // PHÉP TRỪ: Có a bạn, bớt b bạn → Còn = a - b
                        a = _rnd.Next(2, limit + 1);  // Tổng ban đầu
                        b = _rnd.Next(1, a);           // Số cần bớt (nhỏ hơn a)
                    }

                    Title = $"Có {a} bạn nhỏ, nếu {(isAdd ? "thêm" : "bớt")} {b} bạn thì có tất cả bao nhiêu bạn?";
                    CorrectAnswer = (isAdd ? a + b : a - b).ToString();

                    // TẠO DANH SÁCH ĐỘNG VẬT:
                    // - Luôn hiển thị ĐỦ a con ban đầu
                    // - Highlight b con để thể hiện "thêm" hoặc "bớt"
                    var allAnimals = new List<GameItem>();

                    if (isAdd)
                    {
                        // Bài THÊM: Hiển thị (a+b) con, highlight b con
                        allAnimals = GenerateRandomAnimals(a + b);
                    }
                    else
                    {
                        // Bài BỚT: Hiển thị a con, highlight b con
                        allAnimals = GenerateRandomAnimals(a);
                    }
                    
                    // Đánh dấu b con đầu tiên là IsTarget (để highlight)
                    for (int i = 0; i < b && i < allAnimals.Count; i++)
                    {
                        allAnimals[i].IsTarget = true;
                    }

                    // Data = (danh sách a con, số lượng con được highlight = b)
                    Data = new Tuple<List<GameItem>, int, bool>(allAnimals, b, isAdd);
                    
                    // Tạo options cho đáp án
                    Options = CreateOptions(CorrectAnswer, 0, limit + 5);
                    break;
            }
        }

        private static string RandomColor()
        {
            // Sửa lỗi CS9176 bằng cách khai báo mảng tường minh
            string[] colors = ["#F44336", "#2196F3", "#4CAF50", "#FFEB3B", "#9C27B0", "#FF9800"];
            return colors[_rnd.Next(colors.Length)];
        }
    }

    // ==========================================
    // 5. SEQUENCE QUEST (BÀI TOÁN QUY LUẬT)
    // ==========================================
    public class SequenceQuest : QuestionBase, IQuestion
    {
        public string Title { get; }
        public string CorrectAnswer { get; }
        public List<string> Options { get; }
        public string VisualType { get; }
        public object Data { get; }

        public SequenceQuest(int level, int mode)
        {
            var items = new List<GameItem>();

            // [TỐI ƯU] Dùng switch cho các chế độ chuỗi
            switch (mode)
            {
                case 0: // PATTERN (HÌNH ẢNH)
                    VisualType = "Pattern";
                    Title = "Hình nào còn thiếu?";
                    var a = GameData.AnimalList[_rnd.Next(GameData.AnimalList.Count)];
                    var b = GameData.AnimalList[_rnd.Next(GameData.AnimalList.Count)];
                    while (b.Key == a.Key) 
                        b = GameData.AnimalList[_rnd.Next(GameData.AnimalList.Count)];
                    var c = GameData.AnimalList[_rnd.Next(GameData.AnimalList.Count)];
                    while (c.Key == a.Key || c.Key == b.Key) 
                        c = GameData.AnimalList[_rnd.Next(GameData.AnimalList.Count)];

                    string patternType = "ABAB";
                    if (level == 2) 
                        patternType = _rnd.Next(2) == 0 ? "AAB" : "ABB";
                    else if (level == 3) 
                        patternType = _rnd.Next(2) == 0 ? "AAB" : "ABB"; // lớp 1 không dùng ABC/AABB 8 ô

                    int len = 6;
                    if (patternType == "ABAB" && level == 1) len = 5;

                    int missingIndex = _rnd.Next(0, len);
                    string correctAns = "";

                    for (int i = 0; i < len; i++)
                    {
                        KeyValuePair<string, string> target = a;
                        if (patternType == "ABAB") 
                            target = (i % 2 == 0) ? a : b;
                        else if (patternType == "AAB") 
                            target = (i % 3 == 2) ? b : a;
                        else if (patternType == "ABB") 
                            target = (i % 3 == 0) ? a : b;

                        if (i == missingIndex) 
                        { 
                            correctAns = target.Value; 
                            items.Add(new GameItem { IsMissingSlot = true }); 
                        }
                        else 
                            items.Add(new GameItem { Key = target.Key, Value = target.Value });
                    }

                    CorrectAnswer = correctAns;
                    Data = items;

                    var opts = new HashSet<string>
                    {
                        CorrectAnswer, // Luôn có đáp án đúng
                        a.Value,       // Luôn có các nhân vật trong quy luật để gây nhiễu
                        b.Value
                    };

                    if (patternType.Contains('C')) 
                        opts.Add(c.Value);
                    while (opts.Count < 4) 
                        opts.Add(GameData.AnimalList[_rnd.Next(GameData.AnimalList.Count)].Value);
                    Options = [.. opts.OrderBy(_ => _rnd.Next())];
                    break;

                case 1: // MISSING NUMBER (SỐ HỌC)
                default:
                    VisualType = "MissingNumber";
                    Title = "Số nào còn thiếu?";
                    int start, step;
                    bool isAsc = true;
                    if (level == 1) 
                    { 
                        start = _rnd.Next(1, 6); 
                        step = 1; 
                    }
                    else if (level == 2) 
                    { 
                        isAsc = _rnd.Next(2) == 0;
                        step = _rnd.Next(1, 3); 
                        start = isAsc ? _rnd.Next(1, 15) : _rnd.Next(10, 25);
                    }
                    else 
                    { 
                        isAsc = true; // lớp 1 chỉ học tăng dần, bước nhỏ
                        step = _rnd.Next(1, 3); 
                        start = _rnd.Next(1, 30);
                    }

                    int mIndex = _rnd.Next(0, 5);
                    string correctAns2 = "";

                    for (int i = 0; i < 5; i++)
                    {
                        int val = isAsc ? start + i * step : start - i * step;
                        if (val < 0) val = 0;
                        if (i == mIndex) 
                        { 
                            correctAns2 = val.ToString(); 
                            items.Add(new GameItem { IsMissingSlot = true });
                        }
                        else 
                            items.Add(new GameItem { NumberValue = val, Value = val.ToString() });
                    }

                    CorrectAnswer = correctAns2;
                    Data = items;
                    int ansVal = int.Parse(CorrectAnswer);
                    Options = [.. CreateOptions(CorrectAnswer, Math.Max(0, ansVal - 5), ansVal + 5).OrderBy(x => _rnd.Next())];
                    break;
            }
        }
    }

    // ==========================================
    // 6. CÁC CLASS KHÁC (TEXT MATH & CLOCK)
    // ==========================================
    public class TextMathQuest : QuestionBase, IQuestion
    {
        public string Title { get; private set; }
        public string CorrectAnswer { get; }
        public List<string> Options { get; }
        public string VisualType => "Classic";
        public object Data { get; }

        public TextMathQuest(int max, int level)
        {
            bool isComparison = _rnd.Next(0, 2) == 0;
            if (isComparison)
            {
                Title = "Điền dấu thích hợp ( >, <, = )";
                Options = [">", "<", "="];
                int leftComplexity = (level == 1) ? _rnd.Next(0, 2) : (level == 2 ? 1 : _rnd.Next(1, 3));
                int rightComplexity = (level == 1) ? 0 : (level == 2 ? _rnd.Next(0, 2) : _rnd.Next(1, 3));

                var (leftVal, leftStr) = GenerateSide(leftComplexity, max, level);
                var (rightVal, rightStr) = GenerateSide(rightComplexity, max, level);
                CorrectAnswer = leftVal > rightVal ? ">" : (leftVal < rightVal ? "<" : "=");
                Data = $"{leftStr} ... {rightStr}";
            }
            else
            {
                Title = "Tính nhẩm: ";
                string equation = "";
                string[] ops = (level == 1) ? ["+"] : ["+", "-"];
                bool isBalanced = false; // lớp 1 không học 4 số cân bằng a+b=c+d
                bool isThreeTerms = false; // chỉ 2 số hạng cho lớp 1

                if (isBalanced)
                {
                    int target = _rnd.Next(2, Math.Min(max, 20));
                    var (a, b, op1) = GenerateExpression(target, ops, max);
                    var (c, d, op2) = GenerateExpression(target, ops, max);
                    int[] nums = [a, b, c, d]; int missing = _rnd.Next(0, 4);
                    CorrectAnswer = nums[missing].ToString();
                    string[] p = [.. nums.Select(n => n.ToString())]; p[missing] = "?";
                    equation = $"{p[0]} {op1} {p[1]} = {p[2]} {op2} {p[3]}";
                    Title = "Tìm số thích hợp";
                }
                else if (isThreeTerms)
                {
                    int a = _rnd.Next(1, 10), b = _rnd.Next(1, 10), c = _rnd.Next(1, 10);
                    string op1 = ops[_rnd.Next(ops.Length)], op2 = ops[_rnd.Next(ops.Length)];
                    int t = (op1 == "+") ? a + b : a - b; int res = (op2 == "+") ? t + c : t - c;
                    if (t < 0 || res < 0) 
                    { 
                        op1 = "+"; 
                        op2 = "+"; 
                        res = a + b + c; 
                    }
                    int missing = _rnd.Next(0, 4);
                    string[] p = [a.ToString(), b.ToString(), c.ToString(), res.ToString()];
                    CorrectAnswer = p[missing]; p[missing] = "?";
                    equation = $"{p[0]} {op1} {p[1]} {op2} {p[2]} = {p[3]}";
                    Title = missing < 3 ? "Tìm số thích hợp" : "Kết quả bằng mấy?";
                }
                else
                {
                    int target = _rnd.Next(2, max);
                    var (a, b, op) = GenerateExpression(target, ops, max);
                    int[] nums = [a, b, target]; int missing = _rnd.Next(0, 3);
                    CorrectAnswer = nums[missing].ToString();
                    string[] p = [.. nums.Select(n => n.ToString())]; p[missing] = "?";
                    equation = _rnd.Next(2) == 0 ? $"{p[0]} {op} {p[1]} = {p[2]}" : $"{p[2]} = {p[0]} {op} {p[1]}";
                    Title = missing < 2 ? "Tìm số thích hợp" : "Phép tính này bằng mấy?";
                }
                Data = equation;
                Options = CreateOptions(CorrectAnswer, 0, max + 5);
            }
        }

        // [TỐI ƯU] Dùng switch expression cho độ khó
        private static (int value, string text) GenerateSide(int complexity, int max, int level)
        {
            string[] ops = (level == 1) ? ["+"] : ["+", "-"];

            return complexity switch
            {
                0 => (_rnd.Next(0, max + 1) is int v ? (v, v.ToString()) : (0, "0")), // Case 0: Số đơn
                1 => RunCase1(), // Case 1: 2 số hạng
                _ => RunCase2()  // Case 2: 3 số hạng
            };

            // Tách hàm con để switch expression gọn gàng
            (int, string) RunCase1()
            {
                int target = _rnd.Next(2, max + 1);
                var (a, b, op) = GenerateExpression(target, ops, max);
                return ((op == "+") ? a + b : a - b, $"{a} {op} {b}");
            }

            (int, string) RunCase2()
            {
                int a = _rnd.Next(1, 10), b = _rnd.Next(1, 10), c = _rnd.Next(1, 10);
                string op1 = ops[_rnd.Next(ops.Length)], op2 = ops[_rnd.Next(ops.Length)];
                int t = (op1 == "+") ? a + b : a - b;
                int val = (op2 == "+") ? t + c : t - c;
                if (t < 0 || val < 0) 
                    return GenerateSide(complexity, max, level);
                return (val, $"{a} {op1} {b} {op2} {c}");
            }
        }

        private static (int a, int b, string op) GenerateExpression(int target, string[] availableOps, int maxVal)
        {
            string op = availableOps[_rnd.Next(availableOps.Length)];
            int a, b;
            if (op == "+") 
            {
                a = _rnd.Next(1, target); 
                b = target - a; 
            }
            else 
            { 
                int limit = Math.Min(maxVal, target + 10); 
                a = _rnd.Next(target + 1, limit + 1); 
                b = a - target;
            }
            return (a, b, op);
        }
    }

    public class ClockQuest : QuestionBase, IQuestion
    {
        public string Title => "Đồng hồ chỉ mấy giờ?";
        public string CorrectAnswer { get; }
        public List<string> Options { get; }
        public string VisualType => "Clock";
        public object Data { get; }
        public ClockQuest(int level)
        {
            bool isHalf = level == 3 && _rnd.Next(0, 2) == 0;
            int hour = _rnd.Next(1, 13);
            double displayValue = hour;
            if (isHalf)
            {
                CorrectAnswer = $"{hour} giờ 30";
                displayValue = hour + 0.5;
            }
            else
            {
                CorrectAnswer = $"{hour} giờ";
            }
            Data = displayValue;
            var opts = new HashSet<string> { CorrectAnswer };
            while (opts.Count < 4)
            {
                int rH = _rnd.Next(1, 13);
                opts.Add(isHalf ? $"{rH} giờ 30" : $"{rH} giờ");
            }
            Options = [.. opts.OrderBy(_ => _rnd.Next())];
        }
    }

    // === DẠNG MỚI LỚP 1: TÁCH/GỘP SỐ ===
    public class SplitNumberQuest : QuestionBase, IQuestion
    {
        public string Title { get; }
        public string CorrectAnswer { get; }
        public List<string> Options { get; }
        public string VisualType => "Classic";
        public object Data { get; }
        public SplitNumberQuest(int level)
        {
            int max = level == 1 ? 10 : (level == 2 ? 15 : 18);
            int whole = _rnd.Next(3, max + 1);
            int part1 = _rnd.Next(1, whole);
            int part2 = whole - part1;
            bool askPart2 = _rnd.Next(2) == 0;
            if (askPart2)
            {
                Title = $"Tách số: {whole} gồm {part1} và mấy?";
                CorrectAnswer = part2.ToString();
                Data = $"{whole} = {part1} + ?";
            }
            else
            {
                Title = $"Gộp số: {part1} và {part2} là mấy?";
                CorrectAnswer = whole.ToString();
                Data = $"{part1} + {part2} = ?";
            }
            Options = CreateOptions(CorrectAnswer, 0, max + 5);
        }
    }

    // === DẠNG MỚI: SỐ LIỀN TRƯỚC/SAU ===
    public class PrevNextQuest : QuestionBase, IQuestion
    {
        public string Title { get; }
        public string CorrectAnswer { get; }
        public List<string> Options { get; }
        public string VisualType => "Classic";
        public object Data { get; }
        public PrevNextQuest(int level)
        {
            int max = level == 1 ? 10 : (level == 2 ? 20 : 100);
            int n = _rnd.Next(1, max + 1);
            bool isPrev = _rnd.Next(2) == 0;
            if (n == 0) isPrev = false;
            if (n == max) isPrev = true;
            if (isPrev)
            {
                Title = $"Số liền trước của {n} là mấy?";
                CorrectAnswer = (n - 1).ToString();
                Data = $"{n} - 1 = ?";
            }
            else
            {
                Title = $"Số liền sau của {n} là mấy?";
                CorrectAnswer = (n + 1).ToString();
                Data = $"{n} + 1 = ?";
            }
            Options = CreateOptions(CorrectAnswer, Math.Max(0, n - 5), n + 5);
        }
    }

    // === DẠNG MỚI: SO SÁNH ĐỘ DÀI ===
    public class LengthCompareQuest : QuestionBase, IQuestion
    {
        public string Title => "Thanh nào dài hơn?";
        public string CorrectAnswer { get; }
        public List<string> Options { get; }
        public string VisualType => "LengthCompare";
        public object Data { get; }
        public LengthCompareQuest(int level)
        {
            int maxLen = level == 1 ? 5 : (level == 2 ? 8 : 10);
            int left = _rnd.Next(1, maxLen + 1);
            int right = _rnd.Next(1, maxLen + 1);
            while (left == right) right = _rnd.Next(1, maxLen + 1);
            CorrectAnswer = left > right ? "Thanh 1" : "Thanh 2";
            Options = ["Thanh 1", "Thanh 2"];
            Data = new Tuple<int,int>(left, right);
        }
    }
}