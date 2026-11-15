namespace LamToanLop1.Services
{
    public interface ITtsService
    {
    	Task SpeakAsync(string text);
        // Pre-cache toàn bộ giọng đọc của game (số, con vật, câu hỏi, lời khen...)
        Task PreCacheAllGameVoicesAsync(
            IProgress<int>? progress = null,
            CancellationToken cancellationToken = default);
        Task PreCacheNumberVoicesAsync(
            IProgress<int>? progress = null,
            CancellationToken cancellationToken = default);
        void Stop(); // Thêm hàm này để xử lý lỗi dừng đọc
    }
}
