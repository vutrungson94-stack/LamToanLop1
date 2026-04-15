#if ANDROID
using Android.Media;
using System.Runtime.Versioning;

namespace LamToanLop1.Platforms.Android
{
    public sealed class AudioFocusHelper : Java.Lang.Object, global::Android.Media.AudioManager.IOnAudioFocusChangeListener
    {
        private readonly global::Android.Media.AudioManager _audioManager;
        private global::Android.Media.AudioFocusRequestClass? _focusRequest; // Dành cho Android 8.0+ (API 26+)
        private bool _hasFocus;

        public AudioFocusHelper()
        {
            // [SỬA LỖI] Thêm 'global::' để tránh xung đột tên namespace
            // Hệ thống sẽ hiểu là lấy từ gốc Android SDK chứ không phải folder trong project
            var context = global::Android.App.Application.Context;
            _audioManager = (global::Android.Media.AudioManager)context.GetSystemService(global::Android.Content.Context.AudioService)!;
        }

        public bool RequestFocus()
        {
            if (_hasFocus) return true;

            int result;

#pragma warning disable CA1416, CA1422 // Tắt cảnh báo về hàm lỗi thời
            // KIỂM TRA PHIÊN BẢN ANDROID
            if (global::Android.OS.Build.VERSION.SdkInt >= global::Android.OS.BuildVersionCodes.O) // Android 8.0+
            {
                // Gọi hàm mới (đã được tách riêng bên dưới)
                result = RequestFocusNew();
            }
            else
            {
                // Dùng hàm cũ cho Android dưới 8.0
                result = (int)_audioManager.RequestAudioFocus(
                    this,
                    global::Android.Media.Stream.Music,
                    global::Android.Media.AudioFocus.GainTransient);
            }
#pragma warning restore CA1416, CA1422

            _hasFocus = result == (int)global::Android.Media.AudioFocusRequest.Granted;
            return _hasFocus;
        }

        // Hàm riêng cho Android 26+ để trình biên dịch không báo lỗi
        [SupportedOSPlatform("android26.0")]
        private int RequestFocusNew()
        {
            var attributes = new global::Android.Media.AudioAttributes.Builder()
                ?.SetUsage(global::Android.Media.AudioUsageKind.Media)
                ?.SetContentType(global::Android.Media.AudioContentType.Speech)
                ?.Build();

            if (attributes != null)
            {
                _focusRequest = new global::Android.Media.AudioFocusRequestClass.Builder(AudioFocus.GainTransient)
                    .SetAudioAttributes(attributes)
                    .SetAcceptsDelayedFocusGain(false)
                    .SetOnAudioFocusChangeListener(this)
                    .Build();

                return (int)_audioManager.RequestAudioFocus(_focusRequest!);
            }
            return (int)global::Android.Media.AudioFocusRequest.Failed;
        }

        public void AbandonFocus()
        {
            if (!_hasFocus) return;

            // Tắt cảnh báo kiểm tra phiên bản (CA1416) và hàm lỗi thời (CA1422)
            // Vì ta đã tự kiểm tra thủ công bằng if/else rồi
#pragma warning disable CA1416, CA1422
            if (global::Android.OS.Build.VERSION.SdkInt >= global::Android.OS.BuildVersionCodes.O)
            {
                AbandonFocusNew();
            }
            else
            {
                _audioManager.AbandonAudioFocus(this);
            }
#pragma warning restore CA1416, CA1422 // Bật lại cảnh báo sau khi xong việc

            _hasFocus = false;
        }

        // Hàm riêng cho Android 26+
        [SupportedOSPlatform("android26.0")]
        private void AbandonFocusNew()
        {
            if (_focusRequest != null)
            {
                _audioManager.AbandonAudioFocusRequest(_focusRequest);
            }
        }

        public void OnAudioFocusChange(AudioFocus focusChange)
        {
            // Xử lý khi bị ứng dụng khác chiếm âm thanh (VD: Cuộc gọi đến)
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                AbandonFocus();
            }
            base.Dispose(disposing);
        }
    }
}
#endif