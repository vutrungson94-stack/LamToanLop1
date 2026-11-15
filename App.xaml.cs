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
        try
        {
            var healer = serviceProvider.GetService<ISelfHealingService>();
            healer?.AttachGlobalHandlers();
            if (healer != null && healer.GetCrashCount() > 0)
            {
                healer.TryRecover();
            }
        }
        catch (Exception ex) { Debug.WriteLine($"[SELF-HEAL] Init failed: {ex}"); }
    }

    protected override Window CreateWindow(IActivationState? activationState)
    {
        try
        {
            var _appShell = _serviceProvider.GetRequiredService<AppShell>();
            var _window = new Window(_appShell);
            Shell.SetNavBarIsVisible(_appShell, false);
            return _window;
        }
        catch (Exception ex)
        {
            _serviceProvider.GetService<ISelfHealingService>()?.LogCrash(ex, "CreateWindow");
            Debug.WriteLine($"[FATAL] CreateWindow failed: {ex}");
            // Fallback window để không crash trên máy cũ khi DI lỗi (ví dụ AudioManager)
            var fallback = new ContentPage
            {
                Content = new Label
                {
                    Text = "Đang khởi động lại... Vui lòng mở lại ứng dụng.",
                    HorizontalOptions = LayoutOptions.Center,
                    VerticalOptions = LayoutOptions.Center,
                    Padding = 20
                }
            };
            return new Window(fallback);
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
