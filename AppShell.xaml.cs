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
	}
}