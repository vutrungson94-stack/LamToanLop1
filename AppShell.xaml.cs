using LamToanLop1.Pages;

namespace LamToanLop1;

public partial class AppShell : Shell
{
	public AppShell(IServiceProvider serviceProvider)
	{
		InitializeComponent();

		// SplashPage: trang đầu tiên, cần ITtsService → phải dùng DI factory
        Items.Add(new ShellContent
        {
            Route = "SplashPage",
            ContentTemplate = new DataTemplate(() =>
                serviceProvider.GetRequiredService<SplashPage>())
        });

        // MenuPage: cần ITtsService + ISoundService → phải dùng DI factory
        Items.Add(new ShellContent
        {
            Route = "MenuPage",
            ContentTemplate = new DataTemplate(() =>
                serviceProvider.GetRequiredService<MenuPage>())
        });

		// Đăng ký đường dẫn cho các trang con
		Routing.RegisterRoute(nameof(GamePage), typeof(GamePage));
		Routing.RegisterRoute(nameof(AnimalPage), typeof(AnimalPage));
	}
}