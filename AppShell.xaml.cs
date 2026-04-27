using LamToanLop1.Pages;

namespace LamToanLop1;

public partial class AppShell : Shell
{
	public AppShell()
	{
		InitializeComponent();

        // Đăng ký đường dẫn cho các trang con
		// Lưu ý: SplashPage và MainPage KHÔNG đăng ký ở đây
        // vì đã khai báo trong AppShell.xaml rồi
		Routing.RegisterRoute(nameof(MainPage), typeof(MainPage));
		Routing.RegisterRoute(nameof(GamePage), typeof(GamePage));
		Routing.RegisterRoute(nameof(AnimalPage), typeof(AnimalPage));
	}
}