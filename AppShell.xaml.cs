using LamToanLop1.Pages;

namespace LamToanLop1;

public partial class AppShell : Shell
{
	public AppShell()
	{
		InitializeComponent();

		// Thêm mainpage bằng code-behind để đảm bảo nó luôn là trang đầu tiên, không bị ảnh hưởng bởi routing
		Items.Add(new ShellContent
		{
			Title = "",
			Route = "MainPage",
			ContentTemplate = new DataTemplate(typeof(MainPage))
		});

		// Đăng ký đường dẫn cho các trang con
		// Lưu ý: SplashPage và MainPage KHÔNG đăng ký ở đây
        // vì đã khai báo trong AppShell.xaml rồi
		Routing.RegisterRoute(nameof(GamePage), typeof(GamePage));
		Routing.RegisterRoute(nameof(AnimalPage), typeof(AnimalPage));
	}
}