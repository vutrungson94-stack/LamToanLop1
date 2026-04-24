namespace LamToanLop1.Platforms.Android
{
    // Sử dụng global:: để chỉ định thư viện Android hệ thống, tránh xung đột với namespace hiện tại
    [global::Android.App.Activity(
        Theme = "@style/MainTheme",
        MainLauncher = true,
        LaunchMode = global::Android.Content.PM.LaunchMode.SingleTop,
        ConfigurationChanges = global::Android.Content.PM.ConfigChanges.ScreenSize |
                               global::Android.Content.PM.ConfigChanges.Orientation |
                               global::Android.Content.PM.ConfigChanges.UiMode |
                               global::Android.Content.PM.ConfigChanges.ScreenLayout |
                               global::Android.Content.PM.ConfigChanges.SmallestScreenSize |
                               global::Android.Content.PM.ConfigChanges.Density)]
    public class MainActivity : MauiAppCompatActivity
    {
    }
}
