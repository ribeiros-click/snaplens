using System.Diagnostics;
using System.Runtime.InteropServices;
using static SnapLens.Loc;

namespace SnapLens;

/// App da bandeja do sistema (equivalente ao AppDelegate do macOS).
public sealed class TrayApp : ApplicationContext
{
    public static TrayApp Instance { get; private set; } = null!;

    private readonly NotifyIcon tray;
    private readonly MessageWindow messages = new();
    private readonly Store store = Store.Shared;
    private readonly System.Windows.Forms.Timer recTimer = new() { Interval = 500 };
    private readonly System.Windows.Forms.Timer clipDebounce = new() { Interval = 150 };
    private readonly SynchronizationContext ui;
    private LibraryForm? library;
    private SettingsForm? settings;
    private ShareResultForm? shareForm;
    private uint ownClipboardSeq;
    private bool isStartingCapture;
    private bool suspended;
    private const int EscapeHotKeyID = 99;

    public TrayApp(bool background)
    {
        Instance = this;
        ui = SynchronizationContext.Current ?? new WindowsFormsSynchronizationContext();
        Trace.Log($"=== SnapLens iniciado · {Environment.OSVersion} · telas={Screen.AllScreens.Length}");

        tray = new NotifyIcon { Icon = Icons.Tray(false), Text = "SnapLens", Visible = true };
        tray.MouseUp += (_, e) =>
        {
            // Clique esquerdo também abre o menu (como o ícone da barra de menus do macOS).
            if (e.Button == MouseButtons.Left)
                typeof(NotifyIcon).GetMethod("ShowContextMenu", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)?.Invoke(tray, null);
        };
        tray.DoubleClick += (_, _) => ShowLibrary();
        RebuildMenu();

        ApplyShortcuts();
        Shortcuts.Changed += () => { suspended = false; ApplyShortcuts(); RebuildMenu(); };
        Shortcuts.Suspend += on =>
        {
            if (on) { suspended = true; for (int i = 1; i <= Shortcuts.All.Length; i++) messages.Unregister(i); }
            else if (suspended) { suspended = false; ApplyShortcuts(); }
        };

        messages.ClipboardChanged += () => { clipDebounce.Stop(); clipDebounce.Start(); };
        clipDebounce.Tick += (_, _) => { clipDebounce.Stop(); PollClipboard(); };
        ownClipboardSeq = GetClipboardSequenceNumber();
        messages.ListenClipboard();

        ScreenRecorder.Shared.StateChanged += RecordingStateChanged;
        recTimer.Tick += (_, _) => UpdateRecordingTimer();

        // Troca de idioma: refaz o menu e as janelas (que guardam textos já traduzidos).
        L10n.Changed += () =>
        {
            RebuildMenu();
            library?.Close(); library = null;
            shareForm?.Close(); shareForm = null;
            bool wasOpen = settings is { Visible: true };
            settings?.Close(); settings = null;
            if (wasOpen) ShowSettings();
        };
        Microsoft.Win32.SystemEvents.UserPreferenceChanged += (_, _) => ui.Post(_ => RecordingStateChanged(), null);

        if (!background && !Settings.Data.WelcomeShown)
        {
            Settings.Data.WelcomeShown = true;
            Settings.Save();
            Toast.Show(L("SnapLens está na bandeja do sistema, perto do relógio. Use %@ para capturar uma seleção.", ShortcutAction.region.Get().Display), Icons.Info);
        }
    }

    /// Outra instância pediu para abrir: mostra a biblioteca.
    public void Activate() => ui.Post(_ => ShowLibrary(), null);

    // MARK: Menu

    private void RebuildMenu()
    {
        var old = tray.ContextMenuStrip;
        var menu = new ContextMenuStrip();
        menu.Items.Add(L("Sobre o SnapLens"), null, (_, _) => ShowAbout());
        menu.Items.Add(new ToolStripSeparator());
        foreach (var action in Shortcuts.All)
        {
            var title = action == ShortcutAction.record && ScreenRecorder.Shared.IsRecording ? L("Parar gravação") : action.Title();
            var item = new ToolStripMenuItem(title + (action == ShortcutAction.history ? "…" : ""), null, (_, _) => Run(action))
            {
                ShortcutKeyDisplayString = action.Get().Display,
                Tag = action,
            };
            menu.Items.Add(item);
            if (action == ShortcutAction.record) menu.Items.Add(new ToolStripSeparator());
        }
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(L("Cancelar captura em andamento"), null, (_, _) => CancelCapture());
        var diag = new ToolStripMenuItem(L("Diagnóstico"));
        diag.DropDownItems.Add(L("Mostrar log no Explorer"), null, (_, _) => RevealInExplorer(Trace.FilePath));
        diag.DropDownItems.Add(L("Copiar últimas 200 linhas do log"), null, (_, _) => { CopyText(Trace.Tail(200)); Toast.Show(L("Log copiado — cole no chat"), Icons.Copy); });
        menu.Items.Add(diag);
        menu.Items.Add(L("Ajustes…"), null, (_, _) => ShowSettings());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(L("Sair do SnapLens"), null, (_, _) => Quit());
        tray.ContextMenuStrip = menu;
        old?.Dispose();
    }

