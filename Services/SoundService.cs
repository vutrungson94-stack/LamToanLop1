using Plugin.Maui.Audio;
using System.Diagnostics;

namespace LamToanLop1.Services
{
    public interface ISoundService
    {
        Task PlayPhaoAsync();
        Task PlayVoTayAsync();
        void StopAll();
    }

    public class SoundService(IAudioManager audioManager) : ISoundService
    {
        private readonly IAudioManager? _audioManager = audioManager;
        private readonly List<(IAudioPlayer player, Stream stream)> _active = [];
        private readonly Lock _lock = new();

        public async Task PlayPhaoAsync() => await PlaySoundOneShotAsync("tieng_phao_no.mp3");
        public async Task PlayVoTayAsync() => await PlaySoundOneShotAsync("tieng_vo_tay.mp3");

        public void StopAll()
        {
            List<(IAudioPlayer player, Stream stream)> copy;
            lock (_lock) { copy = [.. _active]; _active.Clear(); }
            foreach (var (p, s) in copy)
            {
                try { if (p.IsPlaying) p.Stop(); } catch { }
                try { p.Dispose(); } catch { }
                try { s.Dispose(); } catch { }
            }
        }

        private async Task PlaySoundOneShotAsync(string soundFileName)
        {
            if (_audioManager == null) { Debug.WriteLine("AudioManager is null (silent)"); return; }
            Stream? stream = null;
            IAudioPlayer? player = null;
            try
            {
                if (!await FileSystem.AppPackageFileExistsAsync(soundFileName)) return;
                stream = await FileSystem.OpenAppPackageFileAsync(soundFileName);
                // Plugin.Maui.Audio yêu cầu CreatePlayer trên MainThread (API 21) - hiệu ứng nhỏ hơn giọng đọc
                player = await MainThread.InvokeOnMainThreadAsync(() => _audioManager.CreatePlayer(stream));
                if (player == null) { try { stream.Dispose(); } catch { } return; }
                try { player.Volume = 0.7; } catch { }

                lock (_lock) _active.Add((player, stream!));

                // Giữ stream sống cùng player, dispose cả hai khi xong
                var capturedStream = stream;
                var capturedPlayer = player;
                player.PlaybackEnded += (s, e) =>
                {
                    lock (_lock) _active.Remove((capturedPlayer, capturedStream));
                    try { capturedPlayer.Dispose(); } catch { }
                    try { capturedStream.Dispose(); } catch { }
                };

                player.Play();
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Sound Error: {ex.Message}");
                try { player?.Dispose(); } catch { }
                try { stream?.Dispose(); } catch { }
                if (player != null && stream != null) lock (_lock) _active.Remove((player, stream));
            }
        }
    }
}