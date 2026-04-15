using LamToanLop1.Models;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace LamToanLop1.ViewModels;
using LamToanLop1.Services;

public partial class GameViewModel(ITtsService ttsService) : INotifyPropertyChanged
{
	private IQuestion? _currentQuestion;
	private readonly ITtsService _ttsService = ttsService;
    private bool _initialized;

    public async Task InitializeAsync()
	{
		if (_initialized) return;
		_initialized = true;

		// Khởi tạo câu hỏi đầu tiên
		NextQuestion();

		// Nếu muốn đọc câu hỏi đầu tiên thì gọi TTS ở đây
		if (CurrentQuestion != null)
		{
			await _ttsService.SpeakAsync(CurrentQuestion.Title);
		}
	}

	public IQuestion? CurrentQuestion
	{
		get => _currentQuestion;
		private set
		{
			_currentQuestion = value;
			OnPropertyChanged();
		}
	}

	public int Semester { get; private set; } = 1;
	public int Level { get; private set; } = 1;

    public int Stars
    {
        get => Preferences.Get("Stars", 0);
        set
        {
            Preferences.Set("Stars", value);
            OnPropertyChanged();
        }
    }

    public void Start(int semester, int level)
	{
		Semester = semester;
		Level = level;
		NextQuestion();
	}

	public void NextQuestion()
	{
		CurrentQuestion = QuestionFactory.Create(Semester, Level);
	}

	public bool CheckAnswer(string answer)
	{
		if (CurrentQuestion == null) return false;
		return answer == CurrentQuestion.CorrectAnswer;
	}

	public event PropertyChangedEventHandler? PropertyChanged;
	private void OnPropertyChanged([CallerMemberName] string? name = null)
		=> PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
