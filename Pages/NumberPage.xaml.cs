namespace LamToanLop1.Pages;

public partial class NumberPage : ContentPage
{
    // 🦁🐯🐻 Bộ emoji động vật dễ thương, luân phiên theo số
    private readonly string[] _animalEmojis = new[]
    {
        "🦁", "🐯", "🐻", "🐨", "🐼", "🐸", "🦄", "🦊",
        "🐷", "🐰", "🐹", "🐱", "🐶", "🐵", "🐔", "🐙",
        "🐞", "🐳", "🦕", "🦖", "🦋", "🐌", "🐝", "🦉"
    };

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

    public NumberPage()
    {
        InitializeComponent();
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
        await ShowNumbersAsync(min: 21, max: 100);
    }

    private async void OnBackToMenuClicked(object sender, EventArgs e)
    {
        await Navigation.PopAsync();
    }

    // ========== STATE 2: Hiển thị số + Thú cưng ==========

    private async Task ShowNumbersAsync(int min, int max)
    {
        RangeTitleLabel.Text = $"🎯 SỐ TỪ {min} ĐẾN {max}";

        // Dọn sạch thẻ cũ
        NumbersFlex.Children.Clear();

        var cards = new List<Border>();

        for (int i = min; i <= max; i++)
        {
            int number = i; // capture cho closure
            int colorIndex = (i - min) % _cardColors.Length;
            int emojiIndex = (i - min) % _animalEmojis.Length;

            // 🐷 Emoji con vật
            var lblEmoji = new Label
            {
                Text = _animalEmojis[emojiIndex],
                FontSize = 42,
                HorizontalOptions = LayoutOptions.Center,
                VerticalOptions = LayoutOptions.End
            };

            // 🔢 Con số to (FredokaBold hoặc Baloo bạn đang có)
            var lblNumber = new Label
            {
                Text = number.ToString(),
                FontSize = 56,
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
                Padding = new Thickness(0, 8, 0, 4),
                Children = { lblEmoji, lblNumber }
            };

            var card = new Border
            {
                BackgroundColor = _cardColors[colorIndex],
                StrokeShape = new Microsoft.Maui.Controls.Shapes.RoundedRectangle { CornerRadius = 28 },
                StrokeThickness = 0,
                WidthRequest = 150,
                HeightRequest = 150,
                Margin = new Thickness(8),
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

            NumbersFlex.Children.Add(card);
            cards.Add(card);

            // Ẩn trước để animation
            card.Opacity = 0;
            card.Scale = 0.7;
        }

        // Chuyển State mượt mà
        RangeSelectionLayout.IsVisible = false;
        NumbersDisplayLayout.IsVisible = true;

        // 🎬 Animation stagger: thẻ bay ra từng cái
        foreach (var card in cards)
        {
            await card.FadeToAsync(1, 180, Easing.CubicOut);
            await card.ScaleToAsync(1.0, 220, Easing.SpringOut);
        }
    }

    private async Task SpeakNumberAsync(int number)
    {
        try
        {
            // Định dạng tiếng Việt: 15 -> "mười lăm" (TextToSpeech tự xử lý nếu locale đúng)
            // Hoặc bạn có thể dùng thư viện đọc số tiếng Việt chuẩn nếu cần
            string text = number.ToString("N0", new System.Globalization.CultureInfo("vi-VN")).Replace(".", " ");

            var options = new SpeechOptions
            {
                Pitch = 1.15f, // Giọng cao vui vui
                Volume = 1.0f
            };

            var locales = await TextToSpeech.GetLocalesAsync();
            var viLocale = locales.FirstOrDefault(l =>
                l.Language.StartsWith("vi", StringComparison.OrdinalIgnoreCase));

            if (viLocale != null)
                options.Locale = viLocale;

            await TextToSpeech.Default.SpeakAsync(text, options);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"TTS Error: {ex.Message}");
            await DisplayAlert("Oops!", "Máy chưa thể đọc số lúc này.", "OK");
        }
    }

    private async void OnBackToRangesClicked(object sender, EventArgs e)
    {
        await NumbersDisplayLayout.FadeToAsync(0, 200);
        NumbersDisplayLayout.IsVisible = false;
        NumbersFlex.Children.Clear();

        RangeSelectionLayout.Opacity = 0;
        RangeSelectionLayout.IsVisible = true;
        await RangeSelectionLayout.FadeToAsync(1, 250);
    }
}