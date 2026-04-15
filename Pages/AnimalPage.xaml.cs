using LamToanLop1.Models;
using LamToanLop1.Services;

namespace LamToanLop1.Pages;

public partial class AnimalPage : ContentPage
{
	private readonly ITtsService _tts;

	// Lưu danh sách các con vật đã xem (Lưu Key của con vật)
	private readonly List<string> _history = [];
	private int _historyIndex = -1;

    // Biến khóa để ngăn bấm liên tiếp gây lag máy
    private bool _isNavigating = false;

    // Biến cờ kiểm soát trạng thái trang (để chặn tác vụ khi ẩn)
    private bool _isPageActive = false;

    public AnimalPage(ITtsService tts)
	{
		InitializeComponent();
		this._tts = tts;
	}

    //Hàm hủy animation
    private static void AbortSpecificAnimations(VisualElement view)
    {
        if (view == null) return;
        view.CancelAnimations();
        view.AbortAnimation("ScaleTo");
        view.AbortAnimation("FadeTo");
        view.AbortAnimation("TranslateTo");
        view.AbortAnimation("RotateTo");
    }

    protected override async void OnAppearing()
	{
		base.OnAppearing();

        // 1. Đánh dấu trang đang hoạt động
        _isPageActive = true;

        // 2. [NỐI CẦU CHÌ] Đăng ký lắng nghe sự kiện "App bị ẩn" từ App.xaml.cs
        App.AppHidden += OnAppHiddenHandler;

        App.AppResumed += OnAppResumedHandler;

        if (_history.Count == 0)
		{
			await LoadNextAnimal();
		}
    }

    protected override void OnDisappearing()
    {
        base.OnDisappearing();

        // 1. Đánh dấu trang đã ẩn
        _isPageActive = false;

        // 2. [NGẮT CẦU CHÌ] Hủy đăng ký để tránh lỗi
        App.AppHidden -= OnAppHiddenHandler;

        App.AppResumed -= OnAppResumedHandler;

        _tts.Stop();

        // Ngắt kết nối ảnh để giải phóng RAM
        AnimalImage?.Source = null;
    }

    private void OnAppResumedHandler()
    {
        _isPageActive = true;

        // Nếu muốn đọc lại tên con vật khi mở lại app thì thêm dòng này:
        if (_historyIndex >= 0 && _historyIndex < _history.Count) _ = ShowCurrentAnimal();
    }

    private void OnAppHiddenHandler()
    {
        _isNavigating = false;
		_tts.Stop();
    }

    private async Task LoadNextAnimal()
	{
        // Logic điều hướng (Next/Back)
        if (_historyIndex < _history.Count - 1)
		{
			_historyIndex++;
		}
		else
		{
			string newKey = PickRandomAnimalKey();
			_history.Add(newKey);
			_historyIndex++;
		}

		await ShowCurrentAnimal();
	}

	private async void OnNext(object? sender, EventArgs? e)
	{
		if (_isNavigating) return; // Nếu đang điều hướng thì bỏ qua
		_isNavigating = true;
		try
		{
			if (sender is Button btn)
			{
				AbortSpecificAnimations(btn);
				// Hiệu ứng bấm nút
				await btn.ScaleTo(0.9, 50);
				await btn.ScaleTo(1.0, 50);
            }

            _tts.Stop();
			await LoadNextAnimal();
		}
		finally
		{
            _isNavigating = false;
        }
	}

	private async void OnBack(object sender, EventArgs e)
	{
		if (_isNavigating) return; // Nếu đang điều hướng thì bỏ qua
		_isNavigating = true;

		try
		{
			if (sender is Button btn)
			{
				AbortSpecificAnimations(btn);
				await btn.ScaleTo(0.9, 50);
				await btn.ScaleTo(1.0, 50);
			}

			if (_historyIndex > 0)
			{
				_tts.Stop();
				_historyIndex--;
				await ShowCurrentAnimal();
			}
		}
		finally
		{
			_isNavigating = false;
		}
	}