    private void Run(ShortcutAction action)
    {
        switch (action)
        {
            case ShortcutAction.region: _ = StartCapture(true, null); break;
            case ShortcutAction.full: _ = StartCapture(false, null); break;
            case ShortcutAction.ocr: _ = StartCapture(true, ShotAction.ocr); break;
            case ShortcutAction.describe: _ = StartCapture(true, ShotAction.describe); break;
            case ShortcutAction.record: ToggleRecording(); break;
            case ShortcutAction.history: ShowLibrary(); break;
        }
    }

    private void ApplyShortcuts()
    {
        int i = 1;
        foreach (var action in Shortcuts.All)
        {
            var sc = action.Get();
            var a = action;
            if (!messages.Register(i++, sc, () => Run(a)))
                Toast.Show(L("Atalho %@ (%@) já está em uso por outro app", sc.Display, action.Title()), Icons.Warning);
        }
    }

    // MARK: Gravação

    private void ToggleRecording()
    {
        var rec = ScreenRecorder.Shared;
        if (rec.IsRecording) { rec.Stop(); return; }
        Toast.Dismiss();
        try
        {
            rec.Start(Capture.ScreenUnderMouse());
            Toast.Show(L("Gravando… use o atalho ou o menu para parar"), Icons.Record);
        }
        catch (Exception e)
        {
            Trace.Log("gravação: erro ao iniciar: " + e);
            Toast.Show(L("Erro na gravação: %@", e.Message), Icons.Warning);
        }
    }

    private void RecordingStateChanged()
    {
        RebuildMenu();
        bool recording = ScreenRecorder.Shared.IsRecording;
        var old = tray.Icon;
        tray.Icon = Icons.Tray(recording);
        old?.Dispose();
        if (recording) { recTimer.Start(); UpdateRecordingTimer(); }
        else { recTimer.Stop(); tray.Text = "SnapLens"; }
    }

    private void UpdateRecordingTimer()
    {
        if (ScreenRecorder.Shared.StartDate is not DateTime start) return;
        var t = Format.Duration((DateTime.Now - start).TotalSeconds);
        tray.Text = "SnapLens — ● " + t;
        foreach (var item in tray.ContextMenuStrip!.Items.OfType<ToolStripMenuItem>())
            if (item.Tag is ShortcutAction.record) item.Text = L("Parar gravação") + "  ● " + t;
    }

    // MARK: Captura

    private void CancelCapture() => OverlayForm.CloseAll();

    private async Task StartCapture(bool region, ShotAction? auto)
    {
        // Atalho pressionado de novo com o overlay aberto: cancela em vez de empilhar outro.
        Trace.Log($"startCapture region={region} auto={auto} anyVisible={OverlayForm.AnyVisible} starting={isStartingCapture}");
        if (OverlayForm.AnyVisible) { CancelCapture(); return; }
        if (isStartingCapture) return;
        isStartingCapture = true;
        try
        {
            if (Application.OpenForms.OfType<Form>().Any(f => f.GetType().Name == "ToastForm")) { Toast.Dismiss(); await Task.Delay(120); }
            var screen = Capture.ScreenUnderMouse();
            var sw = Stopwatch.StartNew();
            var image = Capture.ScreenImage(screen);
            Trace.Log($"screenImage: {(image == null ? "null" : $"{image.Width}x{image.Height}")} em {sw.ElapsedMilliseconds}ms");
            if (image == null) { Toast.Show(L("Não foi possível capturar a tela"), Icons.Warning); return; }
            if (region)
            {
                OverlayForm.Present(screen, image, auto, (action, data) => _ = Finish(action, data));
                if (OverlayForm.Current is OverlayForm f)
                {
                    // Saída de emergência: Esc global (não depende de a janela ter o foco do teclado).
                    messages.Register(EscapeHotKeyID, new Shortcut((int)Keys.Escape, 0), () =>
                    {
                        Trace.Log("hotkey Esc global");
                        if (OverlayForm.Current is OverlayForm o) o.HandleEscape(); else OverlayForm.CloseAll();
                    });
                    f.FormClosed += (_, _) => messages.Unregister(EscapeHotKeyID);
                }
            }
            else
            {
                byte[] png;
                using (image) png = Images.ToPng(image);
                await Finish(ShotAction.copy, png);
            }
        }
        finally { isStartingCapture = false; }
    }

    private async Task Finish(ShotAction action, byte[] data)
    {
        Trace.Log($"finish action={action} bytes={data.Length}");
        var item = store.AddImage(data, ItemKind.screenshot);
        switch (action)
        {
            case ShotAction.copy:
                CopyImage(data);
                Toast.Show(L("Screenshot copiado e salvo no histórico"), Icons.Camera);
                break;
            case ShotAction.save:
                var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "SnapLens");
                Directory.CreateDirectory(dir);
                var path = Path.Combine(dir, $"Screenshot {Format.Stamp(DateTime.Now)}.png");
                await File.WriteAllBytesAsync(path, data);
                CopyImage(data);
                Toast.Show(L("Salvo em Imagens/SnapLens e copiado"), Icons.Save);
                break;
            case ShotAction.ocr: await RunOCR(item); break;
            case ShotAction.describe: await RunDescribe(item); break;
            case ShotAction.share: await Share(item); break;
        }
    }

    // MARK: Link público

    public async Task Share(Item item)
    {
        var path = store.PathFor(item);
        if (path == null || !File.Exists(path)) return;
        Toast.Show(L("Enviando para %@…", ShareConfig.Server.Replace("https://", "")), Icons.Link);
        try
        {
            var r = await ShareClient.Upload(await File.ReadAllBytesAsync(path), ShareConfig.Expiry, ShareConfig.Once);
            item.ShareID = r.Id;
            item.ShareURL = r.Url;
            item.ShareExpires = r.ExpiresAt is double e && e > 0 ? DateTimeOffset.FromUnixTimeSeconds((long)e).LocalDateTime : null;
            item.ShareToken = r.DeleteToken;
            item.ShareOnce = r.Once;
            store.Update(item);
            CopyText(r.Url);
            bool once = r.Once ?? false;
            Toast.Show(L("Link copiado · %@", ShareClient.ExpiryText(item.ShareExpires)) + (once ? " · " + L("visualização única") : ""), Icons.Link);
            ShowShareResult(r.Url, item.ShareExpires, r.DeleteToken, once);
        }
        catch (Exception e)
        {
            Trace.Log("share ERRO: " + e.Message);
            Toast.Show(e is AppError ? e.Message : L("Compartilhar: %@", e.Message), Icons.Warning);
        }
    }

    public async Task Revoke(Item item)
    {
        if (item.ShareID is not string id || item.ShareToken is not string token) return;
        try
        {
            await ShareClient.Revoke(id, token);
            item.ShareID = null; item.ShareURL = null; item.ShareExpires = null; item.ShareToken = null; item.ShareOnce = null;
            store.Update(item);
            Toast.Show(L("Link revogado"), Icons.Link);
        }
        catch (Exception e) { Toast.Show(e.Message, Icons.Warning); }
    }

    public async Task RunOCR(Item item)
    {
        var path = store.PathFor(item);
        if (path == null) return;
        Toast.Show(L("Reconhecendo texto…"), Icons.Text);
        string text;
        try { text = (await OCR.Recognize(path)).Trim(); }
        catch (AppError e) { Toast.Show(e.Message, Icons.Warning); return; }
        if (text.Length == 0) { Toast.Show(L("Nenhum texto encontrado"), Icons.Warning); return; }
        CopyText(text);
        store.AddText(text, ItemKind.ocr);
        Toast.Dismiss();
        OcrResultForm.ShowResult(text, t => { CopyText(t); Toast.Show(L("Texto copiado")); });
    }

    public async Task RunDescribe(Item item)
    {
        var path = store.PathFor(item);
        if (path == null) return;
        var provider = Providers.Active;
        Toast.Show(L("Analisando com %@…", provider?.ShortName() ?? "Windows OCR"), Icons.Sparkle);
        try
        {
            var text = provider is Provider p ? await AIClient.Describe(path, p) : await OCR.NativeDescription(path);
            CopyText(text);
            store.AddText(text, ItemKind.ai, provider?.ShortName() ?? L("Nativo"));
            Toast.Show(L("Descrição copiada: %@", text.Length > 80 ? text[..80] : text), Icons.Sparkle);
        }
        catch (Exception e)
        {
            Trace.Log("describe ERRO: " + e.Message);
            Toast.Show(e.Message, Icons.Warning);
        }
    }

    // MARK: Janelas

    private void ShowAbout()
    {
        var text = "SnapLens " + Application.ProductVersion.Split('+')[0] + "\n\n"
                   + L("Captura de tela com anotações, OCR e descrição de imagens com IA, histórico de screenshots e área de transferência.")
                   + "\n\n" + L("Criado por") + "\ncontato@ribeiros.click\n\n© 2026 · " + L("Todos os direitos reservados");
        MessageBox.Show(text, L("Sobre o SnapLens"), MessageBoxButtons.OK, MessageBoxIcon.Information);
    }

    public void ShowSettings()
    {
        if (settings == null || settings.IsDisposed)
        {
            settings = new SettingsForm();
            settings.FormClosed += (_, _) => settings = null;
        }
        Bring(settings);
    }

    private void ShowShareResult(string url, DateTime? expires, string token, bool once)
    {
        shareForm?.Close();
        shareForm = new ShareResultForm(url, expires, token, once);
        shareForm.FormClosed += (_, _) => shareForm = null;
        Bring(shareForm);
    }

    public void ShowLibrary()
    {
        if (library == null || library.IsDisposed)
        {
            library = new LibraryForm(store);
            library.FormClosed += (_, _) => library = null;
        }
        Bring(library);
    }

    private static void Bring(Form f)
    {
        if (!f.Visible) f.Show();
        if (f.WindowState == FormWindowState.Minimized) f.WindowState = FormWindowState.Normal;
        f.Activate();
        OverlayForm.SetForegroundWindow(f.Handle);
    }

    public static void RevealInExplorer(string path) =>
        Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{path}\"") { UseShellExecute = true });

    public static void Open(string pathOrUrl)
    {
        try { Process.Start(new ProcessStartInfo(pathOrUrl) { UseShellExecute = true }); }
        catch (Exception e) { Toast.Show(e.Message, Icons.Warning); }
    }

    private void Quit()
    {
        if (ScreenRecorder.Shared.IsRecording) ScreenRecorder.Shared.Stop();
        OverlayForm.CloseAll();
        tray.Visible = false;
        tray.Dispose();
        messages.Dispose();
        ExitThread();
    }

    // MARK: Área de transferência

    public void CopyImage(byte[] png)
    {
        try
        {
            using var img = Images.Load(png);
            var obj = new DataObject();
            if (img != null) obj.SetImage(img);
            obj.SetData("PNG", false, new MemoryStream(png)); // apps modernos preservam transparência/qualidade
            Clipboard.SetDataObject(obj, true, 5, 100);
        }
        catch (Exception e) { Trace.Log("copyImage: " + e.Message); }
        ownClipboardSeq = GetClipboardSequenceNumber(); // não registrar nossa própria cópia
    }

    public void CopyText(string text)
    {
        try { Clipboard.SetDataObject(new DataObject(DataFormats.UnicodeText, text), true, 5, 100); }
        catch (Exception e) { Trace.Log("copyText: " + e.Message); }
        ownClipboardSeq = GetClipboardSequenceNumber();
    }

    private void PollClipboard()
    {
        var seq = GetClipboardSequenceNumber();
        if (seq == ownClipboardSeq) return;
        ownClipboardSeq = seq;
        try
        {
            var data = Clipboard.GetDataObject();
            if (data == null) return;
            var formats = data.GetFormats(false);
            // Ignora conteúdo que o app de origem marcou como privado (gerenciadores de senha).
            if (formats.Contains("ExcludeClipboardContentFromMonitorProcessing") || formats.Contains("Clipboard Viewer Ignore")) return;
            if (formats.Contains("CanIncludeInClipboardHistory") && data.GetData("CanIncludeInClipboardHistory") is MemoryStream ms
                && ms.Length >= 4 && BitConverter.ToInt32(ms.ToArray(), 0) == 0) return;

            if (data.GetData(DataFormats.UnicodeText) is string text && text.Trim().Length > 0)
            {
                var last = store.Items.FirstOrDefault(i => i.Kind is ItemKind.clipboardText or ItemKind.ocr);
                if (last?.Text != text) store.AddText(text, ItemKind.clipboardText);
            }
            else if (data.GetData("PNG") is MemoryStream png && png.Length > 0)
            {
                store.AddImage(png.ToArray(), ItemKind.clipboardImage);
            }
            else if (Clipboard.ContainsImage() && Clipboard.GetImage() is Image img)
            {
                using (img) store.AddImage(Images.ToPng(img), ItemKind.clipboardImage);
            }
        }
        catch (Exception e) { Trace.Log("clipboard: " + e.Message); }
    }

    [DllImport("user32.dll")] private static extern uint GetClipboardSequenceNumber();
}
