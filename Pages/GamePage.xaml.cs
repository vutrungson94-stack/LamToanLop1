using LamToanLop1.Models;
using LamToanLop1.Services;
using LamToanLop1.ViewModels;
using Microsoft.Maui.Controls.Shapes;
using Microsoft.Maui.Layouts;
using System.ComponentModel;
using System.Diagnostics;

namespace LamToanLop1.Pages;

[QueryProperty(nameof(RangeParameter), "range")]
[QueryProperty(nameof(LevelParameter), "level")]
public partial class GamePage : ContentPage
{
    // ==========================================
    // 1. KHAI BÁO BIẾN & SERVICE
    // ==========================================
    private readonly GameViewModel _vm;
    private readonly ITtsService _tts;
    private readonly ISoundService _soundService;

    // 🔒 [DEBOUNCE] Biến khóa thao tác để tránh spam nút
    private readonly SemaphoreSlim _navLock = new(1, 1);
    private readonly SemaphoreSlim _imageLoadSemaphore = new(4);
    private record PrecomputedItem(GameItem Item, Rect Bounds, double Depth);

    private int _initRange;
    private int _initLevel;

    private bool _isGameActive = false;
    private bool _isFirstLoad = true;

    private int _currentFoundCount;
    private int _totalTargetCount;

    private bool _isProcessing;

    // Cancellation token để hủy các animation/task khi page ẩn
    private CancellationTokenSource? _cts;

    // Token riêng cho render task — cancel mỗi khi RenderQuestion chạy lại
    // Tách khỏi _cts để không bị ảnh hưởng bởi app lifecycle
    private CancellationTokenSource _renderCts = new();

    private readonly PropertyChangedEventHandler? _vmPropertyHandler;

    public int RangeParameter
    {
        set
        {
            _initRange = value;
            PrepareGame(_initRange, _initLevel);
        }
    } // Cập nhật Range, giữ nguyên Level cũ

    public int LevelParameter
    {
        set
        {
            _initLevel = value;
            PrepareGame(_initRange, _initLevel);
        }
    } // Cập nhật Level, giữ nguyên Range cũ

    // Biến cho bài toán Sắp xếp
    private readonly List<int> _orderingResult = [];
    private readonly List<int> _orderingTarget = [];

    //Image cache để tái sử dụng nguồn ảnh, tránh tạo mới nhiều
    private const int IMAGE_CACHE_MAX = 80;
    private readonly Dictionary<string, ImageSource> _imageCache = []; // Key: tên file ảnh, Value: ImageSource đã tải
    private readonly LinkedList<string> _imageCacheOrder = []; // Để theo dõi thứ tự sử dụng và loại bỏ khi cache đầy

    // Biến lưu ô trống dấu ? (đích đến cho hình/số bay vào)
    private View? _missingSlotView;

    // Bảng màu vui nhộn
    private readonly string[] _funColors = ["#E91E63", "#9C27B0", "#2196F3", "#FF9800", "#4CAF50", "#F44336", "#00BCD4"];

    // KHO CHỨA CÁC VIEW ĐỂ TÁI SỬ DỤNG (OBJECT POOL)
    private const int MAX_POOL_SIZE = 50;
    private readonly Stack<View> _viewPool = new();

    public GamePage(GameViewModel vm, ITtsService tts, ISoundService soundService)
    {
        InitializeComponent();
        _vm = vm;
        _tts = tts;
        _soundService = soundService;
        BindingContext = _vm;

        // 🔥 ẨN NAV BAR
        Shell.SetNavBarIsVisible(this, false);

        // Lưu handler để có thể remove khi page disappear
        _vmPropertyHandler = (s, e) =>
        {
            if (e.PropertyName == nameof(GameViewModel.CurrentQuestion))
                RenderQuestion();
        };
    }

    // ================= Helper LRU Image Cache =================
    // Gọi khi truy cập hình: sẽ cập nhật thứ tự sử dụng (đưa key lên cuối)
    private void TouchImageCacheKey(string key)
    {
        if (_imageCacheOrder.Count == 0 && !_imageCache.ContainsKey(key)) return;
        var node = _imageCacheOrder.Find(key);
        if (node != null)
        {
            _imageCacheOrder.Remove(node);
            _imageCacheOrder.AddLast(node);
        }
    }

    // Thread-safe-ish helper to add to cache and maintain LRU
    private void Image_cache_add(string lowerKey, ImageSource src)
    {
        // single-writer assumption in this class; keep simple
        Image_cache_try_remove_oldest_if_needed();
        _imageCache[lowerKey] = src;
        _imageCacheOrder.AddLast(lowerKey);
    }

    private void Image_cache_try_remove_oldest_if_needed()
    {
        if (_imageCacheOrder.Count > IMAGE_CACHE_MAX)
        {
            var oldest = _imageCacheOrder.First?.Value;
            if (oldest != null)
            {
                _imageCacheOrder.RemoveFirst();
                _imageCache.Remove(oldest);
            }
        }
    }

    private async Task<ImageSource?> GetImageSourceCachedAsync(string key, CancellationToken token)
    {
        if (string.IsNullOrEmpty(key)) return null;

        // Đơn giản hóa: Không tự động thêm đuôi file.
        // Yêu cầu key truyền vào phải là tên file đầy đủ (ví dụ: "convat_ga.webp").
        string lowerKey = key.ToLower();

        // Nếu đã có cache trả ngay
        if (_imageCache.TryGetValue(lowerKey, out var cached))
        {
            TouchImageCacheKey(lowerKey);
            return cached;
        }

        // Throttle số load đồng thời
        await _imageLoadSemaphore.WaitAsync(token).ConfigureAwait(false);
        try
        {
            if (token.IsCancellationRequested) return null;

            // Double-check sau khi chờ semaphore
            if (_imageCache.TryGetValue(lowerKey, out var cached2))
            {
                TouchImageCacheKey(lowerKey);
                return cached2;
            }

            // Tạo ImageSource trên background (FromFile có thể chạy background)
            ImageSource? src;
            try
            {
                // ImageSource.FromFile thường an toàn để gọi từ background; nếu không, tạo trên MainThread sau
                src = ImageSource.FromFile(lowerKey);
            }
            catch (Exception ex)
            {
                Debug.WriteLine("Error loading image " + lowerKey + ": " + ex.Message);
                src = null; // Nếu có lỗi khi load ảnh, trả về null để tránh crash
            }

            // Chỉ cache nếu tải thành công (src != null)
            if (src != null)
            {
                Image_cache_add(lowerKey, src);
            }

            return src;
        }
        finally
        {
            _imageLoadSemaphore.Release();
        }
    }

    //Hàm hủy animation triệt để theo từng loại
    private static void AbortSpecificAnimations(VisualElement view)
    {
        if (view == null) return;
        try
        {
            view.CancelAnimations(); // Hủy chung
            view.AbortAnimation("ScaleTo");
            view.AbortAnimation("FadeTo");
            view.AbortAnimation("TranslateTo");
            view.AbortAnimation("RotateTo");
        }
        catch { }
    }

    public void PrepareGame(int range, int level)
    {
        _initRange = range == 0 ? 10 : range;
        _initLevel = level == 0 ? 1 : level;

        // Đánh dấu là cần load lại game khi màn hình hiện lên
        _isFirstLoad = true;
    }

    // ==========================================
    // 2. VÒNG ĐỜI (LIFECYCLE)
    // ==========================================
    protected override void OnAppearing()
    {
        base.OnAppearing();
        if (_vmPropertyHandler != null)
        {
            _vm.PropertyChanged += _vmPropertyHandler;
        }
        _ = OnAppearingAsync(); // Chạy async nhưng không chờ đợi để tránh block UI
    }

    private async Task OnAppearingAsync()
    {
        try
        {
            // Tạo CancellationTokenSource mới mỗi lần appear
            _cts?.Cancel();
            _cts?.Dispose();
            _cts = new CancellationTokenSource();

            var token = _cts?.Token ?? CancellationToken.None;

            // Bật cờ: Game đang hoạt động
            _isGameActive = true;

            // [NỐI CẦU CHÌ] Đăng ký lắng nghe sự kiện từ App
            App.AppHidden += OnAppHiddenHandler;

            // Đăng ký sự kiện Resume
            App.AppResumed += OnAppResumedHandler;

            // Kiểm tra an toàn: Nếu chưa có dữ liệu thì gán mặc định
            if (_initRange == 0) _initRange = 10;
            if (_initLevel == 0) _initLevel = 1;

            if (_isFirstLoad)
            {
                _isFirstLoad = false;

                // Đợi UI hiển thị xong mới bắt đầu logic
                await Task.Delay(75);

                // Bắt đầu game và đọc câu hỏi
                if (!token.IsCancellationRequested)
                    _vm.Start(_initRange, _initLevel);
            }
            else
            {
                // Nếu quay lại từ background, vẽ lại câu hỏi hiện tại
                if (_vm != null && _vm.CurrentQuestion != null && _isGameActive) RenderQuestion();
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"OnAppearingAsync error: {ex.Message}");
        }
    }

    protected override void OnDisappearing()
    {
        base.OnDisappearing();

        _isGameActive = false;

        // Huỷ token để dừng animation/Task đang chạy
        try
        {
            _cts?.Cancel();
            _cts?.Dispose();
            _cts = null;
        }
        catch { }

        // [NGẮT CẦU CHÌ] Hủy đăng ký để tránh lỗi bộ nhớ
        App.AppHidden -= OnAppHiddenHandler;

        //Hủy sự kiện Resume
        App.AppResumed -= OnAppResumedHandler;

        if (_vmPropertyHandler != null)
            _vm.PropertyChanged -= _vmPropertyHandler;

        StopAllAudio(); // Hàm dọn dẹp chung
        CleanupResources(); // Tách hàm dọn dẹp giao diện ra cho gọn
    }

    private void OnAppResumedHandler()
    {
        // Bật cờ: Game đang hoạt động
        _isGameActive = true;
        _isProcessing = false;

        // Đọc lại câu hỏi vì lúc nãy bị ngắt nửa chừng
        if (QuestionText?.Text?.Length > 0)
        {
            // Delay nhỏ 300ms để UI ổn định rồi đọc lại
            MainThread.BeginInvokeOnMainThread(async () =>
            {
                await Task.Delay(300);
                if (_isGameActive) SpeakQuestion(QuestionText.Text);
            });
        }
    }

