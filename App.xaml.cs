using LamToanLop1.Services;
using System.Diagnostics;

namespace LamToanLop1;

public partial class App : Microsoft.Maui.Controls.Application
{
    public static event Action? AppHidden;
    public static event Action? AppResumed;

    private readonly IServiceProvider _serviceProvider;

    public App(IServiceProvider serviceProvider)
    {
        InitializeComponent();
        _serviceProvider = serviceProvider;

        // 🔥 ẨN NAVIGATION BAR TOÀN CỤC
        Microsoft.Maui.Controls.Shell.SetNavBarIsVisible(this, false);
    }

    protected override Window CreateWindow(IActivationState? activationState)
    {
        try
        {
            var appShell = _serviceProvider.GetRequiredService<AppShell>();
            return new Window(appShell);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"❌ CreateWindow Failed: {ex.Message}\n{ex.StackTrace}");
            // Fallback: Trả về trang trống để app không văng, user có thể đọc log
            return new Window(new ContentPage { Content = new Label { Text = $"Lỗi khởi động: {ex.Message}", TextColor = Colors.Red } });
        }
    }

    protected override void OnSleep()
    {
        base.OnSleep();
        try
        {
            _serviceProvider.GetService<ITtsService>()?.Stop();
            _serviceProvider.GetService<ISoundService>()?.StopAll();
            AppHidden?.Invoke();
        }
        catch (Exception ex) { Debug.WriteLine($"OnSleep Error: {ex.Message}"); }
    }

    protected override void OnResume()
    {
        base.OnResume();
        try { AppResumed?.Invoke(); }
        catch (Exception ex) { Debug.WriteLine($"OnResume Error: {ex.Message}"); }
    }
}