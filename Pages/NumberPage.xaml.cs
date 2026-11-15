using LamToanLop1.Helpers;
using LamToanLop1.Services;

namespace LamToanLop1.Pages;

public partial class NumberPage : ContentPage
{
    // 🔊 Giọng đọc tự nhiên (Edge TTS - Hoài My)
    private readonly ITtsService _tts;

    // 🔄 Chỉ pre-cache 1 lần khi mở trang
    private bool _precacheStarted;

    // 🦁🐯🐻 Bộ emoji động vật dễ thương, luân phiên theo số
    private readonly string[] _animalEmojis = new[]
    {
        "🦁", "🐯", "🐻", "🐨", "🐼", "🐸", "🦄", "🦊",
        "🐷", "🐰", "🐹", "🐱", "🐶", "🐵", "🐔", "🐙",
        "🐞", "🐳", "🦕", "🦖", "🦋", "🐌", "🐝", "🦉"
    };

    // 📐 Danh sách thẻ số để cập nhật kích thước khi màn hình đổi
    private readonly List<(Border card, Label emoji, Label number)> _cardRefs = new();

    // 🎨 Bảng màu nền thẻ số: mỗi con vật 1 màu nền khác nhau
    private readonly Color[] _cardColors = new[]
    {
        Color.FromArgb("#FFCDD2"), // đỏ nhạt
        Color.FromArgb("#C8E6C9"), // xanh lá nhạt
        Color.FromArgb("#BBDEFB"), // xanh dương nhạt
        Color.FromArgb("#FFF9C4"), // vàng nhạt
        Color.FromArgb("#E1BEE7"), // tím nhạt
        Color.FromArgb("#B2DFDB"), // ngọc nhạt
        Color.FromArgb("#F0F4C3"), // chanh nhạt
        Color.FromArgb("#FFCCBC"), // cam nhạt
    };

    // 🎲 Dãy số ngẫu nhiên hiện tại (chỉ khi ở chế độ random 21-100)
    private bool _isRandomMode;

    public NumberPage(ITtsService tts)
    {
        InitializeComponent();
        _tts = tts;
        NumbersGrid.SizeChanged += (s, e) => ApplyCardLayout();
        this.SizeChanged += (_, __) => ApplySelectionResponsive();
    }

    private void ApplySelectionResponsive()
    {
        if (Width <= 0 || RangeSelectionLayout == null) return;
        try
        {
            // Scale các nút chọn phạm vi (300x70 -> responsive, nút Back 200x55)
            foreach (var btn in RangeSelectionLayout.Children.OfType<Button>())
            {
                bool isBack = btn.Text?.Contains("QUAY LẠI") == true;
                btn.WidthRequest = isBack ? ResponsiveHelper.W(200) : ResponsiveHelper.W(300);
                btn.HeightRequest = isBack ? ResponsiveHelper.H(55) : ResponsiveHelper.H(70);
                btn.FontSize = ResponsiveHelper.Font(isBack ? 18 : 20);
                btn.CornerRadius = (int)ResponsiveHelper.S(25);
            }
            // Tiêu đề 36 -> scale
            var title = RangeSelectionLayout.Children.OfType<Label>().FirstOrDefault();
            if (title != null) title.FontSize = ResponsiveHelper.Font(36);
            // Nút trong NumbersDisplayLayout
            var backBtn = NumbersDisplayLayout.FindByName<Button>("BackToRangesButton");
            // Fallback: tìm Button trong Grid Row2
            if (backBtn == null)
            {
                var gridBtn = NumbersDisplayLayout.Children.OfType<Button>().FirstOrDefault();
                if (gridBtn != null) { gridBtn.WidthRequest = ResponsiveHelper.W(200); gridBtn.HeightRequest = ResponsiveHelper.H(55); gridBtn.FontSize = ResponsiveHelper.Font(16); }
            }
            else
            {
                // Cả hai nút trong hàng (CHỌN PHẠM VI KHÁC + DÃY SỐ NGẪU NHIÊN KHÁC) đều scale
                var newBtn = NumbersDisplayLayout.FindByName<Button>("GenerateRandomButton");
                if (newBtn != null)
                {
                    newBtn.HeightRequest = ResponsiveHelper.H(55);
                    newBtn.FontSize = ResponsiveHelper.Font(14);
                }
                backBtn.HeightRequest = ResponsiveHelper.H(55);
                backBtn.FontSize = ResponsiveHelper.Font(14);
            }
        }
        catch { }
    }