    private async Task AnimateFramePulse(View frame)
    {
        try
        {
            if (!MainThread.IsMainThread)
                await MainThread.InvokeOnMainThreadAsync(() => frame.ScaleToAsync(1.1, 500));
            else
                await frame.ScaleToAsync(1.1, 500);

            if (_isGameActive)
            {
                if (!MainThread.IsMainThread)
                    await MainThread.InvokeOnMainThreadAsync(() => frame.ScaleToAsync(1.0, 500));
                else
                    await frame.ScaleToAsync(1.0, 500);
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"AnimateFramePulse error: {ex}");
        }
    }

    private void OnAppHiddenHandler()
    {
        // 1. Ngắt cờ hoạt động ngay lập tức
        _isGameActive = false;

        // 2. (Tùy chọn) Nếu muốn chắc chắn hơn, ta có thể force dừng cả UI đang chờ
        _isProcessing = false;

        // 3. Dừng mọi âm thanh đang phát
        StopAllAudio();

        // 4. Huỷ mọi animation/Task đang chạy
        try { _cts?.Cancel(); } catch { }

        //Cancel render task khi app bị ẩn
        try { _renderCts.Cancel(); } catch { }
    }

    // Gom logic dừng âm thanh vào một chỗ
    private void StopAllAudio()
    {
        try
        {
            _tts.Stop(); // Dừng đọc đề bài

            // 2. Dừng luôn tiếng pháo tay/vỗ tay
            _soundService.StopAll();
        }
        catch { }
    }

    private void CleanupResources()
    {
        // Cancel render task đang chạy trước khi dọn dẹp
        try { _renderCts.Cancel(); } catch { }

        GamePage.CleanupLayout(FarmContainer);
        GamePage.CleanupLayout(ShapeContainer);
        GamePage.CleanupLayout(OrderingSlots);
        GamePage.CleanupLayout(AnswerLayout);
        GamePage.CleanupLayout(SourceNumberContainer);
        GamePage.CleanupLayout(FlyingLayer);
        if (FarmBackground?.Source != null)
        {
            FarmBackground.Source = null;
        }
        if (FarmBackground?.Source != null)
        {
            FarmBackground.Source = null;
        }
        
        if (MathBackground?.Source != null)
        {
            MathBackground.Source = null;
        }

        // Dọn sạch Object Pool
        while (_viewPool.Count > 0)
        {
            var view = _viewPool.Pop();
            if (view is Image img) img.Source = null;
        }
        _viewPool.Clear();

        // Clear image cache (và list theo dõi)
        _imageCache.Clear();
        _imageCacheOrder.Clear();
    }

    private static void SafeCleanupLayout(Layout? layout)
    {
        if (layout == null) return;
        foreach (var child in layout.Children.ToList())
        {
            if (child is VisualElement v) AbortSpecificAnimations(v);
            if (child is View view) view.GestureRecognizers.Clear();

            if (child is Image img) img.Source = null;
            else if (child is Border border && border.Content is Image bi)
            {
                bi.Source = null;
                border.Content = null;
            }
            else if (child is Layout sub) SafeCleanupLayout(sub);
        }
        layout.Children.Clear();
    }

    // Xử lý nút Back Vật Lý
    protected override bool OnBackButtonPressed()
    {
        // Được phép check nhanh bằng Wait(0) ở đây (không block lâu)
        if (!_navLock.Wait(0)) return true; // Đang trong quá trình chuyển trang, chặn bấm liên tục

        try
        {
            _isGameActive = false;

            StopAllAudio();
            // dùng BeginInvokeOnMainThread để gọi async pop
            MainThread.BeginInvokeOnMainThread(async () => {
                try { await Navigation.PopAsync(); }
                catch (Exception ex) { Debug.WriteLine($"OnBackButtonPressed PopAsync error: {ex}"); }
            });
        }
        finally
        {
            _navLock.Release();
        }

        return true; // Chặn hành vi mặc định
    }

    private View GetViewFromPool(double size)
    {
        View view;
        if (_viewPool.Count > 0)
        {
            view = _viewPool.Pop();
            AbortSpecificAnimations(view);
            view.IsVisible = true;
            view.Scale = 1;
            view.Opacity = 1;
            view.TranslationX = 0;
            view.TranslationY = 0;
            view.Rotation = 0;
            view.InputTransparent = false;
            view.GestureRecognizers.Clear();
        }
        else
        {
            view = new Image { Aspect = Aspect.AspectFit };
        }
        view.WidthRequest = size;
        view.HeightRequest = size;
        return view;
    }

    // 2. Hàm cất đồ vào kho (Thay vì xóa bỏ)
    private void RecycleViewsInLayout(AbsoluteLayout? layout)
    {
        if (layout == null) return;

        try
        {
            var children = layout.Children.ToList(); // Copy danh sách con để tránh lỗi khi sửa đổi trong vòng lặp
            // Duyệt ngược để remove an toàn
            foreach (var child in children)
            {
                //Dừng animation trước khi xóa
                if (child is VisualElement v)
                {
                    AbortSpecificAnimations(v);
                }

                // Chỉ tái sử dụng Image (vì nó nặng nhất), các Border/Shape khác có thể xóa
                if (child is Image img)
                {
                    img.GestureRecognizers.Clear(); // [QUAN TRỌNG] Xóa event để tránh leak
                    img.Source = null; // Ngắt kết nối nguồn ảnh để giải phóng RAM

                    if (_viewPool.Count < MAX_POOL_SIZE)
                    {
                        img.IsVisible = false; // Ẩn đi
                        _viewPool.Push(img); // Cất vào kho
                    }
                }
                else
                {
                    // Nếu không phải Image thì dọn dẹp như cũ
                    if (child is Border border && border.Content is Image bi)
                    {
                        bi.Source = null;
                    }
                }

                layout.Children.Remove(child); // Gỡ khỏi màn hình
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"RecycleViewsInLayout error: {ex.Message}");
        }
    }

