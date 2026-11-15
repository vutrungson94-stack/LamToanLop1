using LamToanLop1.Helpers;
using LamToanLop1.Models;
using LamToanLop1.Services;
using System.Diagnostics;

namespace LamToanLop1.Pages;

public partial class AnimalPage : ContentPage
{
    private readonly ITtsService _tts;
    
    // Lưu danh sách lịch sử để xem lại
    private readonly List<string> _history = [];
    private int _historyIndex = -1;
    
    // Khóa điều hướng
    private bool _isNavigating = false;
    private bool _isPageActive = false;

    public AnimalPage(ITtsService tts)
    {
        InitializeComponent();
        _tts = tts;
        this.SizeChanged += (_, __) => ApplyResponsive();
    }

    private void ApplyResponsive()
    {
        if (Width <= 0) return;
        try
        {
            // Border ảnh 300 -> scale
            var border = this.FindByName<Border>("AnimalBorder");
            if (border != null) border.HeightRequest = ResponsiveHelper.H(300);
            // Nút Home 110x44
            var btnHome = this.FindByName<Button>("BtnHome");
            if (btnHome != null) { btnHome.WidthRequest = ResponsiveHelper.W(110); btnHome.HeightRequest = ResponsiveHelper.H(44); btnHome.FontSize = ResponsiveHelper.Font(14); }
            // Loa 48x48
            var btnLoa = this.FindByName<ImageButton>("BtnLoa");
            if (btnLoa != null) { btnLoa.WidthRequest = ResponsiveHelper.W(48); btnLoa.HeightRequest = ResponsiveHelper.H(48); }
            // Tên 32
            var lbl = this.FindByName<Label>("AnimalName");
            if (lbl != null) lbl.FontSize = ResponsiveHelper.Font(32);
            // Nút Back/Next 55 height
            var bBack = this.FindByName<Button>("BtnBack");
            var bNext = this.FindByName<Button>("BtnNext");
            if (bBack != null) { bBack.HeightRequest = ResponsiveHelper.H(55); bBack.FontSize = ResponsiveHelper.Font(16); }
            if (bNext != null) { bNext.HeightRequest = ResponsiveHelper.H(55); bNext.FontSize = ResponsiveHelper.Font(16); }
        }
        catch { }
    }

    protected override void OnSizeAllocated(double width, double height)
    {
        base.OnSizeAllocated(width, height);
        if (width > 0) ApplyResponsive();
    }

    private static void AbortSpecificAnimations(VisualElement view)
    {
        if (view == null) return;
        view.CancelAnimations();
        view.AbortAnimation("ScaleTo");
    }

    protected override async void OnAppearing()
    {
        base.OnAppearing();
        _isPageActive = true;
        
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
        _isPageActive = false;
        
        App.AppHidden -= OnAppHiddenHandler;
        App.AppResumed -= OnAppResumedHandler;

        _tts.Stop();
        if (AnimalImage?.Source != null) AnimalImage.Source = null;
    }

    private void OnAppResumedHandler()
    {
        _isPageActive = true;
        if (_historyIndex >= 0 && _historyIndex < _history.Count) 
            _ = ShowCurrentAnimal();
    }

    private void OnAppHiddenHandler()
    {
        _isNavigating = false;
        _tts.Stop();
    }

    private async Task LoadNextAnimal()
    {
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
        if (_isNavigating) return;
        _isNavigating = true;
        try
        {
            if (sender is Button btn)
            {
                AbortSpecificAnimations(btn);
                await btn.ScaleToAsync(0.9, 50);
                await btn.ScaleToAsync(1.0, 50);
            }
            _tts.Stop();
            await LoadNextAnimal();
        }
        finally { _isNavigating = false; }
    }

    private async void OnBack(object sender, EventArgs e)
    {
        if (_isNavigating) return;
        _isNavigating = true;
        try
        {
            if (sender is Button btn)
            {
                AbortSpecificAnimations(btn);
                await btn.ScaleToAsync(0.9, 50);
                await btn.ScaleToAsync(1.0, 50);
            }
            if (_historyIndex > 0)
            {
                _tts.Stop();
                _historyIndex--;
                await ShowCurrentAnimal();
            }
        }
        finally { _isNavigating = false; }
    }

    // 🔥 THÊM HÀM NÀY ĐỂ NÚT HOME HOẠT ĐỘNG
    private async void OnHomeClicked(object sender, EventArgs e)
    {
        if (_isNavigating) return;
        _isNavigating = true;
        try
        {
            if (sender is ImageButton btn)
            {
                AbortSpecificAnimations(btn);
                await btn.ScaleToAsync(0.8, 100);
                await btn.ScaleToAsync(1.0, 100);
            }
            
            _tts.Stop();
            
            // Quay về MenuPage
            await Shell.Current.GoToAsync("//MenuPage");
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Home Click Error: {ex.Message}");
        }
        finally { _isNavigating = false; }
    }

    private async void OnReplaySound(object sender, EventArgs e)
    {
        if (_isNavigating) return;
        _isNavigating = true;
        try
        {
            if (sender is ImageButton btn)
            {
                AbortSpecificAnimations(btn);
                await btn.ScaleToAsync(0.8, 100);
                await btn.ScaleToAsync(1.0, 100);
            }
            _tts.Stop();
            if (_isPageActive && _historyIndex >= 0 && _historyIndex < _history.Count)
            {
                string key = _history[_historyIndex];
                var animalPair = GameData.AnimalList.FirstOrDefault(x => x.Key == key);
                if (!string.IsNullOrEmpty(animalPair.Value))
                    await _tts.SpeakAsync(animalPair.Value);
            }
        }
        finally { _isNavigating = false; }
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
        } while (nextKey == currentKey);

        return nextKey;
    }

    private async Task ShowCurrentAnimal()
    {
        if (!_isPageActive) return;
        _tts.Stop();

        if (_historyIndex < 0 || _historyIndex >= _history.Count) return;

        string key = _history[_historyIndex];
        var animal = GameData.AnimalList.FirstOrDefault(x => x.Key == key);
        string name = animal.Value ?? "";

        AnimalImage.Source = null;
        AnimalImage.Source = $"{key}.webp";
        AnimalName.Text = name.ToUpper();

        BtnBack.IsEnabled = _historyIndex > 0;
        BtnBack.Opacity = _historyIndex > 0 ? 1 : 0.5;

        AbortSpecificAnimations(AnimalImage);
        AnimalImage.Scale = 0.5;
        AnimalImage.Opacity = 0;

        if (_isPageActive)
        {
            var ttsTask = _tts.SpeakAsync(name);
            await Task.WhenAll(
                AnimalImage.FadeToAsync(1, 400),
                AnimalImage.ScaleToAsync(1, 600, Easing.SpringOut)
            );
            await ttsTask;
        }
    }

    private async void OnAnimalImageTapped(object sender, EventArgs e)
    {
        if (_isNavigating) return;
        _isNavigating = true;
        try
        {
            _tts.Stop();
            AbortSpecificAnimations(AnimalImage);
            
            await AnimalImage.ScaleToAsync(1.2, 150, Easing.SpringOut);
            await AnimalImage.ScaleToAsync(1.0, 150, Easing.SpringOut);

            if (_isPageActive && _historyIndex >= 0 && _historyIndex < _history.Count)
            {
                string key = _history[_historyIndex];
                var animalPair = GameData.AnimalList.FirstOrDefault(x => x.Key == key);
                if (!string.IsNullOrEmpty(animalPair.Value))
                    await _tts.SpeakAsync(animalPair.Value);
            }
        }
        finally { _isNavigating = false; }
    }
}