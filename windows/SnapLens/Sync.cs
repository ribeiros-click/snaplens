using System.Globalization;
using System.Text;
using static SnapLens.Loc;

namespace SnapLens;

/// Regras da sincronização, sem rede nem tela (testadas em SnapLens.Tests).
public static class SyncPlan
{
    public sealed record Options(bool Images = true, bool Videos = false, bool Texts = true);

    /// Itens criados aqui, dentro da janela de dias e ainda não enviados.
    public static List<Item> ToUpload(IEnumerable<Item> items, DateTime cutoff, Options o) =>
        items.Where(i => i.Date >= cutoff && i.SyncId == null && i.Device == null &&
                         (i.Kind.IsImage() ? o.Images && i.File != null
                          : i.Kind == ItemKind.video ? o.Videos && i.File != null
                          : o.Texts && !string.IsNullOrEmpty(i.Text)))
             .OrderBy(i => i.Date).ToList();

    public static string Iso(DateTime d) => d.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture);

    /// Metadados guardados em appProperties (cada chave+valor ≤ 124 bytes no Drive).
    public static Dictionary<string, string> Props(Item item, string deviceId, string deviceName)
    {
        var p = new Dictionary<string, string>
        {
            ["id"] = item.Id.ToString().ToUpperInvariant(),
            ["kind"] = item.Kind.ToString(),
            ["date"] = Iso(item.Date),
            ["device"] = deviceId,
            ["deviceName"] = deviceName.Length > 60 ? deviceName[..60] : deviceName,
        };
        if (!string.IsNullOrEmpty(item.Source)) p["source"] = item.Source.Length > 60 ? item.Source[..60] : item.Source;
        if (item.Duration is double d) p["duration"] = d.ToString("0.0", CultureInfo.InvariantCulture);
        return p;
    }

    /// Item local reconstruído a partir de um arquivo remoto; null se já existe, é deste aparelho ou está fora da janela.
    public static Item? Incoming(Dictionary<string, string> props, string fileId, ISet<Guid> localIds, string deviceId, DateTime cutoff)
    {
        if (!props.TryGetValue("id", out var raw) || !Guid.TryParse(raw, out var id) || localIds.Contains(id)) return null;
        if (props.GetValueOrDefault("device") == deviceId) return null;
        if (!Enum.TryParse<ItemKind>(props.GetValueOrDefault("kind"), out var kind)) return null;
        if (!DateTime.TryParse(props.GetValueOrDefault("date"), CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal, out var utc)) return null;
        var date = utc.ToLocalTime();
        if (date < cutoff) return null;
        var item = new Item
        {
            Id = id, Date = date, Kind = kind,
            Source = props.GetValueOrDefault("source"),
            Duration = double.TryParse(props.GetValueOrDefault("duration"), NumberStyles.Float, CultureInfo.InvariantCulture, out var dur) ? dur : null,
            Device = props.GetValueOrDefault("deviceName") ?? "?",
            SyncId = fileId,
        };
        if (kind.IsImage()) item.File = id.ToString().ToUpperInvariant() + ".png";
        if (kind == ItemKind.video) item.File = id.ToString().ToUpperInvariant() + ".mp4";
        return item;
    }
}

/// Sincroniza a Biblioteca dos últimos X dias entre os computadores conectados ao mesmo Google Drive.
/// Mão dupla: envia o que foi criado aqui e traz o que os outros enviaram. Apagar não se propaga.
/// Roda na thread da interface (o Store não é thread-safe).
public static class LibrarySync
{
    public static string Status { get; private set; } = "";
    public static bool Running { get; private set; }
    public static event Action? StatusChanged;

    private static bool rerun;
    private static SynchronizationContext? ui;
    private static readonly System.Windows.Forms.Timer Poll = new() { Interval = 5 * 60 * 1000 };

    public static int Days => Math.Clamp(Settings.Data.SyncDays <= 0 ? 7 : Settings.Data.SyncDays, 1, 90);
    public static SyncPlan.Options Options => new(Settings.Data.SyncImages, Settings.Data.SyncVideos, Settings.Data.SyncTexts);
    public static bool IsAvailable => Settings.Data.SyncEnabled && Cloud.Visible.Contains(CloudDrive.GDrive) && CloudDrive.GDrive.IsConnected();

    /// Identificador fixo deste computador (não muda se o nome mudar).
    public static string DeviceId
    {
        get
        {
            if (Settings.Data.SyncDeviceId.Length == 0) { Settings.Data.SyncDeviceId = Guid.NewGuid().ToString().ToUpperInvariant(); Settings.Save(); }
            return Settings.Data.SyncDeviceId;
        }
    }

