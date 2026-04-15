using LamToanLop1.Pages;

namespace LamToanLop1;

public partial class AppShell : Shell
{
	public AppShell()
	{
		InitializeComponent();

        // Đăng ký đường dẫn cho các trang con
        Routing.RegisterRoute(nameof(GamePage), typeof(GamePage));
		Routing.RegisterRoute(nameof(AnimalPage), typeof(AnimalPage));
		Routing.RegisterRoute(nameof(MainPage), typeof(MainPage));

        // Mặc định hiển thị SplashPage
        this.CurrentItem = this.Items[0]; // SplashPage là item đầu tiên
	}
}