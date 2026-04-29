using LamToanLop1.Services;

namespace LamToanLop1;

public partial class App : Microsoft.Maui.Controls.Application
{
    // Sự kiện tĩnh để các trang con có thể đăng ký lắng nghe
    public static event Action? AppHidden;

    // Sự kiện báo App đã quay lại -> THÊM DÒNG NÀY
    public static event Action? AppResumed;

    private readonly ITtsService _ttsService;
    private readonly ISoundService _soundService;
    private readonly AppShell _appShell;

    public App(AppShell appShell, ITtsService ttsService, ISoundService soundService)
    {
        InitializeComponent();
        _ttsService = ttsService;
        _soundService = soundService;
        _appShell = appShell;
    }

    protected override Window CreateWindow(IActivationState? activationState)
    {
        return new Window(_appShell);
    }

    protected override void OnSleep()
	{
        base.OnSleep();
        // Bắn tín hiệu cho GamePage biết để tạm dừng vòng lặp
        _ttsService.Stop();
        _soundService.StopAll();
        AppHidden?.Invoke();
    }

    protected override void OnResume()
    {
        base.OnResume();
        // Bắn tín hiệu cho GamePage biết để tiếp tục vòng lặp
        AppResumed?.Invoke();
    }
}