    // ==========================================
    // ĐIỀU PHỐI HIỂN THỊ
    // ==========================================
    private void RenderQuestion()
    {
        // Nếu game đã ẩn -> Không vẽ, không đọc
        if (!_isGameActive) return;

        var q = _vm.CurrentQuestion;
        if (q == null) return;

        // Cancel task render CŨ ngay lập tức trước khi làm bất cứ điều gì
        // Đảm bảo task Q1 không add view lên container Q2 sau khi RecycleViewsInLayout xóa sạch
        _renderCts.Cancel();
        _renderCts.Dispose();
        _renderCts = new CancellationTokenSource();
        var renderToken = _renderCts.Token;

        MainThread.BeginInvokeOnMainThread(() =>
        {
            // Kiểm tra lại lần nữa trong MainThread
            if (!_isGameActive || renderToken.IsCancellationRequested) return;

            _isProcessing = false;
            _missingSlotView = null;

            // =========================
            // SET BACKGROUND TRƯỚC
            // =========================
            MathBackground.IsVisible = false;
            FarmBackground.IsVisible = false;
            ClassicText.IsVisible = false;
            FarmContainer.IsVisible = false;
            ShapeContainer.IsVisible = false;
            ClockContainer.IsVisible = false;
            SourceNumberBorder.IsVisible = false;
            OrderingSlots.IsVisible = false;
            CollectionBin.IsVisible = false;
            AnswerLayout.IsVisible = true;

            //Recycle views trước để tránh tình trạng vẽ xong mới dọn -> giảm thiểu flicker
            RecycleViewsInLayout(FarmContainer);
            RecycleViewsInLayout(FlyingLayer);
            RecycleViewsInLayout(SourceNumberContainer);
            ShapeContainer.Children.Clear();
            OrderingSlots.Children.Clear();
            AnswerLayout.Children.Clear();

            //Set question text
            QuestionText.Text = q.Title;
            SpeakQuestion(q.Title); // Đọc đề bài ngay khi set text, không đợi render xong
                        
            try
            {
                switch (q.VisualType)
                {
                    case "TotalCount":
                    case "FindItem":
                        // Tự động chọn hình nền dựa vào loại dữ liệu
                        // Nếu Item không có Key ảnh (Key rỗng) -> Là Hình Khối -> Dùng nền Giấy
                        // Nếu Item có Key ảnh (convat_...) -> Là Con Vật -> Dùng nền Farm
                        if (q.Data is List<GameItem> items)
                        {
                            bool isShapeGame = items.Any(x => string.IsNullOrEmpty(x.Key));
                            FarmBackground.IsVisible = !isShapeGame;
                            MathBackground.IsVisible = isShapeGame;
                            FarmContainer.IsVisible = true;

                            if (q.VisualType == "FindItem")
                            {
                                // Render (true = Dùng tọa độ 40-70% toàn màn hình)
                                RenderInteractiveGame(items);
                                AnswerLayout.IsVisible = false;
                            }
                            else
                            {
                                AnswerLayout.IsVisible = true;
                                _ = Task.Run(async () =>
                                {
                                    try
                                    {
                                        var limitZone = Rect.Zero;
                                        var reservedBottom = 120.0;

                                        await MainThread.InvokeOnMainThreadAsync(() =>
                                        {
                                            if (AnswerLayout.Height > 0)
                                            {
                                                reservedBottom = Math.Max(120, AnswerLayout.Height + 20);
                                            }

                                            if (FarmContainer.Width > 0 && FarmContainer.Height > 0)
                                            {
                                                limitZone = new Rect(0, 0, FarmContainer.Width, Math.Max(0, FarmContainer.Height - reservedBottom));
                                            }
                                        });

                                        if (limitZone == Rect.Zero)
                                        {
                                            var density = DeviceDisplay.MainDisplayInfo.Density;
                                            var screenWidth = DeviceDisplay.MainDisplayInfo.Width / density;
                                            var screenHeight = DeviceDisplay.MainDisplayInfo.Height / density;
                                            limitZone = new Rect(0, 0, screenWidth, Math.Max(0, screenHeight - reservedBottom));
                                        }

                                        var pre = await ComputeScatterLayoutAsync(items, renderToken, useFarmDepth: !isShapeGame, limitZone: limitZone);
                                        if (renderToken.IsCancellationRequested) return;

                                        await RenderItemsScatterFromPrecomputedAsync(pre, renderToken); // Hàm mới có hỗ trợ async loading ảnh
                                        if (renderToken.IsCancellationRequested) return;

                                        // Render answers on UI thread
                                        await MainThread.InvokeOnMainThreadAsync(() => {
                                            if (renderToken.IsCancellationRequested) return;
                                            RenderStandardAnswers(q);
                                        });
                                    }
                                    catch (Exception ex)
                                    {
                                        Debug.WriteLine($"RenderQuestion scatter background error: {ex}");
                                    }
                                }, renderToken);
                            }
                        }
                        break;

                    case "SizeCompare":
                        FarmBackground.IsVisible = true; 
                        FarmContainer.IsVisible = true;
                        if (q.Data is List<GameItem> sizeItems)
                        {
                            RenderSizeCompareGame(sizeItems);
                        }
                        AnswerLayout.IsVisible = false;
                        break;

                    case "VisualCompare":
                        FarmBackground.IsVisible = true; 
                        FarmContainer.IsVisible = true;
                        if (q.Data is Tuple<List<GameItem>, List<GameItem>> cd)
                        {
                            RenderVisualCompareGame(cd.Item1, cd.Item2);
                        }
                        RenderStandardAnswers(q);
                        break;

                    case "FarmMath":
                        FarmBackground.IsVisible = true; 
                        FarmContainer.IsVisible = true;
                        // Cập nhật lại kiểu dữ liệu cho đúng với logic khởi tạo
                        if (q.Data is Tuple<List<GameItem>, int, bool> farmData)
                        {
                            // Gộp 2 list lại và đếm số lượng list 1 làm mốc chia (highlightCount)
                            var allItems = farmData.Item1;
                            int highlightCount = farmData.Item2;
                            bool isAdd = farmData.Item3;

                            // Dùng ComputeScatter + Render để tối ưu
                            var token = _cts?.Token ?? CancellationToken.None;
                            _ = Task.Run(async () =>
                            {
                                try
                                {
                                    var pre = await ComputeScatterLayoutAsync(allItems, token);
                                    if (token.IsCancellationRequested) return;

                                    await RenderItemsScatterFromPrecomputedAsync(pre, token);
                                    if (token.IsCancellationRequested) return;

                                    MainThread.BeginInvokeOnMainThread(() =>
                                    {
                                        if (token.IsCancellationRequested) return;

                                        // Vẽ viền tròn cho các con có IsTarget = true (dùng bounds hiện có)
                                        int imageIndex = 0;
                                        var imageViews = FarmContainer.Children.OfType<Image>().Select(img => (img, AbsoluteLayout.GetLayoutBounds(img))).ToList();
                                        
                                        // 🔥 CHỌN MÀU THEO LOẠI BÀI
                                        Color highlightColor = isAdd ? Colors.LimeGreen : Colors.OrangeRed;
                                        
                                        foreach (var item in allItems)
                                        {
                                            if (item.IsTarget && imageIndex < imageViews?.Count)
                                            {
                                                var (img, bounds) = imageViews[imageIndex];
                                                var circle = new Border
                                                {
                                                    Stroke = highlightColor,
                                                    StrokeThickness = 4,
                                                    BackgroundColor = Colors.Transparent,
                                                    StrokeShape = new RoundRectangle { CornerRadius = (float)(bounds.Width / 2 + 5) },
                                                    InputTransparent = true
                                                };
                                                double padding = 8;
                                                Rect circleRect = new(bounds.X - padding, bounds.Y - padding, bounds.Width + padding * 2, bounds.Height + padding * 2);
                                                AbsoluteLayout.SetLayoutBounds(circle, circleRect);
                                                FarmContainer.Children.Add(circle);

                                                // animate circle safely
                                                _ = Task.Run(async () =>
                                                {
                                                    try
                                                    {
                                                        await MainThread.InvokeOnMainThreadAsync(async () =>
                                                        {
                                                            circle.Opacity = 0;
                                                            await circle.FadeToAsync(1, 500, Easing.SinInOut);
                                                            if (token.IsCancellationRequested) return;
                                                            await circle.FadeToAsync(0.5, 500, Easing.SinInOut);
                                                            if (token.IsCancellationRequested) return;
                                                            await circle.FadeToAsync(1, 500, Easing.SinInOut);
                                                        });
                                                    }
                                                    catch { }
                                                });
                                            }
                                            imageIndex++;
                                        }
                                    });
                                }
                                catch (Exception ex) { Debug.WriteLine($"FarmMath compute/render error: {ex}"); }
                            });
                        }

                        RenderStandardAnswers(q);
                        break;

                    case "Clock":
                        MathBackground.IsVisible = true; 
                        ClockContainer.IsVisible = true; 
                        DrawClockFace();
                        if (q.Data is double h)
                        {
                            if (ClockContainer.FindByName("ClockHourHand") is BoxView hh) { hh.AnchorY = 1; hh.Rotation = h * 30; }
                            bool isHalf = (h % 1) != 0;
                            if (ClockContainer.FindByName("ClockMinuteHand") is BoxView mh) { mh.AnchorY = 1; mh.Rotation = isHalf ? 180 : 0; }
                        }
                        RenderStandardAnswers(q);
                        break;

                    case "Classic":
                        MathBackground.IsVisible = true;
                        ClassicText.Text = q.Data?.ToString();
                        ClassicText.IsVisible = true;
                        RenderStandardAnswers(q);
                        break;

                    case "Ordering":
                        MathBackground.IsVisible = true;
                        SourceNumberBorder.IsVisible = true;
                        OrderingSlots.IsVisible = true;
                        AnswerLayout.IsVisible = false;

                        if (q.Data is List<GameItem> orderingItems)
                        {
                            var intList = orderingItems.Select(x => x.NumberValue).ToList();
                            RenderOrderingGame(intList, q.CorrectAnswer);
                        }
                        else if (q.Data is List<int> nums)
                        {
                            RenderOrderingGame(nums, q.CorrectAnswer);
                        }
                        break;

                    case "Pattern":
                        MathBackground.IsVisible = true; 
                        OrderingSlots.IsVisible = true;
                        if (q.Data is List<GameItem> patternItems)
                        {
                            RenderSequenceGame(patternItems);
                            RenderPatternAnswers(q);
                        }
                        break;

                    case "MissingNumber":
                        MathBackground.IsVisible = true; 
                        OrderingSlots.IsVisible = true;
                        if (q.Data is List<GameItem> missingItems)
                        {
                            RenderSequenceGame(missingItems);
                            RenderStandardAnswers(q);
                        }
                        break;

                    case "FindShape":
                        MathBackground.IsVisible = true;
                        FarmContainer.IsVisible = true;
                        if (q.Data is List<GameItem> gItems) // Nếu đã dùng ScatterQuest thì Data là List<GameItem>
                        {
                            RenderInteractiveGame(gItems);
                            AnswerLayout.IsVisible = false;
                        }
                        // Fallback code cũ
                        else if (q.Data is List<ShapeItem> sItems)
                        {
                            var convertedItems = sItems.Select(x => new GameItem { Value = x.Type, IsTarget = x.IsTarget, ColorHex = x.ColorHex, Scale = x.Scale }).ToList();
                            RenderInteractiveGame(convertedItems);
                            AnswerLayout.IsVisible = false;
                        }
                        break;

                    case "Shape":
                        MathBackground.IsVisible = true; 
                        ShapeContainer.IsVisible = true;
                        RenderSingleShape(q.Data?.ToString());
                        RenderStandardAnswers(q);
                        break;

                    default:
                        MathBackground.IsVisible = true;
                        ClassicText.Text = q.Data?.ToString();
                        ClassicText.IsVisible = true;
                        RenderStandardAnswers(q);
                        break;
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"RenderQuestion error ({q.VisualType}): {ex}");
            }
        });
    }

    // ==========================================
    // ANIMATION & HỆ THỐNG BAY
    // ==========================================
    private static Point GetScreenCoordinates(VisualElement element)
    {
        double x = 0; double y = 0;
        while (element != null)
        {
            x += element.X; y += element.Y;
            if (element.Parent is VisualElement parent)
            {
                if (parent is Grid g && g.FindByName("RootGrid") != null) break;
                element = parent;
            }
            else break;
        }
        return new Point(x, y);
    }

