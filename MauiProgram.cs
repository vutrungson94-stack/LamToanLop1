using LamToanLop1.Services;
using LamToanLop1.ViewModels;
using LamToanLop1.Pages;
using Plugin.Maui.Audio;

namespace LamToanLop1;

public static class MauiProgram
{
	public static MauiApp CreateMauiApp()
	{
		var builder = MauiApp.CreateBuilder();
		builder
			.UseMauiApp<App>()
			.ConfigureFonts(fonts =>
			{
				// Đăng ký 3 "chiến thần" mới
				fonts.AddFont("Nunito-ExtraBold.ttf", "NunitoExtraBold");       // Dùng cho văn bản chính
				fonts.AddFont("PatrickHand-Regular.ttf", "PatrickHandRegular"); // Dùng cho lời khen, tiêu đề vui
				fonts.AddFont("BalooTammudu2-ExtraBold.ttf", "BalooTammudu2ExtraBold");   // Dùng cho SỐ TO, TIÊU ĐỀ LỚN
			});
#if DEBUG
		builder.Logging.AddDebug();
#endif
		builder.Services.AddSingleton(AudioManager.Current); // Đăng ký AudioManager từ Plugin.Maui.Audio

        // ================================================
        // === ĐĂNG KÝ DỊCH VỤ (SINGLETON) ===
        // Singleton: Chỉ có một instance được tạo và tái sử dụng trong toàn bộ ứng dụng.
        // Phù hợp cho các dịch vụ cốt lõi và không lưu trạng thái cụ thể của một trang.
        // ================================================
        builder.Services.AddSingleton<ITtsService, GoogleTtsService>();
		builder.Services.AddSingleton<ISoundService, SoundService>();

        builder.Services.AddSingleton<AppShell>(); // Đăng ký AppShell để có thể lấy instance trong App.xaml.cs
        // ================================================
        // === ĐĂNG KÝ CÁC TRANG VÀ VIEWMODEL ===
        // ================================================
        // Transient vì chỉ hiện một lần rồi bỏ
        builder.Services.AddTransient<SplashPage>();
        builder.Services.AddTransient<MainPage>();
        builder.Services.AddTransient<GamePage>();
        builder.Services.AddTransient<AnimalPage>();
        builder.Services.AddTransient<GameViewModel>();

        return builder.Build();
	}
}