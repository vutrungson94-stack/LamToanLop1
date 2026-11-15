using LamToanLop1.Services;
using System.Diagnostics;

namespace LamToanLop1.Pages;

public partial class SplashPage : ContentPage
{
    private readonly ITtsService _ttsService;
    private bool _isTransitioning;

    public SplashPage(ITtsService ttsService)
    {
        InitializeComponent();
        _ttsService = ttsService;
    }

    protected override async void OnAppearing()
    {
        base.OnAppearing();
        if (_isTransitioning) return;
        _isTransitioning = true;

        try
        {
            await InitializeSplashAsync();
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Splash Crash Handled: {ex.Message}");
            await SplashPage.NavigateToMenu();
        }
    }

    private async Task InitializeSplashAsync()
    {
        var progress = new Progress<int>(p =>
        {
            MainThread.BeginInvokeOnMainThread(() =>
            {
                try
                {
                    if (PreloadProgressBar != null) PreloadProgressBar.Progress = p / 100.0;
                    if (ProgressLabel != null) ProgressLabel.Text = p < 100 ? $"Đang tải... {p}%" : "OK!";
                }
                catch { }
            });
        });

        // Preload TTS với timeout 8s
        var preloadTask = Task.Run(async () =>
        {
            try
            {
                // Pre-cache toàn bộ giọng đọc: số, con vật, câu hỏi/đáp án, lời khen
                await _ttsService.PreCacheAllGameVoicesAsync(progress);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[PreCache Error] {ex.Message}");
            }
        });

        // Chờ preload hoặc timeout
        await Task.WhenAny(preloadTask, Task.Delay(8000));
        
        // Đảm bảo splash hiển thị ít nhất 1s
        await Task.Delay(1000);
        
        await SplashPage.NavigateToMenu();
    }

    private static async Task NavigateToMenu()
    {
        try
        {
            await MainThread.InvokeOnMainThreadAsync(static async () =>
            {
                if (Shell.Current?.CurrentPage?.GetType() != typeof(MenuPage))
                {
                    await Shell.Current.GoToAsync("//MenuPage");
                }
            });
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[Nav Error] {ex.Message}");
        }
    }
}