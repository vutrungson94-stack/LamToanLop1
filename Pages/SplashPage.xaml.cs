using LamToanLop1.Services;
using System.Diagnostics;

namespace LamToanLop1.Pages;

public partial class SplashPage : ContentPage
{
    private readonly ITtsService _ttsService;
    private bool _isTransitioning;
    private volatile bool progressStopped;

    public SplashPage(ITtsService ttsService)
    {
        InitializeComponent();
        _ttsService = ttsService;
    }

    protected override void OnDisappearing()
    {
        progressStopped = true;
        base.OnDisappearing();
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
            // Delay ngắn để splash kịp hiển thị, rồi vào Menu ngay (không chờ preload TTS)
            await Task.Delay(300);

            // Navigate trước để giao diện chính render xong — preload chạy sau đó ở background.
            // Trì hoãn 2s tránh cạnh tranh CPU/mạng/I/O với lúc MenuPage vừa khởi tạo (~950 file TTS).
            await SplashPage.NavigateToMenu();

            _ = Task.Run(async () =>
            {
                try
                {
                    await Task.Delay(2000);

                    // Không cập nhật progress sau khi đã rời splash: tránh dispatch lên UI thread
                    // của các control không còn hiển thị (churn trong suốt quá trình preload).
                    var progress = new Progress<int>(p =>
                    {
                        if (progressStopped) return;
                        MainThread.BeginInvokeOnMainThread(() =>
                        {
                            try
                            {
                                if (progressStopped) return;
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