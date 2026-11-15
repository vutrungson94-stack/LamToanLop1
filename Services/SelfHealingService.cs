using System.Diagnostics;
using System.IO;
using System.Text.Json;

namespace LamToanLop1.Services;

public interface ISelfHealingService
{
    void AttachGlobalHandlers();
    void LogCrash(Exception ex, string source);
    int GetCrashCount();
    bool TryRecover();
    Task<bool> ExecuteWithRetryAsync(Func<Task> action, int maxRetries = 3);
}

public sealed class SelfHealingService : ISelfHealingService
{
    public static SelfHealingService? Current { get; private set; }

    private readonly string _crashLogPath;
    private readonly string _statePath;
    private int _crashCount;

    public SelfHealingService()
    {
        Current = this;
        var dir = FileSystem.AppDataDirectory;
        Directory.CreateDirectory(dir);
        _crashLogPath = Path.Combine(dir, "crash.log");
        _statePath = Path.Combine(dir, "selfheal.state.json");
        _crashCount = ReadCrashCount();
    }

    public void AttachGlobalHandlers()
    {
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
        {
            if (e.ExceptionObject is Exception ex) LogCrash(ex, "AppDomain.UnhandledException");
        };
        TaskScheduler.UnobservedTaskException += (_, e) =>
        {
            LogCrash(e.Exception, "TaskScheduler.UnobservedTaskException");
            e.SetObserved();
        };
    }

    public void LogCrash(Exception ex, string source)
    {
        try
        {
            _crashCount++;
            var entry = $"[{DateTime.UtcNow:O}] SOURCE={source} CRASH_COUNT={_crashCount}\n{ex}\n---\n";
            File.AppendAllText(_crashLogPath, entry);
            PersistState();
            Debug.WriteLine($"[SELF-HEAL] Crash logged: {source} (count={_crashCount})");
        }
        catch (Exception logEx)
        {
            Debug.WriteLine($"[SELF-HEAL] LogCrash failed: {logEx}");
        }
    }

    public int GetCrashCount() => _crashCount;

    public bool TryRecover()
    {
        try
        {
            // Remove cached temp files that may cause repeated failures
            var cacheDir = FileSystem.CacheDirectory;
            if (Directory.Exists(cacheDir))
            {
                foreach (var file in Directory.EnumerateFiles(cacheDir, "*", SearchOption.AllDirectories))
                {
                    try { File.Delete(file); } catch { }
                }
            }

            // Reset crash counter after successful recovery
            _crashCount = 0;
            PersistState();
            Debug.WriteLine("[SELF-HEAL] Recovery completed");
            return true;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[SELF-HEAL] Recovery failed: {ex}");
            return false;
        }
    }

    public async Task<bool> ExecuteWithRetryAsync(Func<Task> action, int maxRetries = 3)
    {
        for (var attempt = 1; attempt <= maxRetries; attempt++)
        {
            try
            {
                await action();
                return true;
            }
            catch (Exception ex)
            {
                LogCrash(ex, $"ExecuteWithRetry attempt {attempt}/{maxRetries}");
                if (attempt == maxRetries) return false;
                await Task.Delay(TimeSpan.FromMilliseconds(200 * attempt));
            }
        }
        return false;
    }

    private int ReadCrashCount()
    {
        try
        {
            if (!File.Exists(_statePath)) return 0;
            var json = File.ReadAllText(_statePath);
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.TryGetProperty("crashCount", out var prop))
                return prop.GetInt32();
        }
        catch { }
        return 0;
    }

    private void PersistState()
    {
        try
        {
            var json = JsonSerializer.Serialize(new { crashCount = _crashCount, lastUpdate = DateTime.UtcNow });
            File.WriteAllText(_statePath, json);
        }
        catch { }
    }
}