    // 📐 Tính khung hình vuông + khoảng cách đều, co giãn theo độ rộng màn hình
    private void ApplyCardLayout()
    {
        double gridWidth = NumbersGrid.Width;
        if (gridWidth <= 0) return;

        double gap = gridWidth * 0.03;            // khoảng cách tỷ lệ 3% chiều rộng
        double side = (gridWidth - 2 * gap) / 3;  // cạnh hình vuông (khớp đúng cột *)

        NumbersGrid.Padding = new Thickness(gap);
        NumbersGrid.ColumnSpacing = gap;
        NumbersGrid.RowSpacing = gap;

        foreach (var (card, emoji, number) in _cardRefs)
        {
            card.HeightRequest = side;            // rộng tự lấp đầy cột => luôn vuông
            emoji.FontSize = side * 0.30;
            number.FontSize = side * 0.42;
            if (card.StrokeShape is Microsoft.Maui.Controls.Shapes.RoundRectangle rr)
                rr.CornerRadius = side * 0.12;
        }
    }

    // ========== PRE-CACHE GIỌNG SỐ 0-100 ==========
    protected override void OnAppearing()
    {
        base.OnAppearing();
        ApplySelectionResponsive();
        if (_precacheStarted) return;
        _precacheStarted = true;
        _ = Task.Run(async () =>
        {
            try { await _tts.PreCacheNumberVoicesAsync(); }
            catch { }
        });
    }

    protected override void OnSizeAllocated(double width, double height)
    {
        base.OnSizeAllocated(width, height);
        if (width > 0) ApplySelectionResponsive();
    }

    // ========== STATE 1: Chọn phạm vi ==========

    private async void OnRange0to9Clicked(object sender, EventArgs e)
    {
        await ShowNumbersAsync(min: 0, max: 9);
    }

    private async void OnRange10to20Clicked(object sender, EventArgs e)
    {
        await ShowNumbersAsync(min: 10, max: 20);
    }

