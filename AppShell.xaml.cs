using LamToanLop1.Pages;

namespace LamToanLop1;

public partial class AppShell : Shell
{
	public AppShell(IServiceProvider serviceProvider)
	{
		InitializeComponent();

        // Ẩn Navigation Bar cho toàn bộ ứng dụng
        Shell.SetNavBarIsVisible(this, false);
        Shell.SetTabBarIsVisible(this, false);

		// SplashPage: trang đầu tiên, cần ITtsService → phải dùng DI factory
        Items.Add(new ShellContent
        {
            Route = "SplashPage",
            ContentTemplate = new DataTemplate(() =>
            {
                try
                {
                    return serviceProvider.GetRequiredService<SplashPage>();
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"Error creating SplashPage: {ex.Message}");
                    // Fallback nếu có lỗi: tạo SplashPage thủ công với null services (có thể handle null trong SplashPage)
                    return new ContentPage { Content = new Label { Text = "Error loading SplashPage" } };
                }
            })
        });

        // MenuPage: cần ITtsService + ISoundService → phải dùng DI factory
        Items.Add(new ShellContent
        {
            Route = "MenuPage",
            ContentTemplate = new DataTemplate(() =>
            {
                try
                {
                    return serviceProvider.GetRequiredService<MenuPage>();
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"Error creating MenuPage: {ex.Message}");
                    // Fallback nếu có lỗi: tạo MenuPage thủ công với null services (có thể handle null trong MenuPage)
                    return new ContentPage { Content = new Label { Text = "Error loading MenuPage" } };
                }
            })
        });

		// Đăng ký đường dẫn cho các trang con
		Routing.RegisterRoute(nameof(GamePage), typeof(GamePage));
		Routing.RegisterRoute(nameof(AnimalPage), typeof(AnimalPage));
	}
}