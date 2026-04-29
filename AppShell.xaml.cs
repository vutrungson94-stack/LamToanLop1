using LamToanLop1.Pages;

namespace LamToanLop1;

public partial class AppShell : Shell
{
	public AppShell()
	{
		InitializeComponent();

		// SplashPage: trang đầu tiên, cần ITtsService → phải dùng DI factory
        Items.Add(new ShellContent
        {
            Route = "SplashPage",
            ContentTemplate = new DataTemplate(() =>
                IPlatformApplication.Current!.Services
                    .GetRequiredService<SplashPage>())
        });

        // MainPage: cần ITtsService + ISoundService → phải dùng DI factory
        Items.Add(new ShellContent
        {
            Route = "MainPage",
            ContentTemplate = new DataTemplate(() =>
                IPlatformApplication.Current!.Services
                    .GetRequiredService<MainPage>())
        });

		// Đăng ký đường dẫn cho các trang con
		Routing.RegisterRoute(nameof(GamePage), typeof(GamePage));
		Routing.RegisterRoute(nameof(AnimalPage), typeof(AnimalPage));
	}
}