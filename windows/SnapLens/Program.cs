namespace SnapLens;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        // Teste da montagem: SnapLens --stack saida.png a.png b.png …
        int i = Array.IndexOf(args, "--stack");
        if (i >= 0 && i + 2 < args.Length)
        {
            var d = Composer.Stack(args[(i + 2)..]);
            if (d != null) File.WriteAllBytes(args[i + 1], d);
            Console.WriteLine(d != null ? $"ok {d.Length} bytes" : "falhou");
            return d != null ? 0 : 1;
        }

        // Teste do OCR: SnapLens --ocr imagem.png
        i = Array.IndexOf(args, "--ocr");
        if (i >= 0 && i + 1 < args.Length)
        {
            var text = OCR.Recognize(Path.GetFullPath(args[i + 1])).GetAwaiter().GetResult();
            File.WriteAllText(args[i + 1] + ".txt", text);
            return text.Length > 0 ? 0 : 1;
        }

        // Prints das janelas a partir da UI real: SnapLens --render-ui <pasta> [idioma]
        i = Array.IndexOf(args, "--render-ui");
        if (i >= 0 && i + 1 < args.Length)
        {
            Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
            Application.EnableVisualStyles();
            Shots.Render(args[i + 1], i + 2 < args.Length ? args[i + 2] : null);
            return 0;
        }

        // Uma instância só: abrir de novo mostra a biblioteca da instância que já está na bandeja.
        using var mutex = new Mutex(true, @"Local\SnapLens.SingleInstance", out bool first);
        using var activate = new EventWaitHandle(false, EventResetMode.AutoReset, @"Local\SnapLens.Activate");
        if (!first)
        {
            activate.Set();
            return 0;
        }

        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.ThreadException += (_, e) => Trace.Log("ERRO não tratado (UI): " + e.Exception);
        AppDomain.CurrentDomain.UnhandledException += (_, e) => Trace.Log("ERRO não tratado: " + e.ExceptionObject);
        TaskScheduler.UnobservedTaskException += (_, e) => { Trace.Log("ERRO em Task: " + e.Exception); e.SetObserved(); };

        // O contexto de sincronização do WinForms precisa existir antes do TrayApp (eventos assíncronos voltam à UI).
        SynchronizationContext.SetSynchronizationContext(new WindowsFormsSynchronizationContext());
        var app = new TrayApp(background: args.Contains("--background"));
        var waiter = new Thread(() =>
        {
            while (activate.WaitOne()) app.Activate();
        }) { IsBackground = true, Name = "SnapLens.Activate" };
        waiter.Start();
        Application.Run(app);
        return 0;
    }
}
