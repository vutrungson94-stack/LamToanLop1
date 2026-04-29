using Plugin.Maui.Audio;
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
        private const string PREF_ANIMAL_CACHE_READY = "animal_voice_cache_ready";
       
        private EventHandler? _currentPlaybackHandler;

        public GoogleTtsService(IAudioManager audioManager)
        {
            _audioManager = audioManager;
            Task.Delay(3000).ContinueWith(_ => CleanupOldCache());
        }

        // Hàm dọn dẹp file rác quá hạn (mặc định 3 ngày)
        private static void CleanupOldCache(int maxAgeDays = 3)
        {
            try
            {
                var cacheDir = FileSystem.CacheDirectory;
                if (!Directory.Exists(cacheDir)) return;

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

        public async Task PreCacheAnimalVoicesAsync(
            IEnumerable<string> animalNames,
            IProgress<int>? progress = null,
            CancellationToken cancellationToken = default)
        {
            bool CacheReady = false;
            await MainThread.InvokeOnMainThreadAsync(() => {
                CacheReady = Preferences.Get(PREF_ANIMAL_CACHE_READY, false);
            });
            if(CacheReady) { progress?.Report(100); return; }

            if (Connectivity.Current.NetworkAccess != NetworkAccess.Internet) return;

            var list = animalNames.Where(x => !string.IsNullOrWhiteSpace(x)).Distinct().ToList();
            int completed = 0;
            using var semaphore = new SemaphoreSlim(2);

            var tasks = list.Select(async name =>
            {
                await semaphore.WaitAsync(cancellationToken);
                try { await GoogleTtsService.PrepareAudioAsync(name, cancellationToken); }
                finally { semaphore.Release(); progress?.Report(Interlocked.Increment(ref completed) * 100 / list.Count); }
            });
            await Task.WhenAll(tasks);
            await MainThread.InvokeOnMainThreadAsync(() => {
                Preferences.Set(PREF_ANIMAL_CACHE_READY, true);
            });
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
                // Chuẩn bị file (Tải nếu chưa có)
                var cachePath = GetCachePath(text);

                bool fileExists = await Task.Run(() => File.Exists(cachePath));

                if (!fileExists && Connectivity.Current.NetworkAccess == NetworkAccess.Internet)
                {
                    // Tải file (có hỗ trợ hủy ngang qua token)
                    bool edgeSuccess = await GoogleTtsService.DownloadEdgeTts(text, cachePath, token);
                    if (!edgeSuccess)
                    {
                        await GoogleTtsService.DownloadGoogleTts(text, cachePath, token);
                    }
                }

                // Phát ngay nếu file tồn tại và chưa bị hủy
                if (await Task.Run(() => File.Exists(cachePath)) && !token.IsCancellationRequested)
                {
                    await PlayFile(cachePath, token);
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

				// Gửi cấu hình (MP3 chất lượng cao)
				string configMsg = MakeMsg("speech.config", "{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":{\"sentenceBoundaryEnabled\":\"false\",\"wordBoundaryEnabled\":\"false\"},\"outputFormat\":\"audio-24khz-48kbitrate-mono-mp3\"}}}}");
				await client.SendAsync(System.Text.Encoding.UTF8.GetBytes(configMsg), WebSocketMessageType.Text, true, token);

                // Gửi nội dung cần đọc (SSML)
                string ssml =
					$@"<speak version='1.0'
						xmlns='http://www.w3.org/2001/10/synthesis'
						xml:lang='vi-VN'>
						<voice name='{VOICE_EDGE}'>
							<prosody rate='-5%' pitch='+8%'>
								{BuildNaturalSsmlText(text)}
							</prosody>
						</voice>
					</speak>";

                string textMsg = MakeMsg("ssml", ssml);
				await client.SendAsync(System.Text.Encoding.UTF8.GetBytes(textMsg), WebSocketMessageType.Text, true, token);

				// Nhận dữ liệu và ghi ra file
				using var fs = File.Create(filePath);
				var buffer = new byte[1024 * 16];

				while (client.State == WebSocketState.Open && !token.IsCancellationRequested)
				{
					var result = await client.ReceiveAsync(new ArraySegment<byte>(buffer), token);
					if (result.MessageType == WebSocketMessageType.Close) break;

					// Parse binary header của Edge
					string header = System.Text.Encoding.UTF8.GetString(buffer, 0, result.Count);
					if (header.Contains("Path:audio"))
					{
						int headerEnd = LocateHeaderEnd(buffer, result.Count);
						if (headerEnd > 0 && headerEnd < result.Count)
						{
							await fs.WriteAsync(buffer.AsMemory(headerEnd, result.Count - headerEnd), token);
						}
					}
					else if (header.Contains("Path:turn.end")) break; // Kết thúc
				}
				return true;
			}
			catch (Exception ex)
			{
				System.Diagnostics.Debug.WriteLine($"Edge Error: {ex.Message}");
				// Xóa file rác nếu tải lỗi để lần sau tải lại
				try { if (File.Exists(filePath)) File.Delete(filePath); } catch { }
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
					await File.WriteAllBytesAsync(filePath, data, token);
					return true;
				}
			}
			catch { }
			return false;
		}

        private static async Task PrepareAudioAsync(string text, CancellationToken token = default)
        {
            var cachePath = GetCachePath(text);

            if (!File.Exists(cachePath) && Connectivity.Current.NetworkAccess.HasFlag(NetworkAccess.Internet))
            {
                await GoogleTtsService.DownloadEdgeTts(text, cachePath, token);
            }
        }

        // --- CÁC HÀM BỔ TRỢ ---
        private static string BuildNaturalSsmlText(string text)
        {
            if (string.IsNullOrWhiteSpace(text))
                return string.Empty;

            text = text.Trim();

            // ============================
            // ĐỘNG VẬT (từ GameData)
            // ============================
            var animalName = NormalizeAnimalName(text);

            if (IsLikelyAnimalName(animalName))
            {
                var (basePitch, baseRate) = GetAnimalVoiceProfile(animalName);

                var pitch = Randomize(basePitch);
                var rate = Randomize(baseRate);

                return
                    $@"<prosody pitch='{pitch}%' rate='{rate}%'>
						<emphasis level='moderate'>{animalName}</emphasis>!
					</prosody>
					<break time='300ms'/>";
            }

            // ============================
            // PHÉP TOÁN
            // ============================
            if (text.Contains('+') || text.Contains('-'))
            {
                return
					$@"<prosody rate='-15%' pitch='+6%'>
						{text}
					</prosody>
					<break time='300ms'/>";
            }

            // ============================
            // CÂU HỎI
            // ============================
            if (text.EndsWith('?'))
            {
                return
					$@"<prosody rate='-10%' pitch='+8%'>
						{text}
					</prosody>";
            }

            // ============================
            // CÂU KHEN (trả lời đúng)
            // ============================
            if (text.Contains("đúng") || text.Contains("giỏi") || text.Contains("tuyệt"))
            {
                return
					$@"<prosody pitch='+16%' rate='+5%'>
						{text}
					</prosody>
					<break time='200ms'/>";
            }

            // ============================
            // MẶC ĐỊNH
            // ============================
            return
				$@"<prosody rate='-5%' pitch='+6%'>
					{text}
				</prosody>";
        }


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

        private static (int pitch, int rate) GetAnimalVoiceProfile(string animalName)
        {
            animalName = animalName.ToLowerInvariant();

            // Chim, cá nhỏ → cao, nhanh
            if (animalName.Contains("chim") || animalName.Contains("cá "))
                return (12, -3);

            // Côn trùng → cao hơn nữa
            if (animalName.Contains("bướm") || animalName.Contains("ong"))
                return (14, 0);

            // Thú to → trầm, chậm
            if (animalName.Contains("voi") || animalName.Contains("hổ") || animalName.Contains("sư tử"))
                return (-6, -10);

            // Mặc định
            return (8, -5);
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

        public Task SpeakWithMoodAsync(string text, VoiceMood mood)
        {
            if (string.IsNullOrWhiteSpace(text))
                return Task.CompletedTask;

            string decoratedText = mood switch
            {
                VoiceMood.Happy => $"Giỏi quá! {text}",
                VoiceMood.Sad => text,
                _ => text
            };

            return SpeakAsync(decoratedText);
        }


        private async Task PlayFile(string path, CancellationToken token)
        {
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

                    // CreatePlayer bắt buộc chạy trên MainThread (tuỳ thư viện, nhưng an toàn nhất là để đây)
                    _player = _audioManager.CreatePlayer(_stream);

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

        private static string GetCachePath(string text)
		{
			// Tạo tên file từ nội dung text để cache lại
			var hash = Convert.ToHexString(SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(text)));
			return Path.Combine(FileSystem.CacheDirectory, $"{hash}.mp3");
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

    public enum VoiceMood
    {
        Neutral,
        Happy,
        Sad
    }
}