    private async void OnRange20PlusClicked(object sender, EventArgs e)
    {
        try
        {
            // Hiển thị 12 số ngẫu nhiên 21-100 để tránh quá tải 80 thẻ gây blank/OOM
            var picks = RandomPicks(21, 100, 12);
            await ShowNumbersForListAsync(picks);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"OnRange20PlusClicked: {ex}");
            await ShowNumbersAsync(min: 21, max: 32);
        }
    }

    private static List<int> RandomPicks(int min, int max, int count)
    {
        var rnd = System.Random.Shared;
        return Enumerable.Range(min, max - min + 1).OrderBy(_ => rnd.Next()).Take(count).OrderBy(n => n).ToList();
    }

    private async void OnGenerateRandomClicked(object sender, EventArgs e)
    {
        if (_isBusy || !_isRandomMode) return;
        try
        {
            // Sinh dãy số ngẫu nhiên MỚI (khác hoàn toàn dãy cũ)
            var picks = RandomPicks(21, 100, 12);
            await ShowNumbersForListAsync(picks);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"OnGenerateRandomClicked: {ex}");
        }
    }

    private async Task ShowNumbersForListAsync(List<int> numbers)
    {
        if (_isBusy) return;
        _isBusy = true;
        try
        {
            if (numbers == null || numbers.Count == 0) return;
            _isRandomMode = true;
            RangeTitleLabel.Text = $"🎯 SỐ NGẪU NHIÊN";
            if (this.FindByName<Button>("GenerateRandomButton") is { } genBtn)
                genBtn.IsVisible = true;
            await ZoomOutThenClearAsync();
            int count = numbers.Count;
            int rowCount = (count + 2) / 3;
            for (int r = 0; r < rowCount; r++)
                NumbersGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var cards = new List<Border>();
        _cardRefs.Clear();
        // Tạo thẻ cho danh sách ngẫu nhiên
        for (int idx = 0; idx < numbers.Count; idx++)
        {
            int number = numbers[idx];
            int colorIndex = idx % _cardColors.Length;
            int emojiIndex = idx % _animalEmojis.Length;
            var lblEmoji = new Label { Text = _animalEmojis[emojiIndex], FontSize = 34, HorizontalOptions = LayoutOptions.Center, VerticalOptions = LayoutOptions.End };
            var lblNumber = new Label { Text = number.ToString(), FontSize = 46, FontAttributes = FontAttributes.Bold, FontFamily = "FredokaBold", TextColor = Color.FromArgb("#333333"), HorizontalOptions = LayoutOptions.Center, VerticalOptions = LayoutOptions.Start };
            var cardContent = new VerticalStackLayout { Spacing = 2, Padding = new Thickness(0, 6, 0, 4), HorizontalOptions = LayoutOptions.Center, VerticalOptions = LayoutOptions.Center, Children = { lblEmoji, lblNumber } };
            var card = new Border { BackgroundColor = _cardColors[colorIndex], StrokeShape = new Microsoft.Maui.Controls.Shapes.RoundRectangle { CornerRadius = 24 }, StrokeThickness = 0, HorizontalOptions = LayoutOptions.Fill, VerticalOptions = LayoutOptions.Fill, Content = cardContent, Shadow = new Shadow { Brush = Colors.Black, Offset = new Point(3, 3), Opacity = 0.25f, Radius = 6 } };
            var tap = new TapGestureRecognizer();
            tap.Tapped += async (s, e) => await SpeakNumberAsync(number);
            card.GestureRecognizers.Add(tap);
            tap.Tapped += async (s, e) => { try { await card.ScaleToAsync(0.90, 80); await card.ScaleToAsync(1.0, 120); } catch { } };
            NumbersGrid.Children.Add(card);
            Grid.SetRow(card, idx / 3);
            Grid.SetColumn(card, idx % 3);
            cards.Add(card);
            _cardRefs.Add((card, lblEmoji, lblNumber));
            card.Opacity = 0; card.Scale = 0.7;
        }
            RangeSelectionLayout.IsVisible = false;
            RangeSelectionLayout.Opacity = 1;
            NumbersDisplayLayout.IsVisible = true;
            NumbersDisplayLayout.Opacity = 1;
            ApplyCardLayout();
            // Zoom-in tất cả cùng lúc (mờ -> rõ)
            await AnimateCardsInAsync(cards);
        }
        catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"ShowNumbersForListAsync: {ex}"); }
        finally { _isBusy = false; }
    }

    private async void OnBackToMenuClicked(object sender, EventArgs e)
    {
        await Navigation.PopAsync();
    }

    // ========== STATE 2: Hiển thị số + Thú cưng ==========

    private async Task ShowNumbersAsync(int min, int max)
    {
        if (_isBusy) return;
        _isBusy = true;
        try
        {
            _isRandomMode = false;
            if (this.FindByName<Button>("GenerateRandomButton") is { } genBtn)
                genBtn.IsVisible = false;

            RangeTitleLabel.Text = $"🎯 SỐ TỪ {min} ĐẾN {max}";

            // Dọn sạch thẻ cũ (zoom hết cỡ + mờ dần rồi Xóa)
            await ZoomOutThenClearAsync();

        // Đủ số hàng cho 3 cột
        int count = max - min + 1;
        int rowCount = (count + 2) / 3;
        for (int r = 0; r < rowCount; r++)
            NumbersGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var cards = new List<Border>();
        _cardRefs.Clear();

        for (int i = min; i <= max; i++)
        {
            int number = i; // capture cho closure
            int colorIndex = (i - min) % _cardColors.Length;
            int emojiIndex = (i - min) % _animalEmojis.Length;

            // 🐷 Emoji con vật
            var lblEmoji = new Label
            {
                Text = _animalEmojis[emojiIndex],
                FontSize = 34,
                HorizontalOptions = LayoutOptions.Center,
                VerticalOptions = LayoutOptions.End
            };

            // 🔢 Con số to (FredokaBold hoặc Baloo bạn đang có)
            var lblNumber = new Label
            {
                Text = number.ToString(),
                FontSize = 46,
                FontAttributes = FontAttributes.Bold,
                // 💡 Nếu chưa tải Fredoka, đổi về "BalooTammudu2ExtraBold"
                FontFamily = "FredokaBold",
                TextColor = Color.FromArgb("#333333"),
                HorizontalOptions = LayoutOptions.Center,
                VerticalOptions = LayoutOptions.Start
            };

            // Xếp chồng: Thú lên trên, Số xuống dưới
            var cardContent = new VerticalStackLayout
            {
                Spacing = 2,
                Padding = new Thickness(0, 6, 0, 4),
                HorizontalOptions = LayoutOptions.Center,
                VerticalOptions = LayoutOptions.Center,
                Children = { lblEmoji, lblNumber }
            };

            var card = new Border
            {
                BackgroundColor = _cardColors[colorIndex],
                StrokeShape = new Microsoft.Maui.Controls.Shapes.RoundRectangle { CornerRadius = 24 },
                StrokeThickness = 0,
                HorizontalOptions = LayoutOptions.Fill,
                VerticalOptions = LayoutOptions.Fill,
                Content = cardContent,
                Shadow = new Shadow
                {
                    Brush = Colors.Black,
                    Offset = new Point(3, 3),
                    Opacity = 0.25f,
                    Radius = 6
                }
            };

            // Nhấn để đọc: "Một", "Hai", "Mười lăm"...
            var tap = new TapGestureRecognizer();
            tap.Tapped += async (s, e) => await SpeakNumberAsync(number);
            card.GestureRecognizers.Add(tap);

            // Nhấn giữ xuống nhẹ (visual feedback)
            tap.Tapped += async (s, e) =>
            {
                await card.ScaleToAsync(0.90, 80, Easing.CubicOut);
                await card.ScaleToAsync(1.0, 120, Easing.SpringOut);
            };

            NumbersGrid.Children.Add(card);
            Grid.SetRow(card, (i - min) / 3);
            Grid.SetColumn(card, (i - min) % 3);
            cards.Add(card);
            _cardRefs.Add((card, lblEmoji, lblNumber));

            // Ẩn trước để animation
            card.Opacity = 0;
            card.Scale = 0.7;
        }

            // Chuyển State mượt mà - reset Opacity để không bị mờ sau khi back
            RangeSelectionLayout.IsVisible = false;
            RangeSelectionLayout.Opacity = 1;
            NumbersDisplayLayout.IsVisible = true;
            NumbersDisplayLayout.Opacity = 1;
            ApplyCardLayout();
            // Zoom-in tất cả cùng lúc (mờ -> rõ)
            await AnimateCardsInAsync(cards);
        }
        catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"ShowNumbersAsync: {ex}"); }
        finally { _isBusy = false; }

    }

    private async Task SpeakNumberAsync(int number)
    {
        try
        {
            await _tts.SpeakAsync(number.ToString());
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"TTS Error (offline silent): {ex.Message}");
            // Không hiện alert khi offline để không làm phiền bé - chỉ log
        }
    }

    private bool _isBusy;
    private async void OnBackToRangesClicked(object sender, EventArgs e)
    {
        if (_isBusy) return;
        _isBusy = true;
        try
        {
            await ZoomOutThenClearAsync();
            NumbersDisplayLayout.IsVisible = false;
            NumbersDisplayLayout.Opacity = 1;
            RangeSelectionLayout.Opacity = 0;
            RangeSelectionLayout.IsVisible = true;
            await RangeSelectionLayout.FadeToAsync(1, 250);
        }
        finally { _isBusy = false; }
    }
    // Thu nhỏ thẻ hiện tại về 1.8x rồi mờ dần cho đến khi biến mất hẳn
    private async Task ZoomOutThenClearAsync()
    {
        var oldCards = NumbersGrid.Children.OfType<View>().OfType<Border>().ToList();
        if (oldCards.Count > 0)
        {
            var tasks = oldCards.Select(async c =>
            {
                try
                {
                    await Task.WhenAll(
                        c.FadeToAsync(0, 260, Easing.CubicIn),
                        c.ScaleToAsync(1.8, 300, Easing.CubicIn));
                }
                catch { }
            }).ToArray();
            try { await Task.WhenAll(tasks); } catch { }
        }
        NumbersGrid.Children.Clear();
        NumbersGrid.RowDefinitions.Clear();
        _cardRefs.Clear();
    }

    // Zoom thẻ: từ mờ (opacity 0) + nhỏ (scale 0.7) -> rõ (1) + đúng kích thước (1.0) cùng lúc
    private async Task AnimateCardsInAsync(List<Border> cards)
    {
        var tasks = cards.Select(async c =>
        {
            try
            {
                await Task.WhenAll(
                    c.FadeToAsync(1, 320, Easing.CubicOut),
                    c.ScaleToAsync(1.0, 380, Easing.SpringOut));
            }
            catch { }
        }).ToArray();
        try { await Task.WhenAll(tasks); } catch { }
    }
    }
