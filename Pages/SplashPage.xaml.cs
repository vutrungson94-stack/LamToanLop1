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
            // Hiển thị splash ngắn (500ms) để transition mượt
            await Task.Delay(500);

            // Preload TTS ở background — KHÔNG chặn navigation
            _ = Task.Run(async () =>
            {
                try
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

                    await _ttsService.PreCacheAllGameVoicesAsync(progress);
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"[PreCache Error] {ex.Message}");
                }
            });

            // Navigate ngay lập tức — không chờ preload
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