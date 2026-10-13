using System.Drawing.Imaging;
using static SnapLens.Loc;

namespace SnapLens;

/// Exportação de itens da biblioteca (imagem, vídeo, texto) para arquivos.
public static class Exporter
{
    public static void Export(Item item, Store store)
    {
        string name, filter;
        switch (item.Kind)
        {
            case ItemKind.video:
                name = L("Gravação") + $" {Format.Stamp(item.Date)}.mp4";
                filter = "MP4 (*.mp4)|*.mp4";
                break;
            case ItemKind.screenshot or ItemKind.clipboardImage:
                name = $"Screenshot {Format.Stamp(item.Date)}.png";
                filter = "PNG (*.png)|*.png|JPEG (*.jpg)|*.jpg;*.jpeg|BMP (*.bmp)|*.bmp|TIFF (*.tif)|*.tif;*.tiff";
                break;
            default:
                name = L("Texto") + $" {Format.Stamp(item.Date)}.txt";
                filter = L("Texto") + " (*.txt)|*.txt";
                break;
        }
        var dest = Ui.SaveDialog(name, filter);
        if (dest.Length == 0) return;
        try
        {
            Write(item, dest, store);
            Toast.Show(L("Exportado: %@", Path.GetFileName(dest)), Icons.Export);
        }
        catch (Exception e) { Toast.Show(L("Falha ao exportar: %@", e.Message), Icons.Warning); }
    }

    private static void Write(Item item, string dest, Store store)
    {
        if (item.Kind.IsText())
        {
            File.WriteAllText(dest, (item.Text ?? "").Replace("\n", "\r\n"));
            return;
        }
        var src = store.PathFor(item);
        if (src == null) return;
        var ext = Path.GetExtension(dest).ToLowerInvariant();
        if (item.Kind.IsImage() && ext is ".jpg" or ".jpeg" or ".bmp" or ".tif" or ".tiff")
        {
            using var img = Images.Load(src) ?? throw new AppError(L("Não consegui ler a imagem."));
            if (ext is ".jpg" or ".jpeg")
            {
                // JPEG não tem transparência: achata sobre branco, qualidade 92.
                using var flat = new Bitmap(img.Width, img.Height, PixelFormat.Format24bppRgb);
                using (var g = Graphics.FromImage(flat)) { g.Clear(Color.White); g.DrawImage(img, 0, 0, img.Width, img.Height); }
                var codec = ImageCodecInfo.GetImageEncoders().First(c => c.FormatID == ImageFormat.Jpeg.Guid);
                using var ps = new EncoderParameters(1);
                ps.Param[0] = new EncoderParameter(Encoder.Quality, 92L);
                flat.Save(dest, codec, ps);
            }
            else img.Save(dest, ext == ".bmp" ? ImageFormat.Bmp : ImageFormat.Tiff);
        }
        else File.Copy(src, dest, true);
    }

    /// Exporta toda a biblioteca para uma pasta: Screenshots\, Vídeos\ e Textos.txt.
    public static void ExportAll(Store store)
    {
        using var d = new FolderBrowserDialog { Description = L("Escolha onde salvar a exportação da biblioteca"), UseDescriptionForTitle = true, ShowNewFolderButton = true };
        if (d.ShowDialog() != DialogResult.OK) return;
        var root = Path.Combine(d.SelectedPath, $"SnapLens Export {Format.Stamp(DateTime.Now)}");
        var shots = Path.Combine(root, "Screenshots");
        var vids = Path.Combine(root, L("Vídeos"));
        try
        {
            Directory.CreateDirectory(root);
            int count = 0;
            var texts = new System.Text.StringBuilder();
            foreach (var item in Enumerable.Reverse(store.Items))
            {
                if (item.Kind == ItemKind.video)
                {
                    Directory.CreateDirectory(vids);
                    Write(item, Unique(Path.Combine(vids, L("Gravação") + $" {Format.Stamp(item.Date)}.mp4")), store);
                    count++;
                }
                else if (item.Kind.IsImage())
                {
                    Directory.CreateDirectory(shots);
                    var kind = item.Kind == ItemKind.screenshot ? "Screenshot" : "Clipboard";
                    Write(item, Unique(Path.Combine(shots, $"{kind} {Format.Stamp(item.Date)}.png")), store);
                    count++;
                }
                else if (item.Text is string t)
                {
                    var label = item.Kind == ItemKind.ocr ? "OCR" : item.Kind == ItemKind.ai ? L("IA") : "Clipboard";
                    texts.Append($"[{Format.Stamp(item.Date)} · {label}]\r\n{t.Replace("\n", "\r\n")}\r\n\r\n----------------------------------------\r\n\r\n");
                    count++;
                }
            }
            if (texts.Length > 0) File.WriteAllText(Path.Combine(root, L("Textos") + ".txt"), texts.ToString());
            Toast.Show(L("%@ itens exportados", count), Icons.Export);
            TrayApp.RevealInExplorer(root);
        }
        catch (Exception e) { Toast.Show(L("Falha ao exportar: %@", e.Message), Icons.Warning); }
    }

    /// Dois itens no mesmo segundo não podem sobrescrever um ao outro.
    private static string Unique(string path)
    {
        if (!File.Exists(path)) return path;
        var dir = Path.GetDirectoryName(path)!;
        var name = Path.GetFileNameWithoutExtension(path);
        var ext = Path.GetExtension(path);
        for (int i = 2; ; i++)
        {
            var p = Path.Combine(dir, $"{name} ({i}){ext}");
            if (!File.Exists(p)) return p;
        }
    }
}
