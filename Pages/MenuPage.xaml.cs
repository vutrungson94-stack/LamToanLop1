using LamToanLop1.Helpers;
using LamToanLop1.Services;

namespace LamToanLop1.Pages;

public partial class MenuPage : ContentPage
{
    // ===============================
    // CORE SERVICES
    // ===============================
    private readonly ITtsService _tts;
    private readonly ISoundService _soundService;

    // [SỬA] Thay biến _isNavigating bằng biến lưu thời gian lần bấm cuối
    private long _lastClickTime = 0;

    // 1 = Cơ bản (PV 10), 2 = Nâng cao (PV 100)
    private int _selectedRange = 1;

    public MenuPage(ITtsService ttsService, ISoundService soundService)
    {
        InitializeComponent();
        _tts = ttsService;
        _soundService = soundService;
        Shell.SetNavBarIsVisible(this, false);
        this.SizeChanged += (_, __) => ApplyResponsive();
    }

    private async void OnVoiceSelectionClicked(object? sender, EventArgs e)
    {
        var preferred = Preferences.Get("preferred_voice", "auto");
        var options = new[]
        {
            "🤖 Tự động (tốt nhất)",
            "Edge TTS (HoaiMy - Neural)",
            "Google TTS (miễn phí)",
            "Viettel AI (cô giáo Quỳnh Anh)",
            "Android TTS (thiết bị)"
        };

        var choice = await DisplayActionSheetAsync("Chọn giọng đọc", "Hủy", null, options);
        if (choice == null || choice == "Hủy") return;

        string pref = choice switch
        {
            "🤖 Tự động (tốt nhất)" => "auto",
            "Edge TTS (HoaiMy - Neural)" => "edge",
            "Google TTS (miễn phí)" => "google",
            "Viettel AI (cô giáo Quỳnh Anh)" => "viettel",
            "Android TTS (thiết bị)" => "android",
            _ => "auto"
        };

        Preferences.Set("preferred_voice", pref);

        // Nguồn cần token: nhắc nhập lần đầu, lưu vào Preferences để GoogleTtsService đọc.
        if (pref == "viettel")
            await EnsureApiKeyAsync("viettel_ai_api_key", "Viettel AI",
                "Dán token lấy tại viettelai.vn/dashboard/token");

        // Phát thử giọng đã chọn
        string testText = "Xin chào! Bé làm toán vui lắm!";
        await _tts.SpeakAsync(testText);
    }

    // Nhập key/token ngay trên app (Preferences không sửa tay được vì APK release không debuggable).
    private async Task EnsureApiKeyAsync(string prefKey, string label, string hint)
    {
        try
        {
            if (!string.IsNullOrWhiteSpace(Preferences.Get(prefKey, ""))) return;
            var value = await DisplayPromptAsync(label, hint, "Lưu", "Hủy");
            if (!string.IsNullOrWhiteSpace(value))
                Preferences.Set(prefKey, value.Trim());
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[KeyInput] {ex.Message}");
        }
    }

    private void ApplyResponsive()
    {
        try
        {
            double s = ResponsiveHelper.Scale;
            // Style base 280x65 -> scale
            foreach (var btn in new[] { btnNumber, btnAnimal, btnMath, btnCoBan, btnNangCao, btnDe, btnVua, btnKho })
            {
                if (btn == null) continue;
                btn.WidthRequest = ResponsiveHelper.W(280);
                btn.HeightRequest = ResponsiveHelper.H(65);
                btn.FontSize = ResponsiveHelper.Font(18);
                btn.CornerRadius = (int)ResponsiveHelper.S(25);
            }
            // Back buttons nhỏ hơn
            foreach (var b in new[] { btnBackToMenu, btnBackToMode })
            {
                if (b == null) continue;
                b.WidthRequest = ResponsiveHelper.W(150);
                b.HeightRequest = ResponsiveHelper.H(50);
                b.FontSize = ResponsiveHelper.Font(16);
                b.CornerRadius = (int)ResponsiveHelper.S(25);
            }
            if (lblMainTitle != null) lblMainTitle.FontSize = ResponsiveHelper.Font(48);
            if (lblModeTitle != null) lblModeTitle.FontSize = ResponsiveHelper.Font(36);
            if (lblLevelTitle != null) lblLevelTitle.FontSize = ResponsiveHelper.Font(32);
        }
        catch { }
    }

    protected override void OnAppearing()
    {
        base.OnAppearing();
        ApplyResponsive();
    }

    // Xử lý nút Back vật lý để quay lại từng cấp Menu
    protected override bool OnBackButtonPressed()
    {
        // Nếu đang ở Menu Chọn Level -> Về Menu Chọn Chế Độ
        if (LevelMenu.IsVisible)
        {
            OnBackToModeClicked(this, EventArgs.Empty);
            return true; // Chặn thoát app
        }

        // Nếu đang ở Menu Chọn Chế Độ -> Về Menu Chính
        if (ModeMenu.IsVisible)
        {
            OnBackToMenuClicked(this, EventArgs.Empty);
            return true; // Chặn thoát app
        }

        // Nếu đang ở Menu Chính -> Cho phép thoát app (trả về false)
        return base.OnBackButtonPressed();
    }

