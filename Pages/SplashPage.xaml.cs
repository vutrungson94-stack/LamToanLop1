using LamToanLop1.Models;
using LamToanLop1.Services;
using System.Linq;

namespace LamToanLop1.Pages;

public partial class SplashPage : ContentPage
{
    // tiêm các dich vụ cần thiết vào constructor nếu có, ví dụ:
    private readonly ITtsService _ttsService;
    private readonly IServiceProvider _serviceProvider;

    private bool _isTransitioning;

    public SplashPage(ITtsService ttsService, IServiceProvider serviceProvider)
    {
        InitializeComponent();
        _ttsService = ttsService;
        _serviceProvider = serviceProvider;
    }

    protected override async void OnAppearing()
    {
        base.OnAppearing();

        if (_isTransitioning) return;

        _isTransitioning = true;

        try
        {
            // Cập nhật UI progress từ luồng chính
            var progress = new Progress<int>(p =>
            {
                MainThread.BeginInvokeOnMainThread(() =>
                {
                    PreloadProgressBar.Progress = p / 100.0;
                    ProgressLabel.Text = p < 100 ? $"Đang tải giọng đọc... {p}%" : "Hoàn tất!";
                });
            });

            // Chạy preload trên luồng phụ với timeout 10 giây
            var preloadTask = Task.Run(async () =>
            {
                try
                {
                    var animalNames = GameData.AnimalList.Select(x => x.Value).ToList();
                    await _ttsService.PreCacheAnimalVoicesAsync(animalNames, progress);
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"Preload error: {ex.Message}");
                }
            });

            // Chờ cả hai: tối thiểu 1 giây splash + preload (hoặc timeout 10 giây)
            var delayTask = Task.Delay(1000);
            var timeoutTask = Task.Delay(10000);
            
            // Chờ preload hoàn thành hoặc timeout
            var preloadCompletedTask = await Task.WhenAny(preloadTask, timeoutTask);
            
            // Sau đó chờ thêm delay 1 giây nếu cần
            if (preloadCompletedTask == preloadTask)
            {
                // Preload hoàn thành trước, chờ thêm delay nếu chưa đủ 1 giây
                await delayTask;
            }
            // Nếu timeout, delayTask có thể đã hoàn thành hoặc chưa
            
            // Đảm bảo ít nhất 1 giây đã trôi qua
            await Task.WhenAll(delayTask, Task.CompletedTask);

            // Chuyển sang AppShell (có MainPage bên trong)
            await NavigateToAppShell();
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"SplashPage Error: {ex.Message}");
            // Vẫn chuyển trang dù có lỗi
            await NavigateToAppShell();
        }
    }

    private async Task NavigateToAppShell()
    {
        try
        {
            // Sử dụng Shell navigation để chuyển sang MainPage
            await MainThread.InvokeOnMainThreadAsync(async () =>
            {
                await Shell.Current.GoToAsync("//MainPage");
            });
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Navigation error: {ex.Message}");
        }
    }
}