    // Hàm xử lý khi bấm nút Loa
    private async void OnReplaySound(object sender, EventArgs e)
    {
        if (_isNavigating) return;
        _isNavigating = true;

        try
        {
            if (sender is ImageButton btn)
            {
                AbortSpecificAnimations(btn);
                // Hiệu ứng nhún nhảy nút loa
                await btn.ScaleTo(0.8, 100);
                await btn.ScaleTo(1.0, 100);
            }

            _tts.Stop();

            if (_isPageActive && _historyIndex >= 0 && _historyIndex < _history.Count)
            {
                string key = _history[_historyIndex];
                var animalPair = GameData.AnimalList.FirstOrDefault(x => x.Key == key);

                if (!string.IsNullOrEmpty(animalPair.Value))
                {
                    await _tts.SpeakAsync(animalPair.Value);
                }
            }
        }
        finally
        {
            _isNavigating = false;
        }
    }

    private string PickRandomAnimalKey()
	{
		string currentKey = _historyIndex >= 0 ? _history[_historyIndex] : "";
		string nextKey;

		if (GameData.AnimalList.Count <= 1) return GameData.AnimalList[0].Key;

		do
		{
			int idx = System.Random.Shared.Next(GameData.AnimalList.Count);
			nextKey = GameData.AnimalList[idx].Key;
		}
		while (nextKey == currentKey);

		return nextKey;
	}

	private async Task ShowCurrentAnimal()
	{
        // Nếu trang đã ẩn thì thôi, không làm gì cả
        if (!_isPageActive) return;

        _tts.Stop();

        if (_historyIndex < 0 || _historyIndex >= _history.Count) return;
			
		string key = _history[_historyIndex];
		var animal = GameData.AnimalList.FirstOrDefault(x => x.Key == key);
		string name = animal.Value ?? "";

		// UI
		AnimalImage.Source = null; // Reset ảnh trước để tránh nhầm lẫn khi load chậm
        AnimalImage.Source = $"{key}.webp";
		AnimalName.Text = name.ToUpper();

        // Ẩn/Hiện nút Back
        BtnBack.IsEnabled = _historyIndex > 0;
		BtnBack.Opacity = _historyIndex > 0 ? 1 : 0.5;

		//Trước khi chạy animation mới
		AbortSpecificAnimations(AnimalImage);

        // Animation
        AnimalImage.Scale = 0.5;
		AnimalImage.Opacity = 0;

		// --- TỐI ƯU HÓA TỐC ĐỘ ---
		// 1. Gọi TTS chạy ngay lập tức, không chờ UI vẽ xong
		// Vì bên service ta đã có Stop() ở đầu, nên nó sẽ ngắt ngay câu trước và đọc câu này
		if (_isPageActive)
		{
			var ttsTask = _tts.SpeakAsync(name);


			await Task.WhenAll(
				AnimalImage.FadeTo(1, 400),
				AnimalImage.ScaleTo(1, 600, Easing.SpringOut)
			);

			// Đợi TTS xong (nếu cần, thực ra không cần await cũng được để UI mượt hơn)
			await ttsTask;
		}
    }

	private async void OnAnimalImageTapped(object sender, EventArgs e)
	{
		if (_isNavigating) return; // Nếu đang điều hướng thì bỏ qua
		_isNavigating = true;

		try
		{
			_tts.Stop();

			AbortSpecificAnimations(AnimalImage);
			// 1. Hiệu ứng nảy hình (Làm to lên rồi nhỏ lại để bé biết đã bấm trúng)
			await AnimalImage.ScaleTo(1.2, 150, Easing.SpringOut);
			await AnimalImage.ScaleTo(1.0, 150, Easing.SpringOut);

			// 2. Lấy tên con vật hiện tại và đọc lại
			if (_isPageActive && _historyIndex >= 0 && _historyIndex < _history.Count)
			{
				string key = _history[_historyIndex];
				// Tìm tên tiếng Việt (Value) dựa trên Key
				var animalPair = GameData.AnimalList.FirstOrDefault(x => x.Key == key);

				if (!string.IsNullOrEmpty(animalPair.Value))
				{
					// Gọi TTS đọc tên
					await _tts.SpeakAsync(animalPair.Value);
				}
			}
		}
		finally
		{
			_isNavigating = false; 
		}
    }
}