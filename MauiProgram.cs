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
                fonts.AddFont("Nunito-ExtraBold.ttf", "NunitoExtraBold");
                fonts.AddFont("PatrickHand-Regular.ttf", "PatrickHandRegular");
                fonts.AddFont("BalooTammudu2-ExtraBold.ttf", "BalooTammudu2ExtraBold");
            });

        // Đăng ký AudioManager thật (không dùng factory throw)
        // Android luôn có AudioManager, sẽ không null
        builder.Services.AddSingleton<IAudioManager>(_ =>
        {
            try
            {
                return AudioManager.Current;
            }
            catch
            {
                return AudioManager.Current; // Fallback: vẫn trả về AudioManager.Current, có thể handle null trong SoundService nếu thực sự không có
            }
        });

        // Đăng ký các service thật (nếu bạn đã sửa các lỗi trước đó, chúng sẽ hoạt động)
        builder.Services.AddSingleton<ITtsService, GoogleTtsService>();
        builder.Services.AddSingleton<ISoundService, SoundService>();

        builder.Services.AddSingleton<AppShell>();

        builder.Services.AddTransient<SplashPage>();
        builder.Services.AddTransient<MenuPage>();
        builder.Services.AddTransient<GamePage>();
        builder.Services.AddTransient<AnimalPage>();
        builder.Services.AddTransient<GameViewModel>();

        return builder.Build();
    }
}