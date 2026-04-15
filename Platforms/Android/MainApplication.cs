namespace LamToanLop1.Platforms.Android
{
    [global::Android.App.Application(UsesCleartextTraffic = true)]
    public class MainApplication(IntPtr handle, global::Android.Runtime.JniHandleOwnership ownership) : MauiApplication(handle, ownership)
    {
        protected override MauiApp CreateMauiApp() => MauiProgram.CreateMauiApp();
    }
}
