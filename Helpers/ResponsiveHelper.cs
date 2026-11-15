namespace LamToanLop1.Helpers;

/// <summary>
/// Helper co giãn UI theo kích thước màn hình (dọc, portrait)
/// Base design: 360dp x 640dp (phone phổ thông). Scale tuyến tính theo chiều rộng.
/// </summary>
public static class ResponsiveHelper
{
    // Base width theo thiết kế (dp)
    private const double BaseWidthDp = 360.0;
    private const double BaseHeightDp = 640.0;

    // Giới hạn scale để không quá to/nhỏ trên tablet hoặc máy rất nhỏ
    private const double MinScale = 0.85;
    private const double MaxScale = 1.35;

    private static double? _cachedScale;
    private static double _lastWidthDp = -1;

    /// <summary>
    /// Tỷ lệ scale hiện tại (1.0 = 360dp). Tự tính theo màn hình thực tế, clamp 0.85-1.35
    /// </summary>
    public static double Scale
    {
        get
        {
            try
            {
                var info = DeviceDisplay.MainDisplayInfo;
                if (info.Width == 0 || info.Density == 0) return 1.0;
                double widthDp = info.Width / info.Density;
                // Nếu xoay ngang (không nên xảy ra do lock portrait) thì vẫn lấy chiều nhỏ làm width
                if (info.Orientation == DisplayOrientation.Landscape)
                    widthDp = Math.Min(info.Width, info.Height) / info.Density;

                if (Math.Abs(widthDp - _lastWidthDp) < 1 && _cachedScale.HasValue)
                    return _cachedScale.Value;

                double raw = widthDp / BaseWidthDp;
                double clamped = Math.Clamp(raw, MinScale, MaxScale);
                _cachedScale = clamped;
                _lastWidthDp = widthDp;
                return clamped;
            }
            catch { return 1.0; }
        }
    }

    public static void Invalidate() { _cachedScale = null; _lastWidthDp = -1; }

    // Scale giá trị
    public static double S(double baseValue) => Math.Round(baseValue * Scale, 1);
    public static double Font(double baseSize) => Math.Round(baseSize * Scale, 1);
    public static Thickness Thick(double baseUniform) => new Thickness(S(baseUniform));
    public static Thickness Thick(double horizontal, double vertical) => new Thickness(S(horizontal), S(vertical));
    public static CornerRadius Corner(double baseRadius) => new CornerRadius(S(baseRadius));

    // Helper cho Width/HeightRequest
    public static double W(double baseWidth) => S(baseWidth);
    public static double H(double baseHeight) => S(baseHeight);
}