    private async Task AnimateFlyToTarget(View sourceView, View flyContent, View targetView)
    {
        // Kiểm tra huỷ token để thoát sớm nếu page bị đóng
        var token = _cts?.Token ?? CancellationToken.None;
        if (token.IsCancellationRequested) return;

        Point startPt = GetScreenCoordinates(sourceView);
        Point targetPt = new(100, 100);

        double startX = startPt.X + (sourceView.Width - flyContent.WidthRequest) / 2;
        double startY = startPt.Y + (sourceView.Height - flyContent.HeightRequest) / 2;

        if (targetView != null)
        {
            Point endPt = GetScreenCoordinates(targetView);
            targetPt = new Point(endPt.X + (targetView.Width - flyContent.WidthRequest) / 2, endPt.Y + (targetView.Height - flyContent.HeightRequest) / 2);
        }

        // Thiết lập layout bounds tương ứng trên layer bay (sử dụng Rect có kích thước cụ thể)
        AbsoluteLayout.SetLayoutBounds(flyContent, new Rect(startX, startY, flyContent.WidthRequest, flyContent.HeightRequest));
        FlyingLayer.Children.Add(flyContent);

        double transX = targetPt.X - startX;
        double transY = targetPt.Y - startY;

        try
        {
            if (token.IsCancellationRequested) return;

            await MainThread.InvokeOnMainThreadAsync(async () =>
            {
                await flyContent.ScaleToAsync(1.3, 150, Easing.SinInOut);
                if (token.IsCancellationRequested) return;
                // TranslateTo/ScaleTo chạy trên main thread; gọi qua MainThread để an toàn
                await flyContent.TranslateToAsync(transX, transY, 400, Easing.SinInOut);
                if (token.IsCancellationRequested) return;
                await flyContent.ScaleToAsync(0.1, 150, Easing.SinIn);
            });
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"AnimateFlyToTarget error: {ex}");
        }
        finally
        {
            // Remove chỉ khi còn nằm trong layer
            try
            {
                if (FlyingLayer.Children.Contains(flyContent)) FlyingLayer.Children.Remove(flyContent);
            }
            catch { }
        }
    }    

    // ==========================================
    // RENDER & LOGIC TỪNG GAME
    // ==========================================
    // PHÂN TÁCH: Compute layout off-UI để tránh block (trả về list Rect position)
    private const double FARM_HORIZON_RATIO = 0.45; // Tỷ lệ chiều cao dành cho phần "đất" trong Farm (phần dưới)
    private const double FARM_BOTTOM_RATIO = 0.82; // Tỷ lệ chiều cao tối đa của item so với container (để tránh quá to)
    private const double FARM_DEPTH_MIN = 0.55; // Tỷ lệ scale nhỏ nhất (cho item ở "xa")
    private const double FARM_DEPTH_MAX = 1.25; // Tỷ lệ scale lớn nhất (cho item ở "gần")

    // --- HÀM TÍNH TOÁN VỊ TRÍ (ComputeScatterLayoutAsync) ---
    private async Task<List<PrecomputedItem>> ComputeScatterLayoutAsync(List<GameItem> items, CancellationToken token, bool useFarmDepth = false, Rect limitZone = default, List<Rect>? forbiddenZones = null, bool enforceExactScale = false)
    {
        // Giữ mọi tính toán nặng ở đây (khoảng cách, tránh chồng lấp, scale)
        // Trả về danh sách bounds (Rect) và depth/scale để render
        var result = new List<PrecomputedItem>(items.Count);
        var rand = System.Random.Shared;

        // Lấy kích thước container một lần trên UI thread
        Rect container = Rect.Zero;

        await MainThread.InvokeOnMainThreadAsync(() =>
        {
            if (FarmContainer.Width > 0 && FarmContainer.Height > 0)
            {
                container = new Rect(0, 0, FarmContainer.Width, FarmContainer.Height);
            }
        });

        if (container.Width <= 0)
        {
            var density = DeviceDisplay.MainDisplayInfo.Density;
            container = new Rect(0, 0, DeviceDisplay.MainDisplayInfo.Width / density, DeviceDisplay.MainDisplayInfo.Height / density); // Fallback kích thước mặc định (360x640 dp)
        }

        double cw = container.Width; double ch = container.Height;

        // Vùng hợp lệ để rải (có thể bị giới hạn bởi limitZone)
        double zoneX = limitZone == default ? 0 : limitZone.X;
        double zoneY = limitZone == default ? 0 : limitZone.Y;
        double zoneWidth = limitZone == default ? cw : limitZone.Width;
        double zoneHeight = limitZone == default ? ch : limitZone.Height;

        // Vùng đất farm (Y tuyệt đối trên container)
        double horizonY = ch * FARM_HORIZON_RATIO;
        double bottomY = ch * FARM_BOTTOM_RATIO;
        double depthRange = bottomY - horizonY;

        // Kích thước cơ sở: dựa vào số lượng item (càng nhiều thì càng nhỏ)
        double baseSize = Math.Clamp(Math.Min(cw, ch) * (items.Count <= 5 ? 0.14 : items.Count <= 10 ? 0.11 : 0.09), 28, 110);

        var placed = new List<Rect>(items.Count);

        // Sắp xếp item to trước (ưu tiên đặt item lớn khi còn nhiều chỗ trống)
        var sorted = items.OrderByDescending(x => x.Scale).ToList();

        foreach (var it in sorted)
        {
            if (token.IsCancellationRequested) break;

            Rect r = Rect.Zero;
            double depthRatio = 0.5; // mặc định giữa

            if (useFarmDepth)
            {
                // --- FARM DEPTH MODEL ---
                // Cố gắng đặt với depth ngẫu nhiên, scale tương ứng
                bool placed_ok = false;
                double globalShrink = 1.0;

                for (int attempt = 0; attempt < 60 && !placed_ok; attempt++)
                {
                    // Depth ngẫu nhiên trong vùng farm (giới hạn thêm bởi limitZone nếu có)
                    double yMin = limitZone == default ? horizonY : Math.Max(horizonY, zoneY);
                    double yMax = limitZone == default ? bottomY : Math.Min(bottomY, zoneY + zoneHeight);
                    if (yMax <= yMin) { yMin = horizonY; yMax = bottomY; }

                    depthRatio = rand.NextDouble(); // 0 = xa (nhỏ), 1 = gần (to)
                    double yPos = yMin + depthRatio * (yMax - yMin);

                    // Kích thước = baseSize * scale_con_vat * depth_scale
                    double depthScale = FARM_DEPTH_MIN + depthRatio * (FARM_DEPTH_MAX - FARM_DEPTH_MIN);
                    double sz = baseSize * it.Scale * depthScale * globalShrink;
                    sz = Math.Clamp(sz, 28, cw * 0.40);

                    double xMin = limitZone == default ? 0 : zoneX;
                    double xMax = limitZone == default ? cw : zoneX + zoneWidth;
                    double x = xMin + rand.NextDouble() * Math.Max(0, (xMax - xMin) - sz); 

                    r = new Rect(x, yPos, sz, sz);

                    // Padding tỷ lệ với kích thước (item to cần khoảng cách lớn hơn)
                    double pad = sz * 0.15;
                    Rect padded = new(r.X - pad, r.Y - pad, r.Width + pad * 2, r.Height + pad * 2);

                    bool isColliding = placed.Any(p => p.IntersectsWith(padded)) || (forbiddenZones?.Any(fz => fz.IntersectsWith(padded)) ?? false);

                    if (!isColliding)
                        placed_ok = true;

                    // Sau 20 lần thất bại, thu nhỏ toàn cục 5%
                    if (!placed_ok && attempt % 20 == 19)
                        globalShrink = Math.Max(0.4, globalShrink - 0.05);
                }

                if (r == Rect.Zero) // fallback: ép vào vị trí bất kỳ
                {
                    double sz = baseSize * it.Scale * 0.6;
                    double yPos = horizonY + rand.NextDouble() * depthRange;
                    depthRatio = (yPos - horizonY) / (depthRange > 0 ? depthRange : 1);
                    r = new Rect(rand.NextDouble() * Math.Max(0, cw - sz), yPos, sz, sz);
                }
            }
            else
            {
                // --- FLAT MODEL (hình học) ---
                double randomScale = enforceExactScale ? 1.0 : 0.8 + rand.NextDouble() * 0.4; // Nếu cần exact scale thì giữ nguyên tỷ lệ thật
                double sz = baseSize * it.Scale * randomScale;
                sz = Math.Clamp(sz, 35, cw * 0.25);

                bool placed_ok = false;
                for (int attempt = 0; attempt < 50 && !placed_ok; attempt++)
                {
                    double x = zoneX + rand.NextDouble() * Math.Max(0, zoneWidth - sz);
                    double y = zoneY + rand.NextDouble() * Math.Max(0, zoneHeight - sz);
                    r = new Rect(x, y, sz, sz);

                    bool isColliding = placed.Any(p => p.IntersectsWith(r)) || (forbiddenZones?.Any(fz => fz.IntersectsWith(r)) ?? false);

                    if (!isColliding) placed_ok = true;
                }
                if (r == Rect.Zero)
                    r = new Rect(zoneX, zoneY, sz, sz); // fallback
                depthRatio = 0.5;
            }

            placed.Add(r);
            result.Add(new PrecomputedItem(it, r, depthRatio));
        }

        return result;
    }

    // Hàm dựng view từ kết quả precomputed (chạy trên UI thread)
    private async Task RenderItemsScatterFromPrecomputedAsync(List<PrecomputedItem> pre, CancellationToken token, bool isInteractive = false)
    {
        if (pre == null || pre.Count == 0) return;

        // 1) Preload image sources (throttle) in background
        var loadTasks = pre.Select(async p =>
        {
            ImageSource? src = null;
            if (!string.IsNullOrEmpty(p.Item.Key))
            {
                try
                {
                    src = await GetImageSourceCachedAsync(p.Item.Key, token);
                }
                catch { src = null; }
            }
            return (pre: p, src);
        });

        var loaded = await Task.WhenAll(loadTasks).ConfigureAwait(false);

        if (token.IsCancellationRequested) return;

        var sorted = loaded.OrderBy(t => t.pre.Bounds.Y).ToArray();

        //Lấy View từ Pool và add vào FarmContainer BẮT BUỘC PHẢI TRÊN UI THREAD
        await MainThread.InvokeOnMainThreadAsync(() =>
        {
            //Thêm "chốt chặn" cuối cùng ngay trước khi cập nhật UI
            if (token.IsCancellationRequested) return;

            try
            {
                // xóa sạch children cũ trước khi add (nếu có) - đảm bảo không bị lỗi khi render nhanh
                foreach (var (p, src) in sorted)
                {
                    var bounds = p.Bounds;
                    var item = p.Item;

                    //Nếu key rỗng = hình học → tạo ShapeView, không dùng Image (Image.Source=null → vô hình)
                    if (string.IsNullOrEmpty(item.Key))
                    {
                        var shapeView = CreateShapeView(item.Value, item.ColorHex, bounds.Width);
                        shapeView.WidthRequest = bounds.Width;
                        shapeView.HeightRequest = bounds.Height;
                        shapeView.Opacity = 0; // Bắt đầu ẩn, sẽ fade in sau

                        if (isInteractive)
                        {
                            var captured = item; // capture for lambda
                            var tap = new TapGestureRecognizer();
                            tap.Tapped += async (s, e) => await HandleItemTap(shapeView, captured);
                            shapeView.GestureRecognizers.Add(tap);
                        }

                        AbsoluteLayout.SetLayoutBounds(shapeView, bounds);
                        AbsoluteLayout.SetLayoutFlags(shapeView, AbsoluteLayoutFlags.None);
                        FarmContainer?.Children.Add(shapeView);
                        continue;
                    }
                    else
                    {

                        // Con vật → dùng Image pool
                        var view = GetViewFromPool(bounds.Width);
                        if (view is Image img)
                        {
                            img.Source = src;
                            img.InputTransparent = false;
                            img.IsVisible = true;
                            img.Opacity = 0; // Bắt đầu ẩn, sẽ fade in sau

                            // Optional: attach tap gesture for interactive games
                            img.GestureRecognizers.Clear();
                            if (isInteractive)
                            {
                                var capturedItem = item; // capture for lambda
                                var capturedView = img; // capture for lambda
                                var tap = new TapGestureRecognizer();
                                tap.Tapped += async (s, e) => await HandleItemTap(capturedView, capturedItem);
                                img.GestureRecognizers.Add(tap);
                            }

                            AbsoluteLayout.SetLayoutBounds(img, bounds);
                            AbsoluteLayout.SetLayoutFlags(img, AbsoluteLayoutFlags.None);

                            FarmContainer?.Children.Add(img);
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Render batch error: {ex.Message}");
            }
        });

        if (token.IsCancellationRequested) return;
        // 4) Optional: staggered fade-in for visible children (limit concurrency)
        var children = FarmContainer.Children.OfType<View>().ToList() ?? [];
        _ = Task.Run(async () =>
        {
            int groupSize = 6;
            for (int i = 0; i < children.Count; i += groupSize)
            {
                if (token.IsCancellationRequested) break;
                var group = children.Skip(i).Take(groupSize).ToList();
                try
                {
                    await MainThread.InvokeOnMainThreadAsync(async () =>
                    {
                        if (token.IsCancellationRequested) return;
                        foreach (var v in group)
                        {
                            v.Scale = 0;
                            v.Opacity = 1;
                        }
                        await Task.WhenAll(group.Select(v => v.ScaleToAsync(1.0, 280, Easing.SpringOut)));
                    });
                } catch { }
                try { await Task.Delay(80, token); } catch { }
                ;
            }
        }, token);
    }

    private void DrawClockFace()
    {
        if (ClockContainer.FindByName("ClockFaceNumbers") is AbsoluteLayout face)
        {
            face.Children.Clear();
            double centerX = 130; double centerY = 130; double radius = 100;
            for (int i = 1; i <= 12; i++)
            {
                double angleRad = (i * 30 - 90) * (Math.PI / 180);
                double x = centerX + radius * Math.Cos(angleRad);
                double y = centerY + radius * Math.Sin(angleRad);
                var label = new Label { Text = i.ToString(), FontSize = 22, FontAttributes = FontAttributes.Bold, TextColor = Color.FromArgb("#5D4037"), HorizontalTextAlignment = TextAlignment.Center, VerticalTextAlignment = TextAlignment.Center, WidthRequest = 30, HeightRequest = 30 };
                AbsoluteLayout.SetLayoutBounds(label, new Rect(x - 15, y - 15, 30, 30));
                face.Children.Add(label);
            }
        }
    }

    private void RenderFarmMath(List<GameItem> items, int highlightCount)
    {
        var renderToken = _renderCts.Token;
        _ = Task.Run(async () =>
        {
            try
            {
                Rect container = Rect.Zero;
                await MainThread.InvokeOnMainThreadAsync(() =>
                {
                    if (FarmContainer?.Width > 0 && FarmContainer.Height > 0)
                        container = new Rect(0, 0, FarmContainer.Width, FarmContainer.Height);
                });

                if (container.Width <= 0) return;

                double cw = container.Width;
                double ch = container.Height;
                double horizonY = ch * FARM_HORIZON_RATIO;
                double bottomY = ch * FARM_BOTTOM_RATIO;

                // Rải đều tất cả items (a con) trong vùng farm
                Rect scatterZone = new(10, horizonY, cw - 20, bottomY - horizonY);

                var pre = await ComputeScatterLayoutAsync(
                    items, 
                    renderToken, 
                    useFarmDepth: true, 
                    limitZone: scatterZone
                );
                
                if (renderToken.IsCancellationRequested) return;
                
                await RenderItemsScatterFromPrecomputedAsync(pre, renderToken, isInteractive: false);
                
                if (renderToken.IsCancellationRequested) return;

                // Vẽ khung highlight xung quanh b con được đánh dấu
                await MainThread.InvokeOnMainThreadAsync(() =>
                {
                    var highlightedItems = pre.Where(p => p.Item.IsTarget).ToList();
                    
                    if (highlightedItems.Count > 0)
                    {
                        double minX = highlightedItems.Min(p => p.Bounds.X);
                        double minY = highlightedItems.Min(p => p.Bounds.Y);
                        double maxX = highlightedItems.Max(p => p.Bounds.Right);
                        double maxY = highlightedItems.Max(p => p.Bounds.Bottom);
                        
                        double pad = 14;
                        var frame = new Border
                        {
                            Stroke = Colors.Orange,
                            StrokeThickness = 3,
                            StrokeDashArray = [10.0f, 5.0f],
                            BackgroundColor = Color.FromArgb("#22FFFFFF"),
                            StrokeShape = new RoundRectangle { CornerRadius = 15 },
                            InputTransparent = true
                        };
                        
                        Rect frameRect = new(minX - pad, minY - pad,
                                            maxX - minX + pad * 2, maxY - minY + pad * 2);
                        
                        AbsoluteLayout.SetLayoutBounds(frame, frameRect);
                        AbsoluteLayout.SetLayoutFlags(frame, AbsoluteLayoutFlags.None);
                        FarmContainer?.Children.Insert(0, frame);
                    }
                });
            }
            catch (Exception ex) { Debug.WriteLine($"RenderFarmMath error: {ex}"); }
        });
    }

    private void RenderSizeCompareGame(List<GameItem> items)
    {
        if (items == null || items.Count == 0)
        {
            Debug.WriteLine("RenderSizeCompareGame: No items to render.");
            return;
        }   

        // SizeCompare: hiển thị các con vật với kích thước tỉ lệ theo Scale thực,
        // không dùng farm-depth (muốn kích thước phản ánh đúng to/nhỏ),
        // có thể tap để chọn đúng/sai.
        _currentFoundCount = 0;
        _totalTargetCount = 1; // Chỉ cần chọn đúng 1 con

        var renderToken = _renderCts.Token;
        _ = Task.Run(async () =>
        {
            try
            {
                Rect container = Rect.Zero;
                await MainThread.InvokeOnMainThreadAsync(() =>
                {
                    if (FarmContainer?.Width > 0 && FarmContainer.Height > 0)
                        container = new Rect(0, 0, FarmContainer.Width, FarmContainer.Height);
                });

                if (container.Width <= 0) return;

                double cw = container.Width;
                double ch = container.Height;

                // 🔥 Tính vùng "Đáp Đất" dựa trên hằng số FARM_HORIZON_RATIO
                // Đảm bảo con vật chỉ xuất hiện từ 50% chiều cao màn hình trở xuống
                double safeY = ch * FARM_HORIZON_RATIO; 
                double safeH = (ch * FARM_BOTTOM_RATIO) - safeY;
                Rect groundZone = new Rect(0, safeY, cw, safeH);

                // Dùng flat model với kích thước đúng theo Scale thật của từng con
                var pre = await ComputeScatterLayoutAsync(
                    items, 
                    renderToken, 
                    useFarmDepth: false, 
                    limitZone: groundZone,
                    enforceExactScale: true
                );
                
                if (renderToken.IsCancellationRequested) return;

                // Load ảnh
                var loadTasks = pre.Select(async p =>
                {
                    ImageSource? src = null;
                    if (!string.IsNullOrEmpty(p.Item.Key))
                        src = await GetImageSourceCachedAsync(p.Item.Key, renderToken);
                    return (p, src);
                });
                var loaded = await Task.WhenAll(loadTasks).ConfigureAwait(false);
                if (renderToken.IsCancellationRequested) return;

                // Render + gắn tap từng con
                await MainThread.InvokeOnMainThreadAsync(() =>
                {
                    foreach (var (p, src) in loaded.OrderBy(t => t.p.Bounds.Y))
                    {
                        if (renderToken.IsCancellationRequested) break;
                        var view = GetViewFromPool(p.Bounds.Width);
                        if (view is not Image img) continue;

                        img.Source = src;
                        img.IsVisible = true;
                        img.Opacity = 1;
                        img.InputTransparent = false;
                        img.GestureRecognizers.Clear();

                        var capturedItem = p.Item;
                        var capturedImg = img;
                        var tap = new TapGestureRecognizer();
                        tap.Tapped += async (s, e) =>
                        {
                            if (_isProcessing) return;
                            if (capturedItem.IsTarget)
                            {
                                _isProcessing = true;
                                await capturedImg.ScaleToAsync(1.2, 100);
                                await capturedImg.ScaleToAsync(1.0, 100);
                                await HandleWinCondition();
                            }
                            else
                            {
                                await capturedImg.TranslateToAsync(10, 0, 50);
                                await capturedImg.TranslateToAsync(-10, 0, 50);
                                capturedImg.TranslationX = 0;
                                _ = _tts.SpeakWithMoodAsync("Chưa đúng rồi, bé nhìn kỹ lại nhé!", VoiceMood.Sad);
                            }
                        };
                        img.GestureRecognizers.Add(tap);

                        AbsoluteLayout.SetLayoutBounds(img, p.Bounds);
                        AbsoluteLayout.SetLayoutFlags(img, AbsoluteLayoutFlags.None);
                        FarmContainer?.Children.Add(img);
                    }
                });

                if (renderToken.IsCancellationRequested) return;

                // Entrance animation
                var children = FarmContainer?.Children.OfType<View>().ToList() ?? [];
                await MainThread.InvokeOnMainThreadAsync(async () =>
                {
                    foreach (var v in children) v.Scale = 0;
                    var tasks = children.Select(v => v.ScaleToAsync(1.0, 350, Easing.SpringOut));
                    await Task.WhenAll(tasks);
                });
            }
            catch (Exception ex) { Debug.WriteLine($"RenderSizeCompareGame error: {ex}"); }
        });
    }

    private void RenderStandardAnswers(IQuestion q)
    {
        AnswerLayout.RowDefinitions.Clear(); AnswerLayout.ColumnDefinitions.Clear();
        bool isShort = q.Options.All(o => o.Length <= 2);
        var shuffledColors = _funColors.OrderBy(x => System.Random.Shared.Next()).Take(4).ToArray();

        if (isShort)
        {
            AnswerLayout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            for (int k = 0; k < 4; k++) AnswerLayout.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Star });
            for (int i = 0; i < 4; i++) { if (i >= q.Options.Count) break; var btn = CreateAnswerButton(q.Options[i], shuffledColors[i], 60); AnswerLayout.Add(btn); Grid.SetColumn(btn, i); }
        }
        else
        {
            AnswerLayout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); AnswerLayout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            AnswerLayout.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Star }); AnswerLayout.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Star });
            for (int i = 0; i < 4; i++) { if (i >= q.Options.Count) break; var btn = CreateAnswerButton(q.Options[i], shuffledColors[i], 70); AnswerLayout.Add(btn); Grid.SetRow(btn, i / 2); Grid.SetColumn(btn, i % 2); }
        }
    }

    //Dọn dẹp sạch sẽ hình ảnh để tránh tràn RAM
    private static void CleanupLayout(Layout layout)
    {
        if (layout == null) return;

        foreach (var child in layout.Children)
        {
            //Dừng animation trước khi xóa
            if (child is VisualElement v)
            {
                AbortSpecificAnimations(v);
            }

            // Xóa gesture nếu child là View
            if (child is View view)
            {
                view.GestureRecognizers.Clear();
            }

            // Ngắt kết nối Source ảnh để bộ nhớ được giải phóng ngay lập tức
            if (child is Image img)
            {
                img.Source = null;
            }
            else if (child is Border border)
            {
                if (border.Content is Image borderImg)
                {
                    borderImg.Source = null;
                    border.Content = null;
                }
            }
            else if (child is Layout subLayout)
            {
                GamePage.CleanupLayout(subLayout); // Đệ quy dọn con bên trong
            }
        }
        layout.Children.Clear();
    }

    private Button CreateAnswerButton(string text, string color, double height)
    {
        var btn = new Button { Text = text, FontSize = 24, FontAttributes = FontAttributes.Bold, BackgroundColor = Color.FromArgb(color), TextColor = Colors.White, CornerRadius = 25, HeightRequest = height, LineBreakMode = LineBreakMode.WordWrap, Shadow = new Shadow { Brush = Colors.Black, Offset = new Point(2, 4), Opacity = 0.3f, Radius = 4 }, Margin = 2 };
        btn.Clicked += OnAnswerClicked; return btn;
    }

    private async void OnAnswerClicked(object? sender, EventArgs e)
    {

        //Dùng _isProcessing guard đơn giản thay vì _navLock (không WaitAsync mà Release → crash)
        if (_isProcessing || !_isGameActive) return;
        _isProcessing = true;

        if (sender is not Button btn)
        {
            Debug.WriteLine("OnAnswerClicked: sender is not a Button.");
            _isProcessing = false;
            return;
        }

        try
        {
            //Stop animation cũ của nút
            AbortSpecificAnimations(btn);
            await Task.WhenAll(
                btn.ScaleToAsync(0.9, 100),
                btn.ScaleToAsync(1, 100)
            );

            if (_vm.CheckAnswer(btn.Text))
            {
                StopAllAudio(); // Dừng âm thanh cũ nếu có

                // --- TRƯỜNG HỢP ĐÚNG ---
                if (_vm.CurrentQuestion?.VisualType == "MissingNumber" && _missingSlotView != null)
                {
                    // Logic bay số vào chỗ trống
                    var flyLabel = new Label { Text = btn.Text, FontSize = 32, FontAttributes = FontAttributes.Bold, TextColor = Color.FromArgb("#1565C0"), WidthRequest = 60, HeightRequest = 60, HorizontalTextAlignment = TextAlignment.Center, VerticalTextAlignment = TextAlignment.Center };
                    btn.Text = ""; // Xóa chữ ở nút bấm cho đẹp

                    await AnimateFlyToTarget(btn, flyLabel, _missingSlotView);
                    if (_missingSlotView is Border slotBorder)
                    {
                        slotBorder.Content = new Label { Text = flyLabel.Text, FontSize = 32, FontAttributes = FontAttributes.Bold, TextColor = Color.FromArgb("#1565C0"), HorizontalOptions = LayoutOptions.Center, VerticalOptions = LayoutOptions.Center };
                        slotBorder.BackgroundColor = Colors.White;
                        slotBorder.Stroke = Colors.Green;
                        slotBorder.StrokeDashArray = null;
                    }
                    await Task.Delay(500);
                    await HandleCorrectAnswerAsync();
                }
                else
                {
                    // Logic thường cho các câu hỏi khác: chỉ cần hiệu ứng đúng rồi chuyển câu mới
                    await HandleCorrectAnswerAsync();
                }

                // _isProcessing sẽ được reset bởi RenderQuestion của câu tiếp theo
                return;
            }
            else
            {
                // --- TRƯỜNG HỢP SAI ---

                // Hiệu ứng lắc qua lại
                await btn.TranslateToAsync(15, 0, 40, Easing.Linear);
                await btn.TranslateToAsync(-15, 0, 40, Easing.Linear);
                await btn.TranslateToAsync(15, 0, 40, Easing.Linear);
                await btn.TranslateToAsync(-15, 0, 40, Easing.Linear);
                btn.TranslationX = 0;

                StopAllAudio();
                _ = _tts.SpeakWithMoodAsync("Sai rồi, thử lại nhé!", VoiceMood.Sad); 
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error in OnAnswerClicked: {ex}");
            btn.TranslationX = 0; // Reset vị trí nếu lỗi xảy ra trong animation
            btn.Scale = 1; // Reset scale nếu lỗi xảy ra trong animation
        }
        finally
        {
            // Đảm bảo mở khóa nếu có lỗi không lường trước
            _isProcessing = false;
        }
    }

    private void RenderPatternAnswers(IQuestion q)
    {
        AnswerLayout.RowDefinitions.Clear(); AnswerLayout.ColumnDefinitions.Clear();
        AnswerLayout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        AnswerLayout.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Star }); AnswerLayout.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Star }); AnswerLayout.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Star }); AnswerLayout.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Star });
        for (int i = 0; i < q.Options.Count; i++)
        {
            string answerText = q.Options[i];
            var kvp = GameData.AnimalList.FirstOrDefault(x => x.Value == answerText);
            string imgKey = !string.IsNullOrEmpty(kvp.Key) ? kvp.Key : "convat_ga_con";
            var card = new Border { Stroke = Colors.Gray, StrokeThickness = 1, BackgroundColor = Colors.White, StrokeShape = new RoundRectangle { CornerRadius = 15 }, HeightRequest = 125, Margin = 4, Shadow = new Shadow { Brush = Colors.Black, Offset = new Point(2, 2), Opacity = 0.2f, Radius = 4 } };
            var stack = new VerticalStackLayout { Spacing = 2, VerticalOptions = LayoutOptions.Center };
            var img = new Image { Source = $"{imgKey}.webp", HeightRequest = 60, Aspect = Aspect.AspectFit };
            var lbl = new Label { Text = answerText, FontSize = 14, FontAttributes = FontAttributes.Bold, TextColor = Colors.Black, HorizontalTextAlignment = TextAlignment.Center, LineBreakMode = LineBreakMode.WordWrap, MaxLines = 2 };
            stack.Add(img); stack.Add(lbl); card.Content = stack;
            var tap = new TapGestureRecognizer();
            tap.Tapped += async (s, e) => await OnPatternAnswerTapped(card, img, answerText, q.CorrectAnswer);
            card.GestureRecognizers.Add(tap);
            AnswerLayout.Add(card);
            Grid.SetColumn(card, i);
        }
    }

    private async Task OnPatternAnswerTapped(Border card, Image answerImg, string selectedAns, string correctAns)
    {
        if (_isProcessing) return;

        _isProcessing = true;

        try
        {
            AbortSpecificAnimations(card);

            if (selectedAns == correctAns)
            {
                // ĐÚNG
                if (_missingSlotView == null)
                {
                    _isProcessing = false;
                    Debug.WriteLine("OnPatternAnswerTapped Error: _missingSlotView is null.");
                    await HandleCorrectAnswerAsync(); // Van xu ly thang nhung khong co animation
                    return;
                }

                answerImg.Opacity = 0;
                var flyImg = new Image { Source = answerImg.Source, WidthRequest = 60, HeightRequest = 60, Aspect = Aspect.AspectFit };

                await AnimateFlyToTarget(card, flyImg, _missingSlotView);
                if (_missingSlotView is Border slotBorder)
                {
                    slotBorder.Content = new Image { Source = answerImg.Source, Aspect = Aspect.AspectFit, Margin = 4 };
                    slotBorder.BackgroundColor = Colors.White;
                    slotBorder.Stroke = Colors.Green;
                    slotBorder.StrokeDashArray = null;
                }
                await Task.Delay(1000);
                await HandleCorrectAnswerAsync();
            }
            else
            {
                // SAI -> Lắc -> Mở khóa
                await card.TranslateToAsync(5, 0, 50);
                await card.TranslateToAsync(-5, 0, 50);
                card.TranslationX = 0;

                StopAllAudio();
                _ = _tts.SpeakWithMoodAsync("Sai rồi, bé chọn lại nhé!", VoiceMood.Sad);

                // [QUAN TRỌNG] MỞ KHÓA
                _isProcessing = false;
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error in OnPatternAnswerTapped: {ex}");
            _isProcessing = false; // Đảm bảo mở khóa nếu có lỗi
        }
    }

    private static Grid CreateShapeView(string type, string colorHex, double size)
    {
        Shape s;
        if (type == "TRÒN") s = new Ellipse();
        else if (type == "VUÔNG") s = new Microsoft.Maui.Controls.Shapes.Rectangle();
        else if (type == "CHỮ NHẬT") s = new Microsoft.Maui.Controls.Shapes.Rectangle { WidthRequest = size * 1.5 };
        else if (type == "TAM GIÁC")
        {
            var poly = new Polygon();
            poly.Points.Add(new Point(size / 2, 0));
            poly.Points.Add(new Point(0, size));
            poly.Points.Add(new Point(size, size));
            s = poly;
        }
        else s = new Ellipse();

        s.Fill = Color.FromArgb(colorHex); 
        s.Stroke = Colors.White; 
        s.StrokeThickness = 3;
        s.HorizontalOptions = LayoutOptions.Fill; 
        s.VerticalOptions = LayoutOptions.Fill;

        if (type != "CHỮ NHẬT" && type != "TAM GIÁC") { s.WidthRequest = size; s.HeightRequest = size; } else if (type == "TAM GIÁC") { } else { s.HeightRequest = size; }
        return new Grid { WidthRequest = size, HeightRequest = size,  Children = { s }, Shadow = new Shadow { Brush = Colors.Black, Offset = new Point(2, 2), Opacity = 0.3f, Radius = 3 } };
    }

    private void RenderVisualCompareGame(List<GameItem> left, List<GameItem> right)
    {
        var renderToken = _renderCts.Token;
        _ = Task.Run(async () =>
        {
            try
            {
                // Lấy kích thước container
                Rect container = Rect.Zero;
                await MainThread.InvokeOnMainThreadAsync(() =>
                {
                    if (FarmContainer?.Width > 0 && FarmContainer.Height > 0)
                        container = new Rect(0, 0, FarmContainer.Width, FarmContainer.Height);
                });

                if (container.Width <= 0) return;

                double halfW = container.Width / 2.0;
                double ch = container.Height;
                double horizonY = ch * FARM_HORIZON_RATIO;
                double bottomY = ch * FARM_BOTTOM_RATIO;

                // Vùng trái và phải (chừa 5px ở giữa mỗi bên)
                Rect leftZone = new(0, horizonY, halfW - 6, bottomY - horizonY);
                Rect rightZone = new(halfW + 6, horizonY, halfW - 6, bottomY - horizonY);

                var preLeft = await ComputeScatterLayoutAsync(left, renderToken, useFarmDepth: true, limitZone: leftZone);

                if (renderToken.IsCancellationRequested) return;
                var preRight = await ComputeScatterLayoutAsync(right, renderToken, useFarmDepth: true, limitZone: rightZone);
                if (renderToken.IsCancellationRequested) return;

                // Kết hợp 2 nhóm (đã có tọa độ riêng) rồi render 1 lần
                var combined = preLeft.Concat(preRight).ToList();

                // Vẽ đường kẻ giữa trên UI thread trước
                await MainThread.InvokeOnMainThreadAsync(() =>
                {
                    var divider = new BoxView
                    {
                        Color = Colors.White,
                        WidthRequest = 3,
                        HeightRequest = ch,
                        Opacity = 0.8
                    };
                    AbsoluteLayout.SetLayoutBounds(divider, new Rect(halfW - 1.5, 0, 3, ch));
                    AbsoluteLayout.SetLayoutFlags(divider, AbsoluteLayoutFlags.None);
                    FarmContainer?.Children.Add(divider);
                });

                await RenderItemsScatterFromPrecomputedAsync(combined, renderToken, isInteractive: false);
            }
            catch (Exception ex) { Debug.WriteLine($"RenderVisualCompareGame error: {ex}"); }
        });
    }

    private void RenderInteractiveGame(List<GameItem> items)
    {
        _currentFoundCount = 0;
        _totalTargetCount = items.Count(i => i.IsTarget);

        bool isShapeGame = items.Any(x => string.IsNullOrEmpty(x.Key));

        // Tính vùng cấm (giỏ hàng)
        Rect forbiddenZone = Rect.Zero;

        MainThread.BeginInvokeOnMainThread(() =>
        {
            FarmBackground.IsVisible = !isShapeGame;
            MathBackground.IsVisible = isShapeGame;
            FarmContainer.IsVisible = true;
            CollectionBin.IsVisible = true;
            CounterLabel.Text = $"0/{_totalTargetCount}";

            // 🔥 TÍNH TOÁN VÙNG CẤM ĐỘNG THEO VỊ TRÍ THỰC TẾ CỦA GIỎ HÀNG
            if (CollectionBin != null && CollectionBin.IsVisible)
            {
                double cartY = CollectionBin.Y;
                double cartH = CollectionBin.Height;
                double margin = 20; // Khoảng cách an toàn giữa item và giỏ
                
                 // Nếu layout chưa render xong (Height = 0), dùng vị trí dự đoán
                if (cartH <= 0)
                {
                    cartH = 120; // Chiều cao dự đoán của giỏ hàng
                    cartY = FarmContainer.Height - cartH; // Vị trí dự đoán của giỏ hàng
                }

                // Vùng cấm: Từ đỉnh giỏ hàng trở xuống hết container + margin
                forbiddenZone = new Rect(
                    0, 
                    cartY - margin, 
                    FarmContainer.Width, 
                    (FarmContainer.Height - (cartY - margin - 100))
                );
            }

            var sample = items.FirstOrDefault(i => i.IsTarget);
            if (sample != null)
            {
                if (TargetIconContainer.Content is Image oldImg) oldImg.Source = null;
                TargetIconContainer.Content = !string.IsNullOrEmpty(sample.Key)
                    ? new Image { Source = $"{sample.Key}.webp", Aspect = Aspect.AspectFit }
                    : (View)CreateShapeView(sample.Value, "#4CAF50", 30);
            }
        });

        var renderToken = _renderCts.Token;
        _ = Task.Run(async () =>
        {
            try
            {
                // Đảm bảo forbiddenZone đã được tính
                if (forbiddenZone == Rect.Zero && FarmContainer.Height > 0)
                {
                    double cartH = 120;
                    double cartY = FarmContainer.Height - cartH;
                    forbiddenZone = new Rect(
                        0, 
                        FarmContainer.Height - 20, 
                        FarmContainer.Width, 
                        cartH + 20
                    );
                }

                // TRUYỀN forbiddenZones vào ComputeScatterLayoutAsync
                var pre = await ComputeScatterLayoutAsync(
                    items, 
                    renderToken, 
                    useFarmDepth: !isShapeGame,
                    forbiddenZones: 
                    [forbiddenZone]  // ← THÊM DÒNG NÀY
                );
                
                if (renderToken.IsCancellationRequested) return;
                
                await RenderItemsScatterFromPrecomputedAsync(pre, renderToken, isInteractive: true);
            }
            catch (Exception ex) 
            { 
                Debug.WriteLine($"RenderInteractiveGame error: {ex}"); 
            }
        });
    }

    private async Task HandleItemTap(View view, GameItem item)
    {
        if (view.InputTransparent) return;
        if (!item.IsTarget)
        {
            view.InputTransparent = true;
            AbortSpecificAnimations(view);
            await view.TranslateToAsync(5, 0, 50);
            await view.TranslateToAsync(-5, 0, 50);
            view.TranslationX = 0;
            view.InputTransparent = false;
            return;
        }
        view.InputTransparent = true;
        view.Opacity = 0;

        View flyContent;
        if (!string.IsNullOrEmpty(item.Key))
            flyContent = new Image { Source = $"{item.Key}.webp", WidthRequest = 60, HeightRequest = 60, Aspect = Aspect.AspectFit };
        else flyContent = CreateShapeView(item.Value, item.ColorHex, 60);

        await AnimateFlyToTarget(view, flyContent, CollectionBin);

        // Logic sau khi animation hoan tat
        _currentFoundCount++;
        CounterLabel.Text = $"{_currentFoundCount}/{_totalTargetCount}";
        await CounterLabel.ScaleToAsync(1.5, 100);
        await CounterLabel.ScaleToAsync(1.0, 100);
        if (_currentFoundCount >= _totalTargetCount)
        {
            _isProcessing = true;
            await Task.Delay(300);
            await HandleWinCondition();
        }
    }

    private void SpeakQuestion(string text)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(text)) return;
            _ = _tts.SpeakAsync(text);
        }
        catch { }
    }

    private void RenderSingleShape(string? shapeName)
    {
        if (string.IsNullOrEmpty(shapeName)) return;
        View s = CreateShapeView(shapeName, "#E91E63", 200);
        ShapeContainer.Children.Add(s);
    }

    // --- HÀM RENDER SẮP XẾP SỐ (RenderOrderingGame) ---
    private void RenderOrderingGame(List<int> numbers, string correctAnswer)
    {
        _orderingResult.Clear();
        _orderingTarget.Clear();
        // 🔥 Parse đáp án để biết CHÍNH XÁC cần bao nhiêu ô & bong bóng
        _orderingTarget.AddRange(correctAnswer.Split(',', StringSplitOptions.RemoveEmptyEntries).Select(int.Parse));

        _isProcessing = false;
        string[] colors = ["#F44336", "#4CAF50", "#2196F3", "#FF9800", "#9C27B0", "#00BCD4"];
        var rand = System.Random.Shared;

        // 1. Vẽ ô trống (Dùng _orderingTarget.Count thay vì numbers.Count)
        OrderingSlots.Children.Clear();
        OrderingSlots.ColumnDefinitions.Clear();
        int targetCount = _orderingTarget.Count;
        for (int i = 0; i < targetCount; i++)
            OrderingSlots.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Star });

        double slotH = targetCount > 5 ? 55 : 70;
        OrderingSlots.HeightRequest = slotH + 10;

        for (int i = 0; i < targetCount; i++)
        {
            var slot = new Border
            {
                Stroke = Colors.Black, StrokeThickness = 2, StrokeDashArray = [5.0f, 3.0f],
                HeightRequest = slotH, HorizontalOptions = LayoutOptions.Fill,
                BackgroundColor = Color.FromArgb("#10000000"), StrokeShape = new RoundRectangle { CornerRadius = 15 }, Margin = 2
            };
            OrderingSlots.Children.Add(slot);
            Grid.SetColumn(slot, i); 
        }

        _ = DelayOnMainThread(1);

        // 2. Rải số nguồn (Chỉ lấy đúng số lượng cần thiết)
        RecycleViewsInLayout(SourceNumberContainer);
        double cw = SourceNumberContainer.Width;
        double ch = SourceNumberContainer.Height;

        if (cw <= 0 || ch <= 0)
        {
            cw = DeviceDisplay.MainDisplayInfo.Width / DeviceDisplay.MainDisplayInfo.Density - 20;
            ch = DeviceDisplay.MainDisplayInfo.Height / DeviceDisplay.MainDisplayInfo.Density - 20;
        }

        double answerH = AnswerLayout.IsVisible ? AnswerLayout.Height : 0;
        double slotsHeight = OrderingSlots.HeightRequest + 40;
        ch = Math.Max(ch - answerH - slotsHeight - 30, 150); 

        // Chia vùng trên & dưới ô đáp án
        Rect scatterZoneTop = new(10, 10, cw - 20, ch / 2 - 20);
        Rect scatterZoneBottom = new(10, ch / 2 + slotsHeight + 10, cw - 20, ch / 2 - 20);

        var occupied = new List<Rect>();
        // 🔥 Shuffle đúng số lượng số có trong đề
        var shuffled = numbers.OrderBy(_ => rand.Next()).ToList();

        for (int i = 0; i < shuffled.Count; i++)
        {
            int num = shuffled[i];
            double size = rand.Next(55, 85);

            Rect pos = Rect.Zero;
            Rect[] zones = { scatterZoneTop, scatterZoneBottom };
            
            foreach (var zone in zones)
            {
                for (int attempt = 0; attempt < 100; attempt++)
                {
                    double x = zone.X + rand.NextDouble() * Math.Max(0, zone.Width - size);
                    double y = zone.Y + rand.NextDouble() * Math.Max(0, zone.Height - size);
                    Rect candidate = new(x, y, size, size);
                    if (!occupied.Any(r => r.IntersectsWith(candidate)))
                    {
                        pos = candidate; break;
                    }
                }
                if (pos != Rect.Zero) break;
            }

            if (pos == Rect.Zero) pos = new Rect(scatterZoneTop.X, scatterZoneTop.Y + (i * 90), size, size);
            occupied.Add(pos);

            var border = new Border
            {
                Stroke = Colors.White, StrokeThickness = 3, BackgroundColor = Color.FromArgb(colors[i % colors.Length]),
                HeightRequest = size, WidthRequest = size, StrokeShape = new RoundRectangle { CornerRadius = (float)(size / 2.5) },
                Rotation = rand.Next(-25, 26),
                Content = new Label { Text = num.ToString(), FontSize = size * 0.42, FontAttributes = FontAttributes.Bold, HorizontalOptions = LayoutOptions.Center, VerticalOptions = LayoutOptions.Center, TextColor = Colors.White }
            };

            AbsoluteLayout.SetLayoutBounds(border, pos);
            AbsoluteLayout.SetLayoutFlags(border, AbsoluteLayoutFlags.None);
            SourceNumberContainer.Children.Add(border);

            border.Scale = 0;
            _ = border.ScaleToAsync(1.0, 400, Easing.SpringOut);

            var capturedNum = num;
            var tap = new TapGestureRecognizer();
            tap.Tapped += async (s, e) => await OnNumberTapped(border, capturedNum);
            border.GestureRecognizers.Add(tap);
        }
    }

    private async Task DelayOnMainThread(int ms)
    {
        try
        {
            await MainThread.InvokeOnMainThreadAsync(async () =>
            {
                await Task.Delay(ms); // Delay nhỏ để đảm bảo các slot đã được vẽ trước khi rải số
            });
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Delay error: {ex}");
        }
    }

    private async Task OnNumberTapped(Border view, int number)
    {
        if (_isProcessing) return;
        _isProcessing = true;

        try
        {
            int slotIndex = _orderingResult.Count;
            if (slotIndex >= OrderingSlots.Children.Count) return;

            if (OrderingSlots.Children[slotIndex] is not Border slotBorder) return;

            AbortSpecificAnimations(view);

            // Ẩn số đã chọn
            await view.ScaleToAsync(0, 200);
            view.IsVisible = false;

            // Điền vào ô trống
            slotBorder.BackgroundColor = Colors.White;
            slotBorder.StrokeDashArray = null;
            slotBorder.Stroke = Colors.Orange;
            slotBorder.Content = new Label
            {
                Text = number.ToString(),
                FontSize = 30,
                FontAttributes = FontAttributes.Bold,
                HorizontalOptions = LayoutOptions.Center,
                VerticalOptions = LayoutOptions.Center,
                TextColor = Colors.Black
            };

            _orderingResult.Add(number);

            if (_orderingResult.Count == _orderingTarget.Count)
            {
                if (_orderingResult.SequenceEqual(_orderingTarget))
                {
                    _isProcessing = true;
                    await Task.Delay(600);
                    await HandleWinCondition();
                }
                else
                {
                    _ = _tts.SpeakWithMoodAsync("Sai rồi, thử lại nhé!", VoiceMood.Sad);
                    await Task.Delay(900);
                    RenderQuestion(); // Vẽ lại câu hỏi
                }
            }
        } 
        finally
        {
            _isProcessing = false;
        }
    }

    private void RenderSequenceGame(List<GameItem> items)
    {
        OrderingSlots.Children.Clear();
        OrderingSlots.ColumnDefinitions.Clear();

        int itemCount = items.Count;

        // Chia đều cột
        for (int i = 0; i < itemCount; i++)
            OrderingSlots.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Star });

        // Tính toán kích thước hiển thị để không tràn màn hình
        // Nếu có 8 con thì size bé (55), nếu 5 con thì size to (75)
        double slotHeight = itemCount > 6 ? 55 : 75;
        double fontSize = itemCount > 6 ? 22 : 32;
        double imgMargin = itemCount > 6 ? 2 : 4;

        OrderingSlots.HeightRequest = slotHeight + 10; // Cập nhật chiều cao Grid cha

        for (int i = 0; i < itemCount; i++)
        {
            var item = items[i];
            var frame = new Border
            {
                StrokeThickness = 2,
                HeightRequest = slotHeight, // Size động
                HorizontalOptions = LayoutOptions.Fill,
                StrokeShape = new RoundRectangle { CornerRadius = 15 },
                Shadow = new Shadow { Brush = Colors.Gray, Offset = new Point(2, 2), Opacity = 0.3f, Radius = 3 },
                Margin = 2
            };

            if (item.IsMissingSlot)
            {
                _missingSlotView = frame;
                frame.BackgroundColor = Color.FromArgb("#FFF3E0");
                frame.Stroke = Colors.Red;
                frame.StrokeDashArray = new float[] { 5.0f, 3.0f };
                frame.Content = new Label
                {
                    Text = "?",
                    FontSize = fontSize,
                    FontAttributes = FontAttributes.Bold,
                    TextColor = Colors.Red,
                    HorizontalOptions = LayoutOptions.Center,
                    VerticalOptions = LayoutOptions.Center
                };
                _ = AnimateFramePulse(frame);
            }
            else
            {
                frame.BackgroundColor = Colors.White;
                frame.Stroke = Colors.Black;
                if (!string.IsNullOrEmpty(item.Key))
                {
                    frame.Content = new Image
                    {
                        Source = $"{item.Key}.webp",
                        Aspect = Aspect.AspectFit,
                        Margin = imgMargin,
                        HorizontalOptions = LayoutOptions.Center,
                        VerticalOptions = LayoutOptions.Center
                    };
                }
                else
                {
                    frame.Content = new Label
                    {
                        Text = item.Value,
                        FontSize = fontSize,
                        FontAttributes = FontAttributes.Bold,
                        TextColor = Color.FromArgb("#1565C0"),
                        HorizontalOptions = LayoutOptions.Center,
                        VerticalOptions = LayoutOptions.Center
                    };
                }
            }
            OrderingSlots.Children.Add(frame);
            Grid.SetColumn(frame, i);
        }
    }

    // Nút Back trên màn hình
    private async void OnBack(object sender, EventArgs e)
    {
        if (!await _navLock.WaitAsync(0)) return;

        try
        {
            if (sender is Button btn)
            {
                AbortSpecificAnimations(btn);
                await btn.ScaleToAsync(0.9, 100);
                await btn.ScaleToAsync(1.0, 100);
            }
            StopAllAudio();
            await Navigation.PopAsync();
        }
        catch (Exception ex) { Debug.WriteLine($"OnBack error: {ex}"); }
        finally
        {
            _navLock.Release();
        }
    }

    private async void OnReplayQuestion(object sender, EventArgs e)
    {
        if (!await _navLock.WaitAsync(0)) return;

        try
        {
            if (sender is ImageButton btn)
            {
                AbortSpecificAnimations(btn);
                // Hiệu ứng nhún nhảy nút loa
                await btn.ScaleToAsync(0.8, 100);
                await btn.ScaleToAsync(1.0, 100);
            }

            StopAllAudio();
            // Đọc lại câu hỏi
            if (QuestionText?.Text?.Length > 0)
            {
                SpeakQuestion(QuestionText.Text);
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"OnReplayQuestion error: {ex}");
        }
        finally
        {
            _navLock.Release();
        }
    }

    private async void OnSkip(object sender, EventArgs e)
    {
        if (_isProcessing) return;
        if (!await _navLock.WaitAsync(0)) return;

        try
        {
            if (sender is Button btn)
            {
                AbortSpecificAnimations(btn);
                await btn.ScaleToAsync(0.9, 100);
                await btn.ScaleToAsync(1.0, 100);
            }
            StopAllAudio();
            _ = _tts.SpeakWithMoodAsync("Không sao, mình làm câu khác nhé!", VoiceMood.Happy);
            _currentFoundCount = 0;
            _vm.NextQuestion();
        }
        catch (Exception ex) { Debug.WriteLine($"OnSkip error: {ex}"); }
        finally
        {
            _navLock.Release();
        }
    }

    private async Task HandleCorrectAnswerAsync()
    {
        // Nếu token cũ đã bị hủy hoặc chưa tạo, hãy tạo mới để chạy tiếp
        if (_cts == null || _cts.IsCancellationRequested)
        {
            _cts = new CancellationTokenSource();
        }
        
        // Đảm bảo Border chúc mừng luôn ở trạng thái sẵn sàng
        CongratulationBorder.IsVisible = true; 
        CongratulationBorder.Scale = 0;

        if (!_isGameActive) return;
        _vm.Stars++;
        await ShowCongratulationsDialogAsync();

        // Quan trọng nhất!
        // Sau khi chúc mừng xong (2s), nếu người dùng đã thoát thì KHÔNG sinh câu hỏi mới
        if (!_isGameActive) return;

        _vm.NextQuestion();
    }

    private async Task HandleWinCondition()
    {
        if (!_isGameActive) return;
        _vm.Stars++;
        await ShowCongratulationsDialogAsync();

        // [CHỐT CHẶN 4]
        if (!_isGameActive) return;

        _vm.NextQuestion();
    }

    private async Task ShowCongratulationsDialogAsync()
    {
        // Nếu đã thoát thì không hiện bảng chúc mừng
        if (!_isGameActive) return;

        var token = _cts?.Token ?? CancellationToken.None;
        if (token.IsCancellationRequested) return;

        await MainThread.InvokeOnMainThreadAsync(() =>
        {
            CongratulationOverlay.IsVisible = true;
            CongratulationOverlay.InputTransparent = false;
            CongratulationOverlay.Opacity = 1;
            CongratulationBorder.Scale = 0;
            CongratulationBorder.Opacity = 1;
            StarsLabel.Opacity = 1;
            StarsLabel.Rotation = 0;
        });

        await Task.Yield();

        try
        {
            // Chạy song song âm thanh và animation để tiết kiệm thời gian
            var soundTask = Task.Run(async () =>
            {
                await _soundService.PlayPhaoAsync();
                if (token.IsCancellationRequested) return;
                await Task.Delay(300, token);
                if (token.IsCancellationRequested) return;
                await _soundService.PlayVoTayAsync();
            }, token);

            var ttsTask = _tts.SpeakWithMoodAsync("Bé làm tốt lắm!", VoiceMood.Happy); // Đọc đúng text

            await MainThread.InvokeOnMainThreadAsync(async () =>
            {
                if (token.IsCancellationRequested || !_isGameActive) return;
                await CongratulationBorder.ScaleToAsync(1.0, 600, Easing.SpringOut);
                if (token.IsCancellationRequested || !_isGameActive) return;
                await StarsLabel.RotateToAsync(360, 1000, Easing.CubicOut);
            });

            if (token.IsCancellationRequested || !_isGameActive) return;

            // Đợi các tác vụ nền hoàn thành và thêm thời gian hiển thị
            await Task.WhenAll(soundTask, ttsTask, Task.Delay(1500, token));

            if (token.IsCancellationRequested || !_isGameActive) return;

            await MainThread.InvokeOnMainThreadAsync(async () =>
            {
                await CongratulationBorder.ScaleToAsync(0, 200, Easing.CubicIn);
            });
        }
        catch (TaskCanceledException)
        {
            // Bình thường nếu token bị hủy thì sẽ vào catch này, không cần log lỗi
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"ShowCongratulationsDialogAsync error: {ex}");
        }
        finally
        {
            await MainThread.InvokeOnMainThreadAsync(() =>
            {
                CongratulationOverlay.IsVisible = false;
            });
        }
    }
}