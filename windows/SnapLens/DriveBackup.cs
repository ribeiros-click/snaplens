using System.Text;
using static SnapLens.Loc;

namespace SnapLens;

/// Backup automático da Biblioteca para o Google Drive (ou OneDrive, oculto por enquanto): mão única (PC → Drive).
/// Cada item novo vai para a pasta escolhida; "Enviar a Biblioteca agora" manda também os antigos.
/// Apagar na Biblioteca não apaga no Drive. Roda na thread da interface (o Store não é thread-safe).
public static class DriveBackup
{
    public static string Status { get; private set; } = "";
    public static bool Running { get; private set; }
    public static event Action? StatusChanged;

    private static bool rerun;
    private static SynchronizationContext? ui;
    private static readonly System.Windows.Forms.Timer RetryTimer = new() { Interval = 15 * 60 * 1000 };

    /// Drive de destino; null = backup desligado (ou Drive desconectado/oculto).
    public static CloudDrive? Drive
    {
        get
        {
            var d = Settings.Data.BackupDrive switch { "gdrive" => CloudDrive.GDrive, "onedrive" => CloudDrive.OneDrive, _ => (CloudDrive?)null };
            return d is CloudDrive c && Cloud.Visible.Contains(c) && c.IsConnected() ? c : null;
        }
        set
        {
            Settings.Data.BackupDrive = value?.Key() ?? "";
            // Ao ligar, só o que for capturado daqui em diante entra sozinho; o resto, pelo botão.
            if (value != null && Settings.Data.BackupSince == null) Settings.Data.BackupSince = DateTime.Now;
            Settings.Save();
        }
    }

    public static void Start()
    {
        ui = SynchronizationContext.Current;
        // Vídeos podem ser adicionados fora da thread da interface (fim da gravação).
        Store.Shared.Inserted += _ => Post(() => Run());
        RetryTimer.Tick += (_, _) => Run();
        RetryTimer.Start();
        Post(async () => { await Task.Delay(5000); Run(); });
    }

    private static void Post(Action a)
    {
        if (ui != null) ui.Post(_ => a(), null); else a();
    }

    /// Envia os itens pendentes. `all`: inclui os anteriores à ativação do backup.
    public static async void Run(bool all = false)
    {
        if (Drive is not CloudDrive drive) { SetStatus(""); return; }
        if (all) { Settings.Data.BackupSince = DateTime.MinValue; Settings.Save(); }
        if (Running) { rerun = true; return; }
        Running = true;
        try
        {
            do
            {
                rerun = false;
                await Process(drive);
            } while (rerun && Drive == drive);
        }
        finally
        {
            Running = false;
            StatusChanged?.Invoke();
        }
    }

    private static List<Item> Pending(CloudDrive drive)
    {
        var since = Settings.Data.BackupSince ?? DateTime.Now;
        var key = drive.Key();
        return Store.Shared.Items.Where(i =>
                i.Date >= since && (i.Backups == null || !i.Backups.ContainsKey(key)) && i.Device == null &&
                (i.Kind.IsImage() ? Settings.Data.BackupImages
                    : i.Kind == ItemKind.video ? Settings.Data.BackupVideos
                    : Settings.Data.BackupTexts && !string.IsNullOrEmpty(i.Text)))
            .Reverse() // mais antigos primeiro
            .ToList();
    }

    private static async Task Process(CloudDrive drive)
    {
        var items = Pending(drive);
        if (items.Count == 0) { SetStatus(L("Backup em dia")); return; }
        for (int n = 0; n < items.Count; n++)
        {
            if (Drive != drive) return;
            var item = items[n];
            SetStatus(L("Enviando %@ de %@…", n + 1, items.Count));
            try
            {
                var payload = Payload(item);
                if (payload == null) continue;
                var (open, length, name, mime) = payload.Value;
                var r = await Cloud.UploadFile(drive, open, length, name, mime);
                // O item pode ter sido apagado enquanto o envio rodava.
                if (Store.Shared.Find(item.Id) is not Item current) continue;
                current.Backups ??= new();
                current.Backups[drive.Key()] = r.Id;
                Store.Shared.Update(current);
            }
            catch (Exception e)
            {
                Trace.Log($"backup {drive.Key()} ERRO: {e.Message}");
                SetStatus(L("Backup pausado: %@", e.Message));
                return; // tenta de novo no próximo item novo ou em 15 minutos
            }
        }
        SetStatus(L("Backup em dia"));
    }

    private static (Func<Stream> Open, long Length, string Name, string Mime)? Payload(Item item)
    {
        var stamp = "SnapLens " + item.Date.ToString("yyyy-MM-dd HH.mm.ss", System.Globalization.CultureInfo.InvariantCulture);
        if (item.Kind.IsText())
        {
            if (string.IsNullOrEmpty(item.Text)) return null;
            var bytes = Encoding.UTF8.GetBytes(item.Text);
            var label = item.Kind switch { ItemKind.ocr => "OCR", ItemKind.ai => "IA", _ => "Texto" };
            Func<Stream> text = () => new MemoryStream(bytes, writable: false);
            return (text, bytes.Length, $"{stamp} {label}.txt", "text/plain; charset=utf-8");
        }
        var path = Store.Shared.PathFor(item);
        if (path == null || !File.Exists(path)) return null;
        var length = new FileInfo(path).Length;
        Func<Stream> open = () => new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 16, useAsync: true);
        if (item.Kind == ItemKind.video)
        {
            var ext = Path.GetExtension(path);
            return (open, length, stamp + (ext.Length > 0 ? ext : ".mp4"), "video/mp4");
        }
        return (open, length, stamp + ".png", "image/png");
    }

    private static void SetStatus(string s)
    {
        Status = s;
        StatusChanged?.Invoke();
    }
}
