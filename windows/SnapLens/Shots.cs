namespace SnapLens;

/// Renderiza as janelas reais em PNG (`--render-ui <pasta> [idioma]`), para conferir a UI e gerar prints.
/// Usa uma biblioteca temporária com itens de exemplo; não toca na biblioteca do usuário.
public static class Shots
{
    public static void Render(string dir, string? language)
    {
        Directory.CreateDirectory(dir);
        if (language != null) Settings.Data.Language = language;
        SynchronizationContext.SetSynchronizationContext(new WindowsFormsSynchronizationContext());

        var temp = Path.Combine(Path.GetTempPath(), "SnapLens-shots-" + Guid.NewGuid().ToString("N"));
        var store = new Store(temp);
        using (var sample = Sample(720, 420)) store.AddImage(Images.ToPng(sample), ItemKind.screenshot);
        using (var sample = Sample(520, 300)) store.AddImage(Images.ToPng(sample), ItemKind.clipboardImage);
        var shared = store.Items[0];
        shared.ShareURL = "https://lens.ribeiros.click/s/a1B2c3"; shared.ShareExpires = DateTime.Now.AddDays(7); shared.ShareToken = "x";
        store.Update(shared);
        store.AddText("Relatório de vendas — 3º trimestre\nRegião Sul: R$ 182.400 (+12%)", ItemKind.ocr);
        store.AddText("A imagem mostra uma tabela de vendas por região…", ItemKind.ai, "Claude");

        Save(new SettingsForm(), Path.Combine(dir, "settings.png"));
        var lib = new LibraryForm(store);
        Save(lib, Path.Combine(dir, "library.png"));
        Save(new ShareResultForm("https://lens.ribeiros.click/s/a1B2c3", DateTime.Now.AddDays(7), "tok_9f8e7d6c5b4a", once: true), Path.Combine(dir, "share.png"));
        try { Directory.Delete(temp, true); } catch { }
    }

    private static void Save(Form f, string path)
    {
        f.StartPosition = FormStartPosition.Manual;
        f.Location = new Point(-10000, -10000);
        f.ShowInTaskbar = false;
        f.Show();
        for (int k = 0; k < 30; k++) { Application.DoEvents(); Thread.Sleep(20); }
        using var bmp = new Bitmap(f.Width, f.Height);
        f.DrawToBitmap(bmp, new Rectangle(Point.Empty, f.Size));
        bmp.Save(path);
        f.Close();
    }

    private static Bitmap Sample(int w, int h)
    {
        var bmp = new Bitmap(w, h);
        using var g = Graphics.FromImage(bmp);
        g.Clear(Color.FromArgb(245, 243, 238));
        using var font = new Font("Segoe UI", 22, FontStyle.Bold);
        g.DrawString("SnapLens", font, Brushes.DarkOliveGreen, 30, 30);
        using var body = new Font("Segoe UI", 14);
        g.DrawString("Região Sul: R$ 182.400 (+12%)\nRegião Sudeste: R$ 401.950 (+8%)", body, Brushes.Black, 30, 110);
        return bmp;
    }
}
