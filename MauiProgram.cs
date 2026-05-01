using LamToanLop1.Services;
using LamToanLop1.ViewModels;
using LamToanLop1.Pages;
using Plugin.Maui.Audio;
using System.Diagnostics;

namespace LamToanLop1;

public static class MauiProgram
{
    public static MauiApp CreateMauiApp()
    {
        // 🛡️ BẮT LỖI TOÀN CỤC NGAY TỪ KHI KHỞI CHẠY
        AppDomain.CurrentDomain.UnhandledException += (s, e) =>
            Debug.WriteLine($"[FATAL] {e.ExceptionObject}");
        TaskScheduler.UnobservedTaskException += (s, e) =>
            Debug.WriteLine($"[TASK ERROR] {e.Exception}");

        var builder = MauiApp.CreateBuilder();
        builder
            .UseMauiApp<App>()
            .ConfigureFonts(fonts =>
            {
                // ✅ Thêm kiểm tra tồn tại file để tránh crash khi thiếu font
                var fontDir = Path.Combine(FileSystem.AppDataDirectory, "..", "Resources", "Fonts");
                if (Directory.Exists(fontDir))
                {
                    fonts.AddFont("Nunito-ExtraBold.ttf", "NunitoExtraBold");
                    fonts.AddFont("PatrickHand-Regular.ttf", "PatrickHandRegular");
                    fonts.AddFont("BalooTammudu2-ExtraBold.ttf", "BalooTammudu2ExtraBold");
                }
            });

        // 🎵 DI Audio Manager an toàn (tránh ném null reference)
        builder.Services.AddSingleton<IAudioManager>(_ =>
        {
            try 
            { 
                var audioManager = AudioManager.Current;
                return audioManager ?? throw new InvalidOperationException("AudioManager not available on this device.");
            }
            catch (Exception ex) 
            { 
                Debug.WriteLine($"AudioManager Init Failed: {ex.Message}"); 
                return null!; 
            }
        });

        // 🔊 Đăng ký Service với Null-Safety
        builder.Services.AddSingleton<ISoundService, SoundService>();
        builder.Services.AddSingleton<ITtsService, GoogleTtsService>();

        // 📱 DI Shell & Pages
        builder.Services.AddSingleton<AppShell>();
        builder.Services.AddTransient<SplashPage>();
        builder.Services.AddTransient<MenuPage>();
        builder.Services.AddTransient<GamePage>();
        builder.Services.AddTransient<AnimalPage>();
        builder.Services.AddTransient<GameViewModel>();

        return builder.Build();
    }
}