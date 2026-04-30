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
            var progress = new Progress<int>(p =>
            {
                MainThread.BeginInvokeOnMainThread(() =>
                {
                    PreloadProgressBar.Progress = p / 100.0;
                    ProgressLabel.Text = p < 100 ? $"Đang tải giọng đọc... {p}%" : "Hoàn tất!";
                });
            });

            // Chạy preload trên background, giới hạn timeout 8s
            var preloadTask = Task.Run(async () =>
            {
                try
                {
                    var animalNames = GameData.AnimalList.Select(x => x.Value).ToList();
                    await _ttsService.PreCacheAnimalVoicesAsync(animalNames, progress);
                }
                catch (Exception ex) { Debug.WriteLine($"Preload Error: {ex.Message}"); }
            });

            // Đảm bảo splash hiển thị tối thiểu 1.5s cho mượt
            await Task.WhenAny(preloadTask, Task.Delay(8000));
            await Task.Delay(1500);

            await NavigateToAppShell();
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Splash Crash Handled: {ex.Message}");
            await NavigateToAppShell();
        }
    }

    private static async Task NavigateToAppShell()
    {
        try
        {
            await MainThread.InvokeOnMainThreadAsync(async () =>
            {
                if (Shell.Current != null)
                    await Shell.Current.GoToAsync("//MenuPage");
                else
                    Debug.WriteLine("Shell.Current is null. Navigation aborted.");
            });
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Navigation Error: {ex.Message}");
        }
    }
}