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

        // Cập nhật UI progress từ luồng chính
        var progress = new Progress<int>(p =>
        {
            MainThread.BeginInvokeOnMainThread(() =>
            {
                PreloadProgressBar.Progress = p / 100.0;
                ProgressLabel.Text = p < 100 ? $"Đang tải giọng đọc... {p}%" : "Hoàn tất!";
            });
        });

        // Chạy preload trên luồng phụ, đồng thời hiển thị Splash tối thiểu 2 giây
        var preloadTask = Task.Run(async () =>
        {
            var animalNames = GameData.AnimalList.Select(x => x.Value).ToList();
            await _ttsService.PreCacheAnimalVoicesAsync(animalNames, progress);
        });

        // Chờ cả hai: đủ thời gian splash + preload xong
        await Task.WhenAll(Task.Delay(2000), preloadTask);

        // Chuyển sang AppShell (có MainPage bên trong)
        // Dùng IServiceProvider để AppShell được tạo với đầy đủ DI
        var appShell = _serviceProvider.GetRequiredService<AppShell>();
        
        MainThread.BeginInvokeOnMainThread(() =>
        {
            var window = Application.Current?.Windows.FirstOrDefault();
            if (window != null)
            {
                window.Page = appShell;
            }
            else
            {
                Application.Current!.MainPage = appShell;
            }
        });
    }
}
