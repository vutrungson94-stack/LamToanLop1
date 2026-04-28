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

        
		builder.Services.AddSingleton<IAudioManager>(provider => {
            var manager = AudioManager.Current;
            if (manager == null)
            {
                // Fallback: nếu null, có thể throw hoặc trả về dummy (ở đây ta throw để dễ phát hiện)
                System.Diagnostics.Debug.WriteLine("CRITICAL: AudioManager.Current is null. Plugin may not be initialized.");
                throw new InvalidOperationException("AudioManager.Current is null. Ensure Plugin.Maui.Audio is properly installed and initialized.");
            }
            return manager;
        });
        
        builder.Services.AddSingleton<ITtsService, GoogleTtsService>();
        builder.Services.AddSingleton<ISoundService, SoundService>();

        builder.Services.AddTransient<AppShell>(); // Đăng ký AppShell để có thể lấy instance trong App.xaml.cs
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