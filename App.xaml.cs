namespace LamToanLop1;

public partial class App : Microsoft.Maui.Controls.Application
{
    // Sự kiện tĩnh để các trang con có thể đăng ký lắng nghe
    public static event Action? AppHidden;

    // Sự kiện báo App đã quay lại -> THÊM DÒNG NÀY
    public static event Action? AppResumed;

    private readonly AppShell _appShell;

    public App(AppShell appShell)
    {
        InitializeComponent();
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
        AppHidden?.Invoke();
    }

    protected override void OnResume()
    {
        base.OnResume();
        // Bắn tín hiệu cho GamePage biết để tiếp tục vòng lặp
        AppResumed?.Invoke();
    }
}