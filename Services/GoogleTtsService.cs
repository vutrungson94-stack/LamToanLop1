using LamToanLop1.Models;
using Plugin.Maui.Audio;
using System.Diagnostics;
using System.Net.WebSockets;
using System.Security.Cryptography;

namespace LamToanLop1.Services
{
	public sealed partial class GoogleTtsService : ITtsService, IDisposable
    {
        private static int Randomize(int baseValue, int range = 2 ) => baseValue + System.Random.Shared.Next(-range, range + 1);

        private readonly IAudioManager _audioManager;
		private IAudioPlayer? _player;
		private Stream? _stream;

        // Dùng cho Google Translate (Backup)
        private static readonly HttpClient _httpClient = new()
        {
            Timeout = TimeSpan.FromSeconds(10),
            DefaultRequestHeaders =
            {
                {"User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" }
            }
        }; 

		// Khóa luồng để không bị chồng chéo giọng đọc
		private CancellationTokenSource? _speakCts;
		private readonly SemaphoreSlim _speakLock = new(1, 1);

        // Task để theo dõi việc đang phát nhạc (để hủy nhanh)
        private TaskCompletionSource<bool>? _playbackTcs;

        // CẤU HÌNH EDGE TTS (HOÀI MY)
        private const string VOICE_EDGE = "vi-VN-HoaiMyNeural";
		// Token này giả lập trình duyệt Edge chính chủ
		private const string EDGE_URL = "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1?TrustedClientToken=6A5AA1D4EAFF4E9FB37E23D68491D6F4";
        private const string PREF_NUMBER_CACHE_READY = "number_voice_cache_ready";
        private const string PREF_GAME_CACHE_READY = "game_voice_cache_ready";

        // Hộp thoại chúc mừng hiển thị "GIỎI QUÁ!" + "Bé làm tốt lắm!" - đọc đúng nội dung hộp thoại
        public const string PRAISE_PHRASE = "Giỏi quá! Bé làm tốt lắm!";
        public const string WRONG_PHRASE = "Chưa đúng rồi, bé thử lại nhé!";
        public const string SKIP_PHRASE = "Mình chuyển câu khác nhé!";
       
        private EventHandler? _currentPlaybackHandler;

        public GoogleTtsService(IAudioManager audioManager)
        {
            _audioManager = audioManager; // có thể null trên máy cũ -> xử lý silent
            // Chạy cleanup an toàn trên threadpool, không block UI thread
            Task.Run(async () =>
            {
                await Task.Delay(3000);
                try { CleanupOldCache(3); } catch { }
            });
        }

        // Hàm dọn dẹp file rác quá hạn (mặc định 3 ngày) - resilient cho máy cũ
        private static void CleanupOldCache(int maxAgeDays = 3)
        {
            try
            {
                var cacheDir = FileSystem.CacheDirectory;
                if (string.IsNullOrEmpty(cacheDir) || !Directory.Exists(cacheDir)) return;

                var dirInfo = new DirectoryInfo(cacheDir);

                // Lấy các file .mp3 chưa được truy cập trong 'maxAgeDays' ngày qua
                var oldFiles = dirInfo.GetFiles("*.mp3")
                                      .Where(f => f.LastAccessTime < DateTime.Now.AddDays(-maxAgeDays));

                foreach (var file in oldFiles)
                {
                    try { file.Delete(); } catch { }
                }
            }
            catch { /* Bỏ qua lỗi nếu không xóa được */ }
        }

        // Pre-cache toàn bộ số 0-100 để khi mất mạng vẫn đọc được
        public async Task PreCacheNumberVoicesAsync(
            IProgress<int>? progress = null,
            CancellationToken cancellationToken = default)
        {
            var numbers = Enumerable.Range(0, 101).Select(n => n.ToString()).ToList();
            await PreCacheVoicesAsync(numbers, PREF_NUMBER_CACHE_READY, progress, cancellationToken);
        }

        // Pre-cache TOÀN BỘ giọng đọc của game: số, con vật, mọi câu hỏi/đáp án, lời khen
        // Để khi mất mạng app vẫn đọc được hết
        public async Task PreCacheAllGameVoicesAsync(
            IProgress<int>? progress = null,
            CancellationToken cancellationToken = default)
        {
            var texts = BuildAllGameVoiceTexts();
            await PreCacheVoicesAsync(texts, PREF_GAME_CACHE_READY, progress, cancellationToken);
        }

        // Liệt kê mọi chuỗi mà app có thể đọc:
        // - Số, con vật, câu hỏi/đáp án, đồng hồ → tận dụng nguồn dữ liệu trong MathEngine
        // - Chỉ thêm phần nằm ngoài MathEngine (lời khen/phản hồi ở GamePage)
        private static List<string> BuildAllGameVoiceTexts()
        {
            var texts = GameData.GetAllSpokenTexts();

            // Phần nằm ngoài MathEngine: câu phản hồi duy nhất khi đúng/sai/bỏ qua
            texts.AddRange([
                PRAISE_PHRASE,
                WRONG_PHRASE,
                SKIP_PHRASE
            ]);

            return texts.Distinct().ToList();
        }

        private static async Task PreCacheVoicesAsync(
            IEnumerable<string> texts,
            string prefKey,
            IProgress<int>? progress = null,
            CancellationToken cancellationToken = default)
        {
            bool CacheReady = false;
            await MainThread.InvokeOnMainThreadAsync(() => {
                CacheReady = Preferences.Get(prefKey, false);
            });
            if(CacheReady) { progress?.Report(100); return; }

            try
            {
                if (Connectivity.Current.NetworkAccess != NetworkAccess.Internet) return;
            }
            catch { return; }

            var list = texts.Where(x => !string.IsNullOrWhiteSpace(x)).Distinct().ToList();
            int completed = 0;
            using var semaphore = new SemaphoreSlim(2);

            var tasks = list.Select(async name =>
            {
                await semaphore.WaitAsync(cancellationToken);
                try
                {
                    var path = GetCachePath(name);
                    if (File.Exists(path)) return;

                    // Thử tất cả nguồn TTS miễn phí theo thứ tự ưu tiên:
                    // 1. Edge TTS → 2. Google TTS → 3. FPT AI → 4. Viettel AI
                    bool ok = await DownloadEdgeTts(name, path, cancellationToken);
                    if (!ok) ok = await DownloadGoogleTts(name, path, cancellationToken);
                    if (!ok) ok = await DownloadFptAiTts(name, path, cancellationToken);
                    if (!ok) await DownloadViettelTts(name, path, cancellationToken);
                }
                finally { semaphore.Release(); progress?.Report(Interlocked.Increment(ref completed) * 100 / list.Count); }
            });
            await Task.WhenAll(tasks);

            // Chỉ đánh dấu ready khi đủ file (thiếu file nào lần sau tải lại file đó)
            bool allExist = list.All(x => File.Exists(GetCachePath(x)));
            if (allExist)
            {
                await MainThread.InvokeOnMainThreadAsync(() => {
                    Preferences.Set(prefKey, true);
                });
            }
        }

        private static bool IsValidCachedMp3(string path)
        {
            // Kiểm tra file cache MP3 trước khi phát — bỏ file hỏng/truncated
            // (tiếng rè / méo), tải lại từ mạng thay vì chơi mãi file lỗi.
            try
            {
                if (!File.Exists(path)) return false;
                var fi = new FileInfo(path);
                if (fi.Length < 1024) return false;

                byte[] head = new byte[10];
                using (var fs = File.OpenRead(path))
                {
                    int r = fs.Read(head, 0, head.Length);
                    if (r < 4) return false;
                    bool id3 = head[0] == 'I' && head[1] == 'D' && head[2] == '3';
                    bool sync = head[0] == 0xFF && (head[1] & 0xE0) == 0xE0;
                    if (!id3 && !sync) return false;

                    if (id3 && r >= 10)
                    {
                        long size = ((head[6] & 0x7FL) << 21) | ((head[7] & 0x7FL) << 14) | ((head[8] & 0x7FL) << 7) | (head[9] & 0x7FL);
                        if (size + 10 >= fi.Length) return false; // ID3v2 khai báo size lớn hơn file -> truncated
                    }

                    // Quét toàn cụm đầu file: cần >= 4 khung MPEG hợp lệ (sync + bitrate + sample rate)
                    fs.Position = 0;
                    byte[] buf = new byte[Math.Min(fi.Length, 512 * 1024)];
                    int read = fs.Read(buf, 0, buf.Length);
                    int hits = 0;
                    for (int i = 0; i < read - 4; i++)
                    {
                        if (buf[i] != 0xFF) continue;
                        if ((buf[i + 1] & 0xE0) != 0xE0) continue;
                        int bitrateIndex = (buf[i + 2] & 0xF0) >> 4;
                        int sampleRateIndex = (buf[i + 2] & 0x0C) >> 2;
                        if (bitrateIndex == 0 || bitrateIndex == 15) continue;
                        if (sampleRateIndex == 3) continue;
                        hits++;
                        if (hits >= 4) return true;
                    }
                    return false;
                }
            }
            catch
            {
                return false;
            }
        }

        public async Task SpeakAsync(string text)
		{
			if (string.IsNullOrWhiteSpace(text)) return;

            // Dừng ngay lập tức câu đang đọc dở (quan trọng nhất)
            // Việc này sẽ khiến Task PlayFile cũ bị hủy -> giải phóng _speakLock
            Stop();

            _speakCts = new CancellationTokenSource();
			var token = _speakCts.Token;

			// Chờ tối đa 2s để lấy quyền đọc (tránh treo app)
			if (!await _speakLock.WaitAsync(2000, token)) return;

			try
			{
                // Chuẩn bị file (Tải nếu chưa có / nếu file cache bị hỏng)
                var cachePath = GetCachePath(text);

                bool fileExists = await Task.Run(() => IsValidCachedMp3(cachePath));
                if (!fileExists && File.Exists(cachePath))
                {
                    try { File.Delete(cachePath); } catch { /* bỏ file cache hỏng để tải lại */ }
                }

                bool hasInternet = false;
                try { hasInternet = Connectivity.Current.NetworkAccess == NetworkAccess.Internet; } catch { hasInternet = false; }
                bool usedEdgeTts = false;
                if (!fileExists && hasInternet)
                {
                    // Thử tất cả nguồn TTS miễn phí theo thứ tự ưu tiên:
                    // 1. Edge TTS (48kHz/192kbps, neural, miễn phí) → chất lượng cao nhất
                    // 2. Google TTS (24kHz/64kbps, miễn phí) → ổn định
                    // 3. FPT AI TTS (free tier, cần API key trong Preferences "fpt_ai_api_key")
                    // 4. Viettel AI TTS (free tier, cần API key trong Preferences "viettel_ai_api_key")
                    bool edgeSuccess = await GoogleTtsService.DownloadEdgeTts(text, cachePath, token);
                    if (edgeSuccess)
                    {
                        usedEdgeTts = true;
                    }
                    else
                    {
                        bool googleSuccess = await GoogleTtsService.DownloadGoogleTts(text, cachePath, token);
                        if (!googleSuccess)
                        {
                            bool fptSuccess = await GoogleTtsService.DownloadFptAiTts(text, cachePath, token);
                            if (!fptSuccess)
                            {
                                await GoogleTtsService.DownloadViettelTts(text, cachePath, token);
                            }
                        }
                    }
                }
                else if (fileExists)
                {
                    // File cache tồn tại — ước lượng nguồn TTS dựa vào kích thước file
                    // Edge TTS: 48kHz/192kbps (lớn), Google TTS: 24kHz/64kbps (nhỏ)
                    try
                    {
                        var fi = new FileInfo(cachePath);
                        usedEdgeTts = fi.Length > 8192;
                    }
                    catch { usedEdgeTts = false; }
                }

                // Phát ngay nếu file tồn tại và hợp lệ (MP3 thật, không truncated)
                if (await Task.Run(() => IsValidCachedMp3(cachePath)) && !token.IsCancellationRequested)
                {
                    // Volume theo nguồn TTS: Google TTS (chất lượng thấp) → 0.5, Edge TTS (chất lượng cao) → 0.6
                    float ttsVolume = usedEdgeTts ? 0.6f : 0.5f;
                    await PlayFile(cachePath, token, ttsVolume);
                }
            }
            catch (OperationCanceledException) { /* Bỏ qua nếu bị hủy */ }
            catch (Exception ex)
			{
				System.Diagnostics.Debug.WriteLine($"Lỗi TTS: {ex.Message}");
			}
			finally
			{
                if (_speakLock.CurrentCount == 0) _speakLock.Release();
            }
		}

        // --- EDGE TTS (WEBSOCKET - GIỌNG HOÀI MY) ---
        private static async Task<bool> DownloadEdgeTts(string text, string filePath, CancellationToken token)
		{
			using var client = new ClientWebSocket();
			try
			{
				// Các Header này giúp "lách" qua tường lửa của Microsoft
				client.Options.SetRequestHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0");
				client.Options.SetRequestHeader("Origin", "chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold"); // ID của Extension Read Aloud
				client.Options.SetRequestHeader("Pragma", "no-cache");
				client.Options.SetRequestHeader("Cache-Control", "no-cache");

				await client.ConnectAsync(new Uri(EDGE_URL), token);

                // MP3 48kHz/192kbps cho to/rõ, đỡ rè khi volume 90%
				string configMsg = MakeMsg("speech.config", "{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":{\"sentenceBoundaryEnabled\":\"false\",\"wordBoundaryEnabled\":\"false\"},\"outputFormat\":\"audio-48khz-192kbitrate-mono-mp3\"}}}}");
				await client.SendAsync(System.Text.Encoding.UTF8.GetBytes(configMsg), WebSocketMessageType.Text, true, token);

                // Gửi nội dung cần đọc (SSML)
                // Lưu ý: BuildNaturalSsmlText đã trả về các thẻ <prosody> riêng
                // nên KHÔNG bọc thêm prosody ở ngoài để tránh lồng/nhân đôi pitch-rate
                string ssml =
					$@"<speak version='1.0'
						xmlns='http://www.w3.org/2001/10/synthesis'
						xml:lang='vi-VN'>
						<voice name='{VOICE_EDGE}'>
							{BuildNaturalSsmlText(text)}
						</voice>
					</speak>";

                string textMsg = MakeMsg("ssml", ssml);
				await client.SendAsync(System.Text.Encoding.UTF8.GetBytes(textMsg), WebSocketMessageType.Text, true, token);

				// Nhận dữ liệu và ghi ra file - xử lý header tách gói
				// Ghi ra .part rồi rename atomically để tránh cache file dở dang (tiếng rè/méo)
				var tmpPath = filePath + ".part";
				using var fs = File.Create(tmpPath);
				var buffer = new byte[1024 * 16];
				bool hasAudio = false;

				while (client.State == WebSocketState.Open && !token.IsCancellationRequested)
				{
					var result = await client.ReceiveAsync(new ArraySegment<byte>(buffer), token);
					if (result.MessageType == WebSocketMessageType.Close) break;
					if (result.Count == 0) continue;

					string header = System.Text.Encoding.UTF8.GetString(buffer, 0, Math.Min(result.Count, 512));
					if (header.Contains("Path:audio"))
					{
						int headerEnd = LocateHeaderEnd(buffer, result.Count);
						if (headerEnd > 0 && headerEnd < result.Count)
						{
							await fs.WriteAsync(buffer.AsMemory(headerEnd, result.Count - headerEnd), token);
							hasAudio = true;
						}
						else if (headerEnd == -1)
						{
							// Header bị tách gói, bỏ gói này, gói sau sẽ chứa audio thuần
							continue;
						}
					}
					else if (header.Contains("Path:turn.end")) break;
					else if (header.Contains("Path:turn.start") || header.Contains("Path:response")) { /* metadata, bỏ qua */ }
					else
					{
						// Có thể là audio thuần không header (nếu header và audio gộp)
						if (result.Count > 100 && buffer[0] == 0xFF) // MP3 sync byte
						{
							await fs.WriteAsync(buffer.AsMemory(0, result.Count), token);
							hasAudio = true;
						}
					}
				}
                await fs.FlushAsync(token);
                await fs.DisposeAsync();
                // Kiểm tra sức khỏe file (byte thật + kích thước tối thiểu)
                try
                {
                    var info = new FileInfo(tmpPath);
                    if (!hasAudio || !info.Exists || info.Length < 1024)
                    {
                        try { if (File.Exists(tmpPath)) File.Delete(tmpPath); } catch { }
                        return false;
                    }
                    File.Move(tmpPath, filePath, overwrite: true);
                }
                catch { try { if (File.Exists(tmpPath)) File.Delete(tmpPath); } catch { } return false; }
				return true;
			}
			catch (Exception ex)
			{
				System.Diagnostics.Debug.WriteLine($"Edge Error: {ex.Message}");
				// Xóa file rác nếu tải lỗi để lần sau tải lại
				try { if (File.Exists(filePath)) File.Delete(filePath); } catch { }
				try { var leftoverPart = filePath + ".part"; if (File.Exists(leftoverPart)) File.Delete(leftoverPart); } catch { }
				return false;
			}
		}

		// --- GOOGLE TRANSLATE (HTTP - BACKUP) ---
		private static async Task<bool> DownloadGoogleTts(string text, string filePath, CancellationToken token)
		{
			try
			{
				var url = $"https://translate.google.com/translate_tts?ie=UTF-8&q={System.Net.WebUtility.UrlEncode(text)}&tl=vi&client=tw-ob";
				var response = await _httpClient.GetAsync(url, token);
				if (response.IsSuccessStatusCode)
				{
					var data = await response.Content.ReadAsByteArrayAsync(token);
					// [FIX] Chỉ chấp nhận file MP3 thật (header ID3 hoặc sync byte 0xFF).
					// Khi Google trả về trang CAPTCHA/HTML (vẫn 200 OK), phải từ chối để
					// fallback sang Edge TTS, tránh lưu nhầm nội dung rác vào cache làm sai âm thanh.
					bool isMp3 = data.Length > 128
						&& ((data[0] == 'I' && data[1] == 'D' && data[2] == '3')
							|| (data[0] == 0xFF && (data[1] & 0xE0) == 0xE0));
					if (!isMp3) return false;

					// Ghi ra .part rồi rename atomic — tránh cache file dở dang (tiếng rè/méo)
				var tmpPath = filePath + ".part";
				await File.WriteAllBytesAsync(tmpPath, data, token);
				try { File.Move(tmpPath, filePath, overwrite: true); } catch { try { if (File.Exists(tmpPath)) File.Delete(tmpPath); } catch { } return false; }
					return true;
				}
			}
			catch { try { var leftoverPart = filePath + ".part"; if (File.Exists(leftoverPart)) File.Delete(leftoverPart); } catch { } }
			return false;
		}

		// --- FPT AI TTS (HTTP - FREE TIER, CẦN API KEY) ---
		private static async Task<bool> DownloadFptAiTts(string text, string filePath, CancellationToken token)
		{
			try
			{
				string apiKey = "";
				await MainThread.InvokeOnMainThreadAsync(() => {
					apiKey = Preferences.Get("fpt_ai_api_key", "");
				});
				if (string.IsNullOrWhiteSpace(apiKey)) return false;

				var request = new HttpRequestMessage(HttpMethod.Post, "https://api.fpt.ai/hmi/tts/v5");
				request.Headers.Add("api_key", apiKey);
				request.Headers.Add("voice", "banmai"); // Giọng nữ miền Bắc - cô giáo
				request.Headers.Add("speed", "0");
				request.Headers.Add("format", "mp3");
				request.Content = new StringContent(text, System.Text.Encoding.UTF8, "text/plain");

				var response = await _httpClient.SendAsync(request, token);
				if (!response.IsSuccessStatusCode) return false;

				var json = await response.Content.ReadAsStringAsync(token);
				int asyncIdx = json.IndexOf("\"async\"", StringComparison.Ordinal);
				if (asyncIdx < 0) return false;
				int colonIdx = json.IndexOf(':', asyncIdx);
				if (colonIdx < 0) return false;
				int quoteStart = json.IndexOf('"', colonIdx + 1);
				if (quoteStart < 0) return false;
				int quoteEnd = json.IndexOf('"', quoteStart + 1);
				if (quoteEnd < 0) return false;
				string audioUrl = json.Substring(quoteStart + 1, quoteEnd - quoteStart - 1);
				if (string.IsNullOrWhiteSpace(audioUrl)) return false;

				await Task.Delay(2000, token);
				var audioResponse = await _httpClient.GetAsync(audioUrl, token);
				if (!audioResponse.IsSuccessStatusCode) return false;

				var data = await audioResponse.Content.ReadAsByteArrayAsync(token);
				if (data.Length < 1024) return false;

				bool isMp3 = data.Length > 128
					&& ((data[0] == 'I' && data[1] == 'D' && data[2] == '3')
						|| (data[0] == 0xFF && (data[1] & 0xE0) == 0xE0));
				if (!isMp3) return false;

				var tmpPath = filePath + ".part";
				await File.WriteAllBytesAsync(tmpPath, data, token);
				try { File.Move(tmpPath, filePath, overwrite: true); } catch { try { if (File.Exists(tmpPath)) File.Delete(tmpPath); } catch { } return false; }
				return true;
			}
			catch { try { var leftoverPart = filePath + ".part"; if (File.Exists(leftoverPart)) File.Delete(leftoverPart); } catch { } }
			return false;
		}

		// --- VIETTEL AI TTS (HTTP - FREE TIER, CẦN API KEY) ---
		private static async Task<bool> DownloadViettelTts(string text, string filePath, CancellationToken token)
		{
			try
			{
				string apiKey = "";
				await MainThread.InvokeOnMainThreadAsync(() => {
					apiKey = Preferences.Get("viettel_ai_api_key", "");
				});
				if (string.IsNullOrWhiteSpace(apiKey)) return false;

				var request = new HttpRequestMessage(HttpMethod.Post, "https://viettelgroup.ai/voice/api/tts/v1/rest/syn");
				request.Headers.Add("token", apiKey);
				var body = $"{{\"text\":\"{System.Net.WebUtility.UrlEncode(text)}\",\"voice\":\"hn-quynhanh\",\"speed\":1.0,\"tts_return_option\":3}}";
				request.Content = new StringContent(body, System.Text.Encoding.UTF8, "application/json");

				var response = await _httpClient.SendAsync(request, token);
				if (!response.IsSuccessStatusCode) return false;

				var data = await response.Content.ReadAsByteArrayAsync(token);
				if (data.Length < 1024) return false;

				bool isMp3 = data.Length > 128
					&& ((data[0] == 'I' && data[1] == 'D' && data[2] == '3')
						|| (data[0] == 0xFF && (data[1] & 0xE0) == 0xE0));
				if (!isMp3) return false;

				var tmpPath = filePath + ".part";
				await File.WriteAllBytesAsync(tmpPath, data, token);
				try { File.Move(tmpPath, filePath, overwrite: true); } catch { try { if (File.Exists(tmpPath)) File.Delete(tmpPath); } catch { } return false; }
				return true;
			}
			catch { try { var leftoverPart = filePath + ".part"; if (File.Exists(leftoverPart)) File.Delete(leftoverPart); } catch { } }
			return false;
		}

        // --- CÁC HÀM BỔ TRỢ ---
        private static string BuildNaturalSsmlText(string text)
        {
            if (string.IsNullOrWhiteSpace(text))
                return string.Empty;

            text = text.Trim();

            // ============================
            // CON SỐ (0-100) - đọc tự nhiên theo điệu tiếng Việt
            // ============================
            if (text.All(char.IsDigit))
            {
                return BuildNumberSsml(text);
            }

            // ============================
            // ĐỘNG VẬT (từ GameData)
            // ============================
            var animalName = NormalizeAnimalName(text);
            if (IsLikelyAnimalName(animalName))
            {
                // Giọng nhẹ nhàng, tự nhiên — để neural voice tự xử lý intonation
                return $"{animalName}<break time='200ms'/>";
            }

            // ============================
            // PHÉP TOÁN
            // ============================
            if (text.Contains('+') || text.Contains('-'))
            {
                return $"{text}<break time='300ms'/>";
            }

            // ============================
            // CÂU SẮP XẾP SỐ
            // ============================
            if (text.StartsWith("Sắp xếp các số từ", StringComparison.Ordinal))
            {
                int tu = text.IndexOf(" từ ", StringComparison.Ordinal);
                int den = text.IndexOf(" đến ", StringComparison.Ordinal);
                if (tu > 0 && den > tu)
                {
                    string from = text.Substring(tu + 4, den - tu - 4).Trim();
                    string to = text.Substring(den + 5).Trim();
                    return $"Sắp xếp các số từ {from} đến {to}<break time='300ms'/>";
                }
            }

            // ============================
            // CÂU HỎI
            // ============================
            if (text.EndsWith('?'))
            {
                return text; // Neural voice tự xử lý rising intonation cho câu hỏi
            }

            // ============================
            // CÂU KHEN (trả lời đúng)
            // ============================
            if (text.Contains("đúng") || text.Contains("giỏi") || text.Contains("tuyệt"))
            {
                return $"{text}<break time='200ms'/>";
            }

            // ============================
            // MẶC ĐỊNH
            // ============================
            return text;
        }

        // Đọc con số theo cách người Việt nói: "một trăm hai mươi ba"
        private static string BuildNumberSsml(string num)
        {
            if (!int.TryParse(num, out int n))
                return num;

            if (n == 0) return "không";

            var sb = new System.Text.StringBuilder();
            int hundred = n / 100;
            int remainder = n % 100;

            if (hundred > 0)
            {
                sb.Append(hundred == 1 ? "một trăm" : $"{GetDigitWord(hundred)} trăm");
                if (remainder > 0) sb.Append(", ");
            }

            if (remainder > 0)
            {
                if (remainder < 20)
                {
                    sb.Append(remainder switch
                    {
                        10 => "mười",
                        11 => "mười một",
                        12 => "mười hai",
                        13 => "mười ba",
                        14 => "mười bốn",
                        15 => "mười lăm",
                        _ => remainder.ToString()
                    });
                }
                else
                {
                    int tens = remainder / 10;
                    int ones = remainder % 10;

                    sb.Append(tens switch
                    {
                        2 => "hai mươi",
                        3 => "ba mươi",
                        4 => "bốn mươi",
                        5 => "năm mươi",
                        6 => "sáu mươi",
                        7 => "bảy mươi",
                        8 => "tám mươi",
                        9 => "chín mươi",
                        _ => ""
                    });
                    if (ones > 0)
                    {
                        sb.Append(" ");
                        sb.Append(ones switch
                        {
                            1 => "mốt",
                            5 => "lăm",
                            _ => GetDigitWord(ones)
                        });
                    }
                }
            }

            return sb.ToString();
        }

        private static string GetDigitWord(int d) => d switch
        {
            1 => "một", 2 => "hai", 3 => "ba", 4 => "bốn", 5 => "năm",
            6 => "sáu", 7 => "bảy", 8 => "tám", 9 => "chín",
            _ => ""
        };


        private static string NormalizeAnimalName(string text)
        {
            if (string.IsNullOrWhiteSpace(text))
                return string.Empty;

            text = text.Trim();

            if (text.StartsWith("Con ", StringComparison.OrdinalIgnoreCase))
            {
                return text[4..].Trim();
            }

            return text;
        }

        private static bool IsLikelyAnimalName(string text)
        {
            if (string.IsNullOrWhiteSpace(text))
                return false;

            // Tên động vật thường:
            // - Viết hoa chữ cái đầu
            // - Không quá dài
            return char.IsUpper(text[0]) && text.Split(' ').Length <= 4;
        }

        private static string MakeMsg(string path, string content)
        {
            return $"X-Timestamp:{DateTime.Now:O}\r\nContent-Type:application/json; charset=utf-8\r\nPath:{path}\r\n\r\n{content}";
        }

        private static int LocateHeaderEnd(byte[] data, int length)
		{
			for (int i = 0; i < length - 3; i++)
				if (data[i] == 13 && data[i + 1] == 10 && data[i + 2] == 13 && data[i + 3] == 10) return i + 4;
			return -1;
		}


        private async Task PlayFile(string path, CancellationToken token, float volume = 0.6f)
        {
            // Nếu máy cũ không có AudioManager thì bỏ qua phát tiếng (không crash)
            if (_audioManager == null)
            {
                Debug.WriteLine("[TTS] AudioManager null -> skip PlayFile");
                return;
            }
            _playbackTcs = new TaskCompletionSource<bool>();

            // Đăng ký hủy: Nếu token bị cancel (do gọi Stop), ta set luôn kết quả để thoát hàm này
            using var reg = token.Register(() => _playbackTcs.TrySetCanceled());

            // Mở file trên luồng nền (Background Thread) để không chặn UI
            Stream? fileStream = null;
            try
            {
                fileStream = await Task.Run(() => File.OpenRead(path), token);
            }
            catch
            {
                _playbackTcs.TrySetResult(false);
                return;
            }

            await MainThread.InvokeOnMainThreadAsync(() =>
            {
                try
                {
                    // Kiểm tra lại lần cuối xem lệnh hủy đã đến chưa
                    if (token.IsCancellationRequested)
                    {
                        fileStream.Dispose();
                        _playbackTcs.TrySetCanceled();
                        return;
                    }

                    CleanupPlayer();

                    // CLEANUP STREAM CŨ
                    if (_stream != null)
                    {
                        try
                        {
                            _stream.Dispose();
                        }
                        catch { }
                        _stream = null;
                    }

                    _stream = fileStream;

                    // CreatePlayer bắt buộc chạy trên MainThread
                    try { _player = _audioManager.CreatePlayer(_stream); }
                    catch (Exception ex) { Debug.WriteLine($"[TTS] CreatePlayer failed: {ex.Message}"); fileStream.Dispose(); _playbackTcs.TrySetResult(false); return; }
                    if (_player == null) { fileStream.Dispose(); _playbackTcs.TrySetResult(false); return; }
                    try { _player.Volume = volume; } catch { }

                    // LƯU HANDLER VÀ SUBSCRIBE
                    _currentPlaybackHandler = OnPlaybackEnded;
                    _player.PlaybackEnded += _currentPlaybackHandler;

                    _player.Play();
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"PlayFile Error: {ex.Message}");
                    _playbackTcs.TrySetResult(false);
                }
            });

            // Chờ cho đến khi phát xong HOẶC bị hủy
            await _playbackTcs.Task;
        }

        private void CleanupPlayer()
        {
            if (_player == null) return;

            try
            {
                // 1. Unsubscribe event TRƯỚC
                if (_currentPlaybackHandler != null)
                {
                    _player.PlaybackEnded -= _currentPlaybackHandler;
                    _currentPlaybackHandler = null;
                }

                // 2. Stop nếu đang play
                if (_player.IsPlaying)
                {
                    _player.Stop();
                }

                // 3. Dispose
                _player.Dispose();
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"CleanupPlayer Error: {ex.Message}");
            }
            finally
            {
                _player = null; // Luôn set null
            }
        }

        // ⭐ Phiên bản cache: đổi khi thay đổi giọng/SSML để ép tải lại giọng mới
        // v8: thêm FPT AI TTS + Viettel AI TTS vào fallback chain
        private const string CACHE_VERSION = "v8-multi-source-tts";

        private static string GetCachePath(string text)
		{
			// Tạo tên file từ nội dung text + version để cache lại - fallback nếu CacheDirectory null (máy cũ chưa init)
			var hash = Convert.ToHexString(SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(CACHE_VERSION + "|" + text)));
			var cacheDir = FileSystem.CacheDirectory;
			if (string.IsNullOrEmpty(cacheDir))
			{
				try { cacheDir = Path.GetTempPath(); } catch { cacheDir = "/tmp"; }
				try { Directory.CreateDirectory(cacheDir); } catch { }
			}
			return Path.Combine(cacheDir, $"{hash}.mp3");
		}

        public void Stop()
        {
            try
            {
                // Hủy token để ngắt việc tải / chờ
                _speakCts?.Cancel();
                _speakCts?.Dispose();
                _speakCts = null;

                // Ngắt Task đang chờ phát nhạc
                _playbackTcs?.TrySetCanceled();

                // DÙNG HÀM CLEANUP CHUNG
                CleanupPlayer();

                if (_stream != null)
                {
                    try
                    {
                        _stream?.Dispose();
                    }catch { /* Ignore */ }
                    _stream = null;
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Stop Error: {ex.Message}");
            }
        }

        private void OnPlaybackEnded(object? sender, EventArgs e)
        {
            if (_player != null && _currentPlaybackHandler != null)
            {
                _player.PlaybackEnded -= _currentPlaybackHandler;
                _currentPlaybackHandler = null;
            }

            _playbackTcs?.TrySetResult(true);
        }

        public void Dispose()
		{
			Stop();
			_speakLock.Dispose();

            // CLEANUP LẦN CUỐI
            CleanupPlayer();

            if (_stream != null)
            {
                try { _stream.Dispose(); } catch { }
                _stream = null;
            }
        }
    }
}
