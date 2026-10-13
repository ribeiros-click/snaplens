namespace SnapLens;

/// Trace de diagnóstico: grava em %LOCALAPPDATA%\SnapLens\Logs\snaplens.log.
/// Barato o suficiente para ficar ligado sempre.
public static class Trace
{
    private const long MaxBytes = 2 * 1024 * 1024;
    private static readonly object Gate = new();

    public static string FilePath { get; } = InitPath();

    private static string InitPath()
    {
        var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SnapLens", "Logs");
        Directory.CreateDirectory(dir);
        return Path.Combine(dir, "snaplens.log");
    }

    public static void Log(string message,
                           [System.Runtime.CompilerServices.CallerFilePath] string file = "",
                           [System.Runtime.CompilerServices.CallerLineNumber] int line = 0)
    {
        var thread = Environment.CurrentManagedThreadId == 1 ? "main" : "bg";
        var text = $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff} [{thread}] {Path.GetFileNameWithoutExtension(file)}:{line} {message}\n";
        System.Diagnostics.Debug.Write(text);
        ThreadPool.QueueUserWorkItem(_ =>
        {
            lock (Gate)
            {
                try
                {
                    var fi = new FileInfo(FilePath);
                    if (fi.Exists && fi.Length > MaxBytes)
                    {
                        var old = Path.ChangeExtension(FilePath, ".1.log");
                        File.Delete(old);
                        File.Move(FilePath, old);
                    }
                    File.AppendAllText(FilePath, text);
                }
                catch { /* diagnóstico nunca derruba o app */ }
            }
        });
    }

    /// Últimas `lines` linhas do log (para "Copiar diagnóstico").
    public static string Tail(int lines = 200)
    {
        try
        {
            lock (Gate)
            {
                var all = File.ReadAllLines(FilePath);
                return string.Join("\n", all.Skip(Math.Max(0, all.Length - lines)));
            }
        }
        catch { return "(log vazio)"; }
    }
}
