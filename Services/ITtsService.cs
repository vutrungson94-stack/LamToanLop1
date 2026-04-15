namespace LamToanLop1.Services
{
    public interface ITtsService
    {
    	Task SpeakAsync(string text);
        Task SpeakWithMoodAsync(string v, VoiceMood mood);
        Task PreCacheAnimalVoicesAsync(
            IEnumerable<string> animalNames,
            IProgress<int>? progress = null,
            CancellationToken cancellationToken = default);
        void Stop(); // Thêm hàm này để xử lý lỗi dừng đọc
    }
}