    // --- 1. MỞ MENU PHẠM VI ---
    private async void OnOpenMathMenu(object sender, EventArgs e)
    {
        try
        {
            if (sender is Button btn)
            {
                try { await btn.ScaleToAsync(0.9, 100); await btn.ScaleToAsync(1.0, 100); } catch { }
            }
            MainMenuView.IsVisible = false;
            ModeMenu.IsVisible = true;
        }
        catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"OnOpenMathMenu: {ex.Message}"); }
    }

    private async void OnAnimalDiscoveryClicked(object sender, EventArgs e)
    {
        try
        {
            if (sender is Button btn)
            {
                try { await btn.ScaleToAsync(0.9, 100); await btn.ScaleToAsync(1.0, 100); } catch { }
            }
            if (Shell.Current != null) await Shell.Current.GoToAsync(nameof(AnimalPage));
        }
        catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"OnAnimalDiscoveryClicked: {ex.Message}"); }
    }

    // --- 2. CHỌN PHẠM VI (RANGE) ---
    private async void OnBasicModeClicked(object sender, EventArgs e)
    {
        try
        {
            if (sender is Button btn) { try { await btn.ScaleToAsync(0.9, 100); await btn.ScaleToAsync(1.0, 100); } catch { } }
            _selectedRange = 1;
            ShowLevelMenu("CƠ BẢN");
        }
        catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"OnBasicModeClicked: {ex.Message}"); }
    }

    private async void OnAdvancedModeClicked(object sender, EventArgs e)
    {
        try
        {
            if (sender is Button btn) { try { await btn.ScaleToAsync(0.9, 100); await btn.ScaleToAsync(1.0, 100); } catch { } }
            _selectedRange = 2;
            ShowLevelMenu("NÂNG CAO");
        }
        catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"OnAdvancedModeClicked: {ex.Message}"); }
    }

    private void ShowLevelMenu(string title)
    {
        ModeMenu.IsVisible = false;
        LevelMenu.IsVisible = true;
        lblLevelTitle.Text = title;
    }

    // --- 3. CHỌN ĐỘ KHÓ & VÀO GAME ---
    private async void OnLevelEasyClicked(object sender, EventArgs e)
    {
        try
        {
            if (!CanNavigate()) return;
            if (sender is Button btn) { try { await btn.ScaleToAsync(0.9, 100); await btn.ScaleToAsync(1.0, 100); } catch { } }
            await StartGame(1);
        }
        catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"OnLevelEasyClicked: {ex.Message}"); }
    }

    private async void OnLevelMediumClicked(object sender, EventArgs e)
    {
        try
        {
            if (!CanNavigate()) return;
            if (sender is Button btn) { try { await btn.ScaleToAsync(0.9, 100); await btn.ScaleToAsync(1.0, 100); } catch { } }
            await StartGame(2);
        }
        catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"OnLevelMediumClicked: {ex.Message}"); }
    }

    private async void OnLevelHardClicked(object sender, EventArgs e)
    {
        try
        {
            if (!CanNavigate()) return;
            if (sender is Button btn) { try { await btn.ScaleToAsync(0.9, 100); await btn.ScaleToAsync(1.0, 100); } catch { } }
            await StartGame(3);
        }
        catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"OnLevelHardClicked: {ex.Message}"); }
    }

    // Kiểm tra xem có được phép chuyển trang không
    private bool CanNavigate()
    {
        long now = DateTime.Now.Ticks / 10000; // Đổi ra mili-giây
        if (now - _lastClickTime < 1000) return false; // Nếu chưa đủ 1 giây thì chặn
        _lastClickTime = now;
        return true;
    }

    private async Task StartGame(int level)
    {
        if (Shell.Current != null)
        {
            await Shell.Current.GoToAsync($"{nameof(GamePage)}?range={_selectedRange}&level={level}");
        }
    }

    // --- CÁC NÚT QUAY LẠI ---
    private void OnBackToMenuClicked(object sender, EventArgs e)
    {
        ModeMenu.IsVisible = false;
        MainMenuView.IsVisible = true;
    }

    private void OnBackToModeClicked(object sender, EventArgs e)
    {
        LevelMenu.IsVisible = false;
        ModeMenu.IsVisible = true;
    }

    private async void OnNumberDiscoveryClicked(object sender, EventArgs e)
    {
        try
        {
            if (sender is Button btn)
            {
                try { await btn.ScaleToAsync(0.9, 50); await btn.ScaleToAsync(1.0, 50); } catch { }
            }
            if (Shell.Current != null) await Shell.Current.GoToAsync(nameof(NumberPage));
        }
        catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"OnNumberDiscoveryClicked: {ex.Message}"); }
    }
}