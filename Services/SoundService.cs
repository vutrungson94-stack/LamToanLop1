using Plugin.Maui.Audio;

namespace LamToanLop1.Services
{
    // 1. Tạo Interface
    public interface ISoundService
    {
        Task PlayPhaoAsync();
        Task PlayVoTayAsync();

        // Hàm ra lệnh dừng toàn bộ âm thanh hiệu ứng
        void StopAll();
    }

    public class SoundService(IAudioManager audioManager) : ISoundService
    {
        private readonly IAudioManager _audioManager = audioManager;

        // Danh sách các âm thanh đang gào thét
        private readonly List<IAudioPlayer> _activePlayers = [];
        private readonly Lock _lock = new(); // Khóa để tránh lỗi đụng độ luồng

        public async Task PlayPhaoAsync()
        {
            await PlaySoundOneShotAsync("tieng_phao_no.mp3");
        }

        public async Task PlayVoTayAsync()
        {
            await PlaySoundOneShotAsync("tieng_vo_tay.mp3");
        }

        public void StopAll()
        {
            lock (_lock)
            {
                foreach (var player in _activePlayers)
                {
                    try
                    {
                        if (player.IsPlaying) player.Stop();
                        player.Dispose();
                    }
                    catch { }
                }
                _activePlayers.Clear();
            }
        }

        private async Task PlaySoundOneShotAsync(string soundFileName)
        {
            try
            {
                if (await FileSystem.AppPackageFileExistsAsync(soundFileName))
                {
                    Stream stream = await FileSystem.OpenAppPackageFileAsync(soundFileName);

                    // Tạo player
                    IAudioPlayer player = _audioManager.CreatePlayer(stream);

                    // 1. Thêm vào danh sách quản lý
                    lock (_lock)
                    {
                        _activePlayers.Add(player);
                    }

                    // Đăng ký sự kiện
                    player.PlaybackEnded += (s, e) =>
                    {
                        bool isRemoved = false;

                        // 1. CHỈ LOCK ĐỂ XÓA KHỎI DANH SÁCH (Cực nhanh)
                        lock (_lock)
                        {
                            // Hàm Remove tự động kiểm tra tồn tại.
                            // Nếu trả về true: Nghĩa là chưa ai xóa -> Tôi có quyền Dispose.
                            // Nếu trả về false: Nghĩa là StopAll() đã xóa rồi -> Tôi không làm gì cả.
                            isRemoved = _activePlayers.Remove(player);
                        }

                        if (isRemoved)
                        {
                            try
                            {
                                player.Dispose();
                                stream.Dispose();
                            }
                            catch { }
                        }
                    };

                    // Phat nhac
                    player.Play();
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Lỗi âm thanh {soundFileName}: " + ex.Message); // Hàm Debug.WriteLine đơn với System.Diagnostics.Debug.WriteLine("ex.Message);
            }
        }
    }
}