    public static string DeviceName => Settings.Data.SyncDeviceName.Length > 0 ? Settings.Data.SyncDeviceName : Environment.MachineName;

    public static void Start()
    {
        ui = SynchronizationContext.Current;
        // Vídeos podem ser adicionados fora da thread da interface (fim da gravação).
        Store.Shared.Inserted += _ => Post(Run);
        Poll.Tick += (_, _) => Run();
        Poll.Start();
        var first = new System.Windows.Forms.Timer { Interval = 8000 };
        first.Tick += (_, _) => { first.Stop(); first.Dispose(); Run(); };
        first.Start();
    }

    private static void Post(Action a)
    {
        if (ui != null) ui.Post(_ => a(), null); else a();
    }

    public static async void Run()
    {
        if (!IsAvailable) { SetStatus(""); return; }
        if (Running) { rerun = true; return; }
        Running = true;
        try
        {
            do { rerun = false; await Cycle(); } while (rerun && IsAvailable);
        }
        finally
        {
            Running = false;
            StatusChanged?.Invoke();
        }
    }

    private static async Task Cycle()
    {
        var cutoff = DateTime.Now.AddDays(-Days);
        var device = DeviceId;
        try
        {
            // 1. Envia o que foi criado aqui.
            var up = SyncPlan.ToUpload(Store.Shared.Items, cutoff, Options);
            for (int n = 0; n < up.Count; n++)
            {
                SetStatus(L("Enviando %@ de %@…", n + 1, up.Count));
                var item = up[n];
                var payload = Payload(item);
                if (payload == null) continue;
                var (open, length, name, mime) = payload.Value;
                var id = await Cloud.SyncUpload(open, length, name, mime, SyncPlan.Props(item, device, DeviceName));
                if (Store.Shared.Find(item.Id) is not Item current) continue;
                current.SyncId = id;
                Store.Shared.Update(current);
            }
            // 2. Traz o que veio dos outros.
            var remote = await Cloud.SyncList(after: cutoff);
            var local = Store.Shared.Items.Select(i => i.Id).ToHashSet();
            var o = Options;
            var incoming = remote
                .Select(f => SyncPlan.Incoming(f.Props, f.Id, local, device, cutoff))
                .OfType<Item>()
                .Where(i => (o.Images || !i.Kind.IsImage()) && (o.Videos || i.Kind != ItemKind.video) && (o.Texts || !i.Kind.IsText()))
                .ToList();
            for (int n = 0; n < incoming.Count; n++)
            {
                SetStatus(L("Recebendo %@ de %@…", n + 1, incoming.Count));
                var item = incoming[n];
                var data = await Cloud.Download(CloudDrive.GDrive, item.SyncId!);
                if (item.Kind.IsText())
                {
                    item.Text = Encoding.UTF8.GetString(data);
                    Store.Shared.ImportSynced(item, null);
                }
                else Store.Shared.ImportSynced(item, data);
            }
            // 3. Apaga da pasta de sincronização o que este computador enviou e já saiu da janela.
            foreach (var old in await Cloud.SyncList(before: cutoff, device: device))
            {
                try { await Cloud.Delete(CloudDrive.GDrive, old.Id); } catch (Exception e) { Trace.Log("sync: não apagou antigo: " + e.Message); }
            }
            SetStatus(L("Sincronizado às %@", DateTime.Now.ToString("t", L10n.Culture)));
        }
        catch (Exception e)
        {
            Trace.Log("sync ERRO: " + e.Message);
            SetStatus(L("Sincronização pausada: %@", e.Message));
        }
    }

    private static (Func<Stream> Open, long Length, string Name, string Mime)? Payload(Item item)
    {
        var name = item.Id.ToString().ToUpperInvariant();
        if (item.Kind.IsText())
        {
            if (string.IsNullOrEmpty(item.Text)) return null;
            var bytes = Encoding.UTF8.GetBytes(item.Text);
            Func<Stream> text = () => new MemoryStream(bytes, writable: false);
            return (text, bytes.Length, name + ".txt", "text/plain; charset=utf-8");
        }
        var path = Store.Shared.PathFor(item);
        if (path == null || !File.Exists(path)) return null;
        Func<Stream> open = () => new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 16, useAsync: true);
        var length = new FileInfo(path).Length;
        return item.Kind == ItemKind.video ? (open, length, name + ".mp4", "video/mp4") : (open, length, name + ".png", "image/png");
    }

    private static void SetStatus(string s)
    {
        Status = s;
        StatusChanged?.Invoke();
    }
}
