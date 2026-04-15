using LamToanLop1.Models;
using LamToanLop1.Services;

namespace LamToanLop1;

public partial class MainPage : ContentPage
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

    public MainPage(ITtsService tts, ISoundService soundService)
    {
        InitializeComponent();
        _tts = tts;
        _soundService = soundService;
    }

    protected override void OnAppearing()
    {
        base.OnAppearing();
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
        // Hiệu ứng nút bấm
        if (sender is Button btn)
        {
            await btn.ScaleTo(0.9, 100);
            await btn.ScaleTo(1.0, 100);
        }

        MainMenuView.IsVisible = false;
        ModeMenu.IsVisible = true;
    }

    private async void OnAnimalDiscoveryClicked(object sender, EventArgs e)
    {
        if (sender is Button btn)
        {
            await btn.ScaleTo(0.9, 100);
            await btn.ScaleTo(1.0, 100);
        }

        var services = this.Handler?.MauiContext?.Services;
        if (services == null)
        {
            var windows = Application.Current?.Windows;
            var firstWindow = (windows != null && windows.Count > 0) ? windows[0] : null;
            services = firstWindow?.Handler?.MauiContext?.Services;
        }

        if (services == null)
        {
            throw new InvalidOperationException("MAUI services (MauiContext) are not available. Ensure the page is attached to a Window before navigating.");
        }

        var animalPage = services.GetRequiredService<LamToanLop1.Pages.AnimalPage>();

        await Navigation.PushAsync(animalPage);
    }

    // --- 2. CHỌN PHẠM VI (RANGE) ---
    private async void OnBasicModeClicked(object sender, EventArgs e)
    {
        if (sender is Button btn) { await btn.ScaleTo(0.9, 100); await btn.ScaleTo(1.0, 100); }
        _selectedRange = 1; // Tương đương Semester 1 (Phạm vi 10)
        ShowLevelMenu("CƠ BẢN");
    }

    private async void OnAdvancedModeClicked(object sender, EventArgs e)
    {
        if (sender is Button btn) { await btn.ScaleTo(0.9, 100); await btn.ScaleTo(1.0, 100); }
        _selectedRange = 2; // Logic cũ: 2 là phạm vi 100
        ShowLevelMenu("NÂNG CAO");
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
        if (!CanNavigate()) return; // Chặn nếu bấm quá nhanh
        if (sender is Button btn) { await btn.ScaleTo(0.9, 100); await btn.ScaleTo(1.0, 100); }
        await StartGame(1);
    }

    private async void OnLevelMediumClicked(object sender, EventArgs e)
    {
        if (!CanNavigate()) return;
        if (sender is Button btn) { await btn.ScaleTo(0.9, 100); await btn.ScaleTo(1.0, 100); }
        await StartGame(2);
    }

    private async void OnLevelHardClicked(object sender, EventArgs e)
    {
        if (!CanNavigate()) return;
        if (sender is Button btn) { await btn.ScaleTo(0.9, 100); await btn.ScaleTo(1.0, 100); }
        await StartGame(3);
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
        // Prefer the current page's handler/maui context (when attached),
        // fall back to the first application Window's handler if needed.
        var services = this.Handler?.MauiContext?.Services;
        if (services == null)
        {
            var windows = Application.Current?.Windows;
            var firstWindow = (windows != null && windows.Count > 0) ? windows[0] : null;
            services = firstWindow?.Handler?.MauiContext?.Services;
        }

        services = services ?? throw new InvalidOperationException("MAUI services (MauiContext) are not available. Ensure the page is attached to a Window before starting the game.");
        var page = services.GetRequiredService<LamToanLop1.Pages.GamePage>();

        // Prepare the page with parameters and navigate
        page.PrepareGame(_selectedRange, level);

        await Navigation.PushAsync(page);
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
}