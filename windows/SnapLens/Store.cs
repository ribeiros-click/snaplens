using System.Drawing.Imaging;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace SnapLens;

[JsonConverter(typeof(JsonStringEnumConverter<ItemKind>))]
public enum ItemKind { screenshot, clipboardImage, clipboardText, ocr, ai, video }

public static class ItemKindExt
{
    public static bool IsImage(this ItemKind k) => k is ItemKind.screenshot or ItemKind.clipboardImage;
    public static bool IsText(this ItemKind k) => k is ItemKind.clipboardText or ItemKind.ocr or ItemKind.ai;
}

public sealed class Item
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public DateTime Date { get; set; } = DateTime.Now;
    public ItemKind Kind { get; set; }
    public string? Text { get; set; }
    public string? File { get; set; }
    public string? Source { get; set; }
    public double? Duration { get; set; }
    // Link público (lens.ribeiros.click)
    public string? ShareID { get; set; }
    public string? ShareURL { get; set; }
    public DateTime? ShareExpires { get; set; }
    public string? ShareToken { get; set; }
    public bool? ShareOnce { get; set; }
}

/// Biblioteca: screenshots, vídeos e textos em %APPDATA%\SnapLens (history.json + images\ + videos\).
public sealed class Store
{
    public static Store Shared { get; } = new();
    public const int MaxItems = 500;

    public event Action? Changed;
    public List<Item> Items { get; private set; } = new();

    public string Dir { get; }
    public string ImagesDir { get; }
    public string VideosDir { get; }
    private string IndexPath => Path.Combine(Dir, "history.json");
    private static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull };

    public Store(string? customDir = null)
    {
        Dir = customDir ?? Settings.Dir;
        ImagesDir = Path.Combine(Dir, "images");
        VideosDir = Path.Combine(Dir, "videos");
        Directory.CreateDirectory(ImagesDir);
        Directory.CreateDirectory(VideosDir);
        try
        {
            if (System.IO.File.Exists(IndexPath))
                Items = JsonSerializer.Deserialize<List<Item>>(System.IO.File.ReadAllText(IndexPath), Json) ?? new();
        }
        catch (Exception e) { Trace.Log("store: índice ilegível: " + e.Message); }
    }

    public string? PathFor(Item item) =>
        item.File == null ? null : Path.Combine(item.Kind == ItemKind.video ? VideosDir : ImagesDir, item.File);

    public Item AddImage(byte[] png, ItemKind kind, string? text = null)
    {
        var name = Guid.NewGuid().ToString().ToUpperInvariant() + ".png";
        System.IO.File.WriteAllBytes(Path.Combine(ImagesDir, name), png);
        return Insert(new Item { Kind = kind, Text = text, File = name });
    }

    public Item AddText(string text, ItemKind kind, string? source = null) =>
        Insert(new Item { Kind = kind, Text = text, Source = source });

    public Item AddVideo(string file, double duration, string? source) =>
        Insert(new Item { Kind = ItemKind.video, File = file, Source = source, Duration = duration });

    private Item Insert(Item item)
    {
        Items.Insert(0, item);
        // Vídeos ficam fora do limite: só o usuário os apaga.
        while (Items.Count(i => i.Kind != ItemKind.video) > MaxItems)
        {
            var last = Items.Last(i => i.Kind != ItemKind.video);
            DeleteFile(last);
            Items.Remove(last);
        }
        Save();
        return item;
    }

    public Item? Find(Guid id) => Items.FirstOrDefault(i => i.Id == id);

    public void Update(Item item)
    {
        int i = Items.FindIndex(x => x.Id == item.Id);
        if (i < 0) return;
        Items[i] = item;
        Save();
    }

    public void Remove(Item item)
    {
        DeleteFile(item);
        Items.RemoveAll(i => i.Id == item.Id);
        Save();
    }

    public void Clear(Func<ItemKind, bool> match)
    {
        foreach (var item in Items.Where(i => match(i.Kind))) DeleteFile(item);
        Items.RemoveAll(i => match(i.Kind));
        Save();
    }

    private void DeleteFile(Item item)
    {
        var p = PathFor(item);
        if (p == null) return;
        try { System.IO.File.Delete(p); } catch (Exception e) { Trace.Log("store: não apagou " + p + ": " + e.Message); }
    }

    private void Save()
    {
        try
        {
            var tmp = IndexPath + ".tmp";
            System.IO.File.WriteAllText(tmp, JsonSerializer.Serialize(Items, Json));
            System.IO.File.Move(tmp, IndexPath, true);
        }
        catch (Exception e) { Trace.Log("store: falha ao salvar: " + e.Message); }
        Changed?.Invoke();
    }
}

public static class Images
{
    public static byte[] ToPng(Image img)
    {
        using var ms = new MemoryStream();
        img.Save(ms, ImageFormat.Png);
        return ms.ToArray();
    }

    /// Carrega sem manter o arquivo bloqueado (o GDI+ trava o arquivo enquanto a imagem vive).
    public static Bitmap? Load(string path)
    {
        try
        {
            using var ms = new MemoryStream(System.IO.File.ReadAllBytes(path));
            using var img = Image.FromStream(ms);
            return new Bitmap(img);
        }
        catch { return null; }
    }

    public static Bitmap? Load(byte[] data)
    {
        try
        {
            using var ms = new MemoryStream(data);
            using var img = Image.FromStream(ms);
            return new Bitmap(img);
        }
        catch { return null; }
    }

    public static Bitmap Thumbnail(Image src, int maxSize)
    {
        double scale = Math.Min(1.0, (double)maxSize / Math.Max(src.Width, src.Height));
        int w = Math.Max(1, (int)Math.Round(src.Width * scale)), h = Math.Max(1, (int)Math.Round(src.Height * scale));
        var bmp = new Bitmap(w, h);
        using var g = Graphics.FromImage(bmp);
        g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
        g.DrawImage(src, 0, 0, w, h);
        return bmp;
    }

    public static Bitmap? LoadThumbnail(string path, int maxSize = 480)
    {
        using var img = Load(path);
        return img == null ? null : Thumbnail(img, maxSize);
    }
}

public static class Format
{
    public static string Duration(double t)
    {
        int s = (int)Math.Round(t);
        return s >= 3600 ? $"{s / 3600}:{s % 3600 / 60:00}:{s % 60:00}" : $"{s / 60}:{s % 60:00}";
    }

    public static string Stamp(DateTime d) => d.ToString("yyyy-MM-dd HH.mm.ss");
    public static string Time(DateTime d) => d.ToString("t", L10n.Culture);
    public static string DateTimeShort(DateTime d) => d.ToString("g", L10n.Culture);
}
