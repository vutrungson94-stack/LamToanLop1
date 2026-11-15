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
                // ✅ Thêm font khi build (Resources/Fonts luôn có sẵn)
                fonts.AddFont("Nunito-ExtraBold.ttf", "NunitoExtraBold");
                fonts.AddFont("PatrickHand-Regular.ttf", "PatrickHandRegular");
                fonts.AddFont("BalooTammudu2-ExtraBold.ttf", "BalooTammudu2ExtraBold");
                fonts.AddFont("Fredoka-Bold.ttf", "FredokaBold");
            });

        // 🎵 DI Audio Manager - resilient cho mọi thiết bị (cũ/mới, API 21+)
        // Trên một số máy cũ / emulator không có audio hardware, AudioManager.Current có thể null/throw.
        // Trả về null! nhưng SoundService/GoogleTtsService đã check null nên app vẫn chạy (chỉ mất tiếng), không crash.
        builder.Services.AddSingleton<IAudioManager>(_ =>
        {
            try
            {
                var audioManager = AudioManager.Current;
                if (audioManager != null) return audioManager;
                Debug.WriteLine("[Audio] AudioManager.Current null -> dùng fallback silent (không crash)");
                return null!; // fallback silent, SoundService sẽ bỏ qua phát tiếng
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"[Audio] AudioManager Init Failed (fallback silent): {ex.Message}");
                return null!; // không throw để app vẫn mở được trên máy cũ
            }
        });

        // 🔊 Đăng ký Service với Null-Safety
        // Self-healing service (L5): crash logging, recovery, retry
        builder.Services.AddSingleton<ISelfHealingService, SelfHealingService>();

        builder.Services.AddSingleton<ISoundService, SoundService>();
        builder.Services.AddSingleton<ITtsService, GoogleTtsService>();

        // 📱 DI Shell & Pages
        builder.Services.AddSingleton<AppShell>();
        builder.Services.AddTransient<SplashPage>();
        builder.Services.AddTransient<MenuPage>();
        builder.Services.AddTransient<GamePage>();
        builder.Services.AddTransient<AnimalPage>();
        builder.Services.AddTransient<NumberPage>();
        builder.Services.AddTransient<GameViewModel>();

        return builder.Build();
    }
}
