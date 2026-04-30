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
        private readonly List<IAudioPlayer> _activePlayers = [];
        private readonly Lock _lock = new();

        public async Task PlayPhaoAsync() => await PlaySoundOneShotAsync("tieng_phao_no.mp3");
        public async Task PlayVoTayAsync() => await PlaySoundOneShotAsync("tieng_vo_tay.mp3");

        public void StopAll()
        {
            lock (_lock)
            {
                foreach (var p in _activePlayers)
                {
                    try { if (p.IsPlaying) p.Stop(); p.Dispose(); } catch { }
                }
                _activePlayers.Clear();
            }
        }

        private async Task PlaySoundOneShotAsync(string soundFileName)
        {
            if (_audioManager == null) { Debug.WriteLine("AudioManager is null"); return; }
            try
            {
                if (await FileSystem.AppPackageFileExistsAsync(soundFileName))
                {
                    using var stream = await FileSystem.OpenAppPackageFileAsync(soundFileName);
                    var player = _audioManager.CreatePlayer(stream);

                    lock (_lock) _activePlayers.Add(player);

                    player.PlaybackEnded += (s, e) =>
                    {
                        lock (_lock)
                        {
                            if (_activePlayers.Remove(player))
                            {
                                try { player.Dispose(); } catch { }
                            }
                        }
                    };
                    player.Play();
                }
            }
            catch (Exception ex) { Debug.WriteLine($"Sound Error: {ex.Message}"); }
        }
    }
}