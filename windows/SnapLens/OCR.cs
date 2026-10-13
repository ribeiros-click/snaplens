using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage;
using static SnapLens.Loc;

namespace SnapLens;

/// OCR com Windows.Media.Ocr (motor nativo do Windows, roda 100% no dispositivo).
public static class OCR
{
    public static async Task<string> Recognize(string path)
    {
        try
        {
            var engine = OcrEngine.TryCreateFromUserProfileLanguages()
                         ?? OcrEngine.AvailableRecognizerLanguages.Select(OcrEngine.TryCreateFromLanguage).FirstOrDefault(e => e != null);
            if (engine == null)
            {
                Trace.Log("OCR: nenhum idioma de OCR instalado");
                throw new AppError(L("Nenhum idioma de OCR instalado no Windows. Adicione um idioma em Configurações › Hora e idioma."));
            }
            using var bitmap = await LoadBitmap(path, (int)OcrEngine.MaxImageDimension);
            var result = await engine.RecognizeAsync(bitmap);
            var cjk = engine.RecognizerLanguage.LanguageTag.StartsWith("zh") || engine.RecognizerLanguage.LanguageTag.StartsWith("ja")
                      || engine.RecognizerLanguage.LanguageTag.StartsWith("ko");
            // Em chinês/japonês o motor separa cada ideograma com espaço: junta as palavras sem espaço.
            return string.Join("\n", result.Lines.Select(l => cjk ? string.Concat(l.Words.Select(w => w.Text)) : l.Text));
        }
        catch (AppError) { throw; }
        catch (Exception e)
        {
            Trace.Log("OCR erro: " + e);
            return "";
        }
    }

    private static async Task<SoftwareBitmap> LoadBitmap(string path, int maxDimension)
    {
        var file = await StorageFile.GetFileFromPathAsync(path);
        using var stream = await file.OpenAsync(FileAccessMode.Read);
        var decoder = await BitmapDecoder.CreateAsync(stream);
        uint w = decoder.PixelWidth, h = decoder.PixelHeight;
        var transform = new BitmapTransform();
        double scale = 1;
        if (Math.Max(w, h) > maxDimension) scale = (double)maxDimension / Math.Max(w, h);
        // Textos pequenos (capturas de UI) reconhecem melhor ampliados.
        else if (Math.Max(w, h) < 1200) scale = Math.Min(2.0, (double)maxDimension / Math.Max(w, h));
        if (scale != 1)
        {
            transform.ScaledWidth = (uint)Math.Max(1, w * scale);
            transform.ScaledHeight = (uint)Math.Max(1, h * scale);
            transform.InterpolationMode = BitmapInterpolationMode.Fant;
        }
        return await decoder.GetSoftwareBitmapAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied, transform,
                                                    ExifOrientationMode.RespectExifOrientation, ColorManagementMode.DoNotColorManage);
    }

    /// Descrição sem provedor externo: texto reconhecido + dados básicos da imagem.
    public static async Task<string> NativeDescription(string path)
    {
        string text;
        try { text = (await Recognize(path)).Trim(); } catch (AppError) { text = ""; }
        var out_ = L("Descrição nativa (sem IA externa — configure um provedor em Ajustes para descrições completas)");
        using (var img = Images.Load(path))
            if (img != null) out_ += "\n" + L("Imagem de %@ × %@ pixels.", img.Width, img.Height);
        if (text.Length > 0) out_ += "\n\n" + L("Texto na imagem:") + "\n" + text;
        return out_;
    }
}
