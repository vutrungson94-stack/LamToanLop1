using LamToanLop1.Pages;
using Microsoft.Maui.Controls;

namespace LamToanLop1.Pages;

public partial class NumberPage : ContentPage
{
    public NumberPage()
    {
        InitializeComponent();
    }

    private async void OnRange0to9Clicked(object sender, EventArgs e)
    {
        if (sender is Button btn)
        {
            await btn.ScaleToAsync(0.9, 50);
            await btn.ScaleToAsync(1.0, 50);
        }
        
        // Navigate đến GamePage với range=9 (0-9)
        await Shell.Current.GoToAsync($"{nameof(GamePage)}?range=9&level=1");
    }

    private async void OnRange10to20Clicked(object sender, EventArgs e)
    {
        if (sender is Button btn)
        {
            await btn.ScaleToAsync(0.9, 50);
            await btn.ScaleToAsync(1.0, 50);
        }
        
        // Navigate đến GamePage với range=20 (10-20)
        await Shell.Current.GoToAsync($"{nameof(GamePage)}?range=20&level=1");
    }

    private async void OnRange20PlusClicked(object sender, EventArgs e)
    {
        if (sender is Button btn)
        {
            await btn.ScaleToAsync(0.9, 50);
            await btn.ScaleToAsync(1.0, 50);
        }
        
        // Navigate đến GamePage với range=100 (21-100 random)
        await Shell.Current.GoToAsync($"{nameof(GamePage)}?range=100&level=1");
    }

    private async void OnBackToMenuClicked(object sender, EventArgs e)
    {
        if (sender is Button btn)
        {
            await btn.ScaleToAsync(0.9, 50);
            await btn.ScaleToAsync(1.0, 50);
        }
        
        await Shell.Current.GoToAsync("//MenuPage");
    }
}