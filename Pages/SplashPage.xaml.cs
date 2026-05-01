using LamToanLop1.Models;
using LamToanLop1.Services;
using System.Diagnostics;
using System.Linq;

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
                PreloadProgressBar.Progress = p / 100.0;
                ProgressLabel.Text = p < 100 ? $"Đang tải... {p}%" : "OK!";
            });
        });

        // Preload TTS với timeout 8s
        var preloadTask = Task.Run(async () =>
        {
            try
            {
                var animals = GameData.AnimalList.Select(x => x.Value).ToList();
                await _ttsService.PreCacheAnimalVoicesAsync(animals, progress);
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