using System.Drawing.Drawing2D;
using Windows.Storage;
using Windows.Storage.FileProperties;
using static SnapLens.Loc;

namespace SnapLens;

/// Biblioteca: screenshots, gravações e textos (OCR, IA, área de transferência).
public sealed class LibraryForm : Form
{
    private enum Tab { images, videos, texts }

    private readonly Store store;
    private Tab tab = Tab.images;
    private readonly List<Guid> selected = new(); // ordem de seleção = ordem na montagem
    private readonly Dictionary<Guid, Control> cards = new();
    private readonly FlowLayoutPanel content;
    private readonly FlowLayoutPanel selectionBar;
    private readonly Label selectionLabel;
    private readonly TextBox search;
    private readonly Label empty;
    private readonly ToolTip tips = new();
    private readonly System.Windows.Forms.Timer debounce = new() { Interval = 80 };
    private static readonly Dictionary<string, Bitmap> ThumbCache = new();

    public LibraryForm(Store store)
    {
        this.store = store;
        Ui.Window(this, L("Biblioteca"), 980, 640);
        MinimumSize = new Size(680, 420);
        BackColor = Color.FromArgb(243, 243, 245);

        var top = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 48, Padding = new Padding(10, 9, 10, 6), WrapContents = false, BackColor = Color.White };
        foreach (var t in Enum.GetValues<Tab>())
        {
            var tt = t;
            var rb = new RadioButton
            {
                Text = t switch { Tab.images => L("Imagens"), Tab.videos => L("Vídeos"), _ => L("Texto") },
                Appearance = Appearance.Button, AutoSize = false, Size = new Size(96, 28), TextAlign = ContentAlignment.MiddleCenter,
                Checked = t == tab, FlatStyle = FlatStyle.Flat, Margin = new Padding(0), Cursor = Cursors.Hand,
            };
            rb.FlatAppearance.CheckedBackColor = Color.FromArgb(0, 103, 192);
            rb.FlatAppearance.BorderColor = Color.FromArgb(200, 200, 205);
            rb.CheckedChanged += (_, _) =>
            {
                rb.ForeColor = rb.Checked ? Color.White : SystemColors.ControlText;
                if (rb.Checked) { tab = tt; Rebuild(); }
            };
            rb.ForeColor = rb.Checked ? Color.White : SystemColors.ControlText;
            top.Controls.Add(rb);
        }
        search = new TextBox { Width = 220, PlaceholderText = L("Buscar…"), Margin = new Padding(14, 3, 0, 0), Visible = false };
        search.TextChanged += (_, _) => Rebuild();
        top.Controls.Add(search);

        selectionBar = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Margin = new Padding(14, 0, 0, 0), Visible = false };
        selectionLabel = Ui.Label("", Ui.Body, Ui.Secondary);
        selectionLabel.Margin = new Padding(0, 6, 8, 0);
        selectionBar.Controls.Add(selectionLabel);
        selectionBar.Controls.Add(Ui.Button(L("Copiar juntas"), () => Combine(copy: true)));
        selectionBar.Controls.Add(Ui.Button(L("Baixar juntas"), () => Combine(copy: false)));
        selectionBar.Controls.Add(Ui.Button(L("Limpar seleção"), () => { selected.Clear(); Rebuild(); }));
        top.Controls.Add(selectionBar);

        var right = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Padding = new Padding(0, 9, 10, 6), BackColor = Color.White };
        right.Controls.Add(Ui.Button(L("Exportar tudo…"), () => Exporter.ExportAll(store)));
        right.Controls.Add(Ui.Button(L("Limpar"), ClearTab));

        content = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoScroll = true, Padding = new Padding(10), BackColor = BackColor };
        content.Resize += (_, _) => { if (tab == Tab.texts) FitRows(); };
        empty = new Label { Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter, ForeColor = Ui.Secondary, Font = new Font("Segoe UI", 11f), Visible = false };

        var bar = new TableLayoutPanel { Dock = DockStyle.Top, Height = 48, ColumnCount = 2, BackColor = Color.White };
        bar.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        bar.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        top.Dock = DockStyle.Fill;
        right.Dock = DockStyle.Fill;
        bar.Controls.Add(top, 0, 0);
        bar.Controls.Add(right, 1, 0);

        Controls.Add(content);
        Controls.Add(empty);
        Controls.Add(new Label { Dock = DockStyle.Top, Height = 1, BackColor = Color.FromArgb(220, 220, 224) });
        Controls.Add(bar);

        debounce.Tick += (_, _) => { debounce.Stop(); Rebuild(); };
        store.Changed += OnStoreChanged;
        FormClosed += (_, _) => store.Changed -= OnStoreChanged;
        Rebuild();
    }


    private void OnStoreChanged()
    {
        if (IsDisposed) return;
        debounce.Stop();
        debounce.Start();
    }

    private IEnumerable<Item> VisibleItems() => tab switch
    {
        Tab.images => store.Items.Where(i => i.Kind.IsImage()),
        Tab.videos => store.Items.Where(i => i.Kind == ItemKind.video),
        _ => store.Items.Where(i => i.Kind.IsText() && (search.Text.Length == 0 || (i.Text ?? "").Contains(search.Text, StringComparison.CurrentCultureIgnoreCase))),
    };

    private void Rebuild()
    {
        if (IsDisposed) return;
        selected.RemoveAll(id => store.Find(id) == null);
        search.Visible = tab == Tab.texts;
        selectionBar.Visible = tab == Tab.images && selected.Count > 0;
        selectionLabel.Text = L("%@ selecionada(s)", selected.Count);

        var items = VisibleItems().ToList();
        content.SuspendLayout();
        content.Controls.Clear();
        foreach (var id in cards.Keys.ToList())
        {
            cards[id].Dispose();
            cards.Remove(id);
        }
        foreach (var item in items)
        {
            Control c = tab switch
            {
                Tab.images => ImageCard(item),
                Tab.videos => VideoCard(item),
                _ => TextRow(item),
            };
            cards[item.Id] = c;
            content.Controls.Add(c);
        }
        if (tab == Tab.texts) FitRows();
        content.ResumeLayout();

        empty.Visible = items.Count == 0;
        content.Visible = items.Count > 0;
        empty.Text = tab switch
        {
            Tab.images => L("Nenhum screenshot ainda.\nUse %@ para capturar uma seleção.", ShortcutAction.region.Get().Display),
            Tab.videos => L("Nenhuma gravação ainda.\nUse %@ para gravar a tela.", ShortcutAction.record.Get().Display),
            _ => L("Nenhum texto no histórico."),
        };
    }

    private void FitRows()
    {
        int w = content.ClientSize.Width - content.Padding.Horizontal - SystemInformation.VerticalScrollBarWidth - 4;
        foreach (Control c in content.Controls) c.Width = Math.Max(300, w);
    }

    private void Toggle(Item item)
    {
        if (!selected.Remove(item.Id)) selected.Add(item.Id);
        selectionBar.Visible = selected.Count > 0;
        selectionLabel.Text = L("%@ selecionada(s)", selected.Count);
        foreach (var c in cards.Values) c.Invalidate(true);
    }

    /// Junta as imagens selecionadas (ordem de seleção) em um PNG: copia para a área de transferência ou salva.
    private void Combine(bool copy)
    {
        var paths = selected.Select(store.Find).Where(i => i != null).Select(i => store.PathFor(i!)).Where(p => p != null).Cast<string>().ToList();
        var data = Composer.Stack(paths);
        if (data == null) return;
        if (copy)
        {
            TrayApp.Instance.CopyImage(data);
            Toast.Show(L("%@ imagens combinadas e copiadas", paths.Count), Icons.Copy);
            return;
        }
        var dest = Ui.SaveDialog(L("Montagem") + $" {Format.Stamp(DateTime.Now)}.png", Ui.FilterPng);
        if (dest.Length == 0) return;
        try { File.WriteAllBytes(dest, data); Toast.Show(L("Exportado: %@", Path.GetFileName(dest)), Icons.Download); }
        catch (Exception e) { Toast.Show(L("Falha ao exportar: %@", e.Message), Icons.Warning); }
    }

    private void ClearTab()
    {
        var what = tab switch { Tab.images => L("Imagens"), Tab.videos => L("Vídeos"), _ => L("Texto") };
        if (MessageBox.Show(this, L("Apagar todos os itens de “%@” da biblioteca?", what), L("Limpar"),
                MessageBoxButtons.OKCancel, MessageBoxIcon.Warning) != DialogResult.OK) return;
        switch (tab)
        {
            case Tab.images: store.Clear(k => k.IsImage()); break;
            case Tab.videos: store.Clear(k => k == ItemKind.video); break;
            default: store.Clear(k => k.IsText()); break;
        }
    }

    // MARK: Cartões

    private Panel Card(int height)
    {
        var p = new Panel { Size = new Size(300, height), Margin = new Padding(6), BackColor = Color.White, Padding = new Padding(8) };
        p.Paint += (_, e) =>
        {
            using var pen = new Pen(Color.FromArgb(222, 222, 226));
            e.Graphics.DrawRectangle(pen, 0, 0, p.Width - 1, p.Height - 1);
        };
        return p;
    }

    private FlowLayoutPanel ButtonRow(params (string glyph, string tip, Action action)[] buttons)
    {
        var row = new FlowLayoutPanel { Height = 28, Dock = DockStyle.Bottom, WrapContents = false, FlowDirection = FlowDirection.RightToLeft, Margin = Padding.Empty };
        foreach (var b in buttons.Reverse()) row.Controls.Add(Ui.Glyph(b.glyph, b.tip, b.action, tips));
        return row;
    }

    private Control ImageCard(Item item)
    {
        var app = TrayApp.Instance;
        var path = store.PathFor(item);
        bool shared = item.ShareURL != null;
        var card = Card(shared ? 262 : 236);

        var thumb = new PictureBox { Dock = DockStyle.Top, Height = 160, SizeMode = PictureBoxSizeMode.Zoom, BackColor = Color.FromArgb(236, 236, 240), Cursor = Cursors.Hand };
        LoadThumb(thumb, path, video: false);
        thumb.Paint += (_, e) =>
        {
            // Círculo de seleção: clique marca/desmarca; o número mostra a ordem na montagem.
            int idx = selected.IndexOf(item.Id);
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            var r = new Rectangle(7, 7, 22, 22);
            using (var fill = new SolidBrush(idx < 0 ? Color.FromArgb(90, 0, 0, 0) : Ui.Accent)) g.FillEllipse(fill, r);
            using (var ring = new Pen(Color.White, 1.5f)) g.DrawEllipse(ring, r);
            if (idx >= 0)
            {
                TextRenderer.DrawText(g, (idx + 1).ToString(), Ui.Small, r, Color.White, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
                using var border = new Pen(Ui.Accent, 3);
                g.DrawRectangle(border, 1, 1, thumb.Width - 3, thumb.Height - 3);
            }
        };
        tips.SetToolTip(thumb, L("Selecionar para montagem"));
        thumb.MouseClick += (_, e) => { if (e.Button == MouseButtons.Left) Toggle(item); };
        thumb.MouseDoubleClick += (_, _) => { Toggle(item); if (path != null) TrayApp.Open(path); };

        var kind = item.Kind == ItemKind.screenshot ? "Screenshot" : "Clipboard";
        var meta = Ui.Label($"{kind} · {Format.Time(item.Date)}", Ui.Small, Ui.Secondary);
        meta.Dock = DockStyle.Bottom;
        meta.AutoSize = false;
        meta.Height = 20;

        var actions = new List<(string, string, Action)> { (Icons.Copy, L("Copiar imagem"), () => { if (path != null && File.Exists(path)) { app.CopyImage(File.ReadAllBytes(path)); Toast.Show(L("Imagem copiada")); } }) };
        if (!shared) actions.Add((Icons.Link, L("Compartilhar por link público"), () => _ = app.Share(item)));
        actions.Add((Icons.Sparkle, L("Descrever com IA"), () => _ = app.RunDescribe(item)));
        actions.Add((Icons.Text, L("Extrair texto (OCR)"), () => _ = app.RunOCR(item)));
        actions.Add((Icons.Export, L("Exportar…"), () => Exporter.Export(item, store)));
        actions.Add((Icons.Folder, L("Mostrar no Explorer"), () => { if (path != null) TrayApp.RevealInExplorer(path); }));
        actions.Add((Icons.Delete, L("Apagar"), () => store.Remove(item)));

        card.Controls.Add(thumb);
        if (shared) card.Controls.Add(ShareRow(item));
        card.Controls.Add(meta);
        card.Controls.Add(ButtonRow(actions.ToArray()));
        // Ordem de docking: o último adicionado fica por cima; acerta para miniatura no topo.
        thumb.BringToFront();
        return card;
    }

    private Control ShareRow(Item item)
    {
        var app = TrayApp.Instance;
        var link = item.ShareURL!;
        var row = new Panel { Dock = DockStyle.Bottom, Height = 26 };
        var text = link.Replace("https://", "") + " · " + ShareClient.ExpiryText(item.ShareExpires) + (item.ShareOnce == true ? " · 1×" : "");
        var label = new Label { Text = text, AutoEllipsis = true, Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft, Font = Ui.Small, ForeColor = item.ShareOnce == true ? Ui.Orange : Ui.Accent };
        if (item.ShareOnce == true) tips.SetToolTip(label, L("Visualização única — o link se apaga na primeira abertura"));
        var buttons = new FlowLayoutPanel { Dock = DockStyle.Right, Width = 86, WrapContents = false, Margin = Padding.Empty };
        buttons.Controls.Add(Ui.Glyph(Icons.Copy, L("Copiar link"), () => { app.CopyText(link); Toast.Show(L("Texto copiado")); }, tips));
        buttons.Controls.Add(Ui.Glyph(Icons.Globe, L("Abrir no navegador"), () => TrayApp.Open(link), tips));
        var revoke = Ui.Glyph(Icons.Clear, L("Revogar link"), () => _ = app.Revoke(item), tips);
        revoke.ForeColor = Color.Firebrick;
        buttons.Controls.Add(revoke);
        row.Controls.Add(label);
        row.Controls.Add(buttons);
        return row;
    }

    private Control VideoCard(Item item)
    {
        var path = store.PathFor(item);
        var card = Card(236);
        var thumb = new PictureBox { Dock = DockStyle.Top, Height = 160, SizeMode = PictureBoxSizeMode.Zoom, BackColor = Color.FromArgb(30, 30, 32), Cursor = Cursors.Hand };
        LoadThumb(thumb, path, video: true);
        thumb.Paint += (_, e) =>
        {
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            var c = new Rectangle(thumb.Width / 2 - 22, thumb.Height / 2 - 22, 44, 44);
            using (var b = new SolidBrush(Color.FromArgb(200, 255, 255, 255))) g.FillEllipse(b, c);
            using (var tri = new SolidBrush(Color.FromArgb(40, 40, 40)))
                g.FillPolygon(tri, new[] { new Point(c.X + 17, c.Y + 12), new Point(c.X + 17, c.Y + 32), new Point(c.X + 33, c.Y + 22) });
            var dur = Format.Duration(item.Duration ?? 0);
            var size = TextRenderer.MeasureText(dur, Ui.Small);
            var r = new Rectangle(thumb.Width - size.Width - 14, thumb.Height - size.Height - 10, size.Width + 8, size.Height + 4);
            using (var bg = new SolidBrush(Color.FromArgb(170, 0, 0, 0))) g.FillRectangle(bg, r);
            TextRenderer.DrawText(g, dur, Ui.Small, r, Color.White, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
        };
        thumb.Click += (_, _) => { if (path != null) TrayApp.Open(path); };

        var meta = Ui.Label(L("Gravação · %@", Format.DateTimeShort(item.Date)) + "  ·  " + (item.Source ?? ""), Ui.Small, Ui.Secondary);
        meta.Dock = DockStyle.Bottom;
        meta.AutoSize = false;
        meta.AutoEllipsis = true;
        meta.Height = 20;
        card.Controls.Add(thumb);
        card.Controls.Add(meta);
        card.Controls.Add(ButtonRow(
            (Icons.Play, L("Reproduzir"), () => { if (path != null) TrayApp.Open(path); }),
            (Icons.Export, L("Exportar…"), () => Exporter.Export(item, store)),
            (Icons.Folder, L("Mostrar no Explorer"), () => { if (path != null) TrayApp.RevealInExplorer(path); }),
            (Icons.Delete, L("Apagar"), () => store.Remove(item))));
        thumb.BringToFront();
        return card;
    }

    private Control TextRow(Item item)
    {
        var app = TrayApp.Instance;
        var (label, glyph) = item.Kind switch
        {
            ItemKind.ocr => ("OCR", Icons.Text),
            ItemKind.ai => (L("IA · %@", item.Source ?? ""), Icons.Sparkle),
            _ => ("Clipboard", Icons.Clipboard),
        };
        var row = new Panel { Height = 92, Margin = new Padding(4, 3, 4, 3), BackColor = Color.White, Padding = new Padding(8, 6, 8, 6) };
        var icon = new Label { Text = glyph, Font = Icons.Font(15), ForeColor = Ui.Secondary, Dock = DockStyle.Left, Width = 28, TextAlign = ContentAlignment.TopCenter };
        var buttons = new FlowLayoutPanel { Dock = DockStyle.Right, Width = 90, WrapContents = false };
        buttons.Controls.Add(Ui.Glyph(Icons.Copy, L("Copiar"), () => { app.CopyText(item.Text ?? ""); Toast.Show(L("Texto copiado")); }, tips));
        buttons.Controls.Add(Ui.Glyph(Icons.Export, L("Exportar como .txt"), () => Exporter.Export(item, store), tips));
        buttons.Controls.Add(Ui.Glyph(Icons.Delete, L("Apagar"), () => store.Remove(item), tips));
        var meta = new Label { Text = $"{label} · {Format.DateTimeShort(item.Date)}", Dock = DockStyle.Bottom, Height = 18, Font = Ui.Small, ForeColor = Ui.Secondary };
        var text = new Label { Text = (item.Text ?? "").Replace("\r\n", "\n").Replace("\n", "\r\n"), Dock = DockStyle.Fill, AutoEllipsis = true, Font = Ui.Body, Cursor = Cursors.Hand };
        bool expanded = false;
        text.Click += (_, _) =>
        {
            // Clique expande/recolhe o texto inteiro.
            expanded = !expanded;
            if (expanded)
            {
                var size = TextRenderer.MeasureText(text.Text, text.Font, new Size(text.Width, 0), TextFormatFlags.WordBreak);
                row.Height = Math.Max(92, size.Height + 40);
            }
            else row.Height = 92;
        };
        tips.SetToolTip(text, item.Text is { Length: > 300 } t ? t[..300] + "…" : item.Text);
        row.Controls.Add(text);
        row.Controls.Add(meta);
        row.Controls.Add(buttons);
        row.Controls.Add(icon);
        text.BringToFront();
        return row;
    }

    // MARK: Miniaturas

    private void LoadThumb(PictureBox box, string? path, bool video)
    {
        if (path == null || !File.Exists(path)) return;
        lock (ThumbCache)
            if (ThumbCache.TryGetValue(path, out var cached)) { box.Image = cached; return; }
        // Só carrega depois que o controle tem handle: o BeginInvoke de volta à UI precisa dele.
        if (box.IsHandleCreated) StartThumb(box, path, video);
        else box.HandleCreated += (_, _) => StartThumb(box, path, video);
    }

    private static void StartThumb(PictureBox box, string path, bool video)
    {
        _ = Task.Run(async () =>
        {
            Bitmap? bmp = video ? await VideoThumbnail(path) : Images.LoadThumbnail(path, 600);
            if (bmp == null) return;
            lock (ThumbCache)
            {
                if (ThumbCache.Count > 600) ThumbCache.Clear();
                ThumbCache[path] = bmp;
            }
            try { if (!box.IsDisposed) box.BeginInvoke(() => { if (!box.IsDisposed) box.Image = bmp; }); }
            catch (InvalidOperationException) { }
        });
    }

    private static async Task<Bitmap?> VideoThumbnail(string path)
    {
        try
        {
            var file = await StorageFile.GetFileFromPathAsync(path);
            using var thumb = await file.GetThumbnailAsync(ThumbnailMode.VideosView, 480, ThumbnailOptions.ResizeThumbnail);
            if (thumb == null) return null;
            using var stream = thumb.AsStreamForRead();
            using var img = Image.FromStream(stream);
            return new Bitmap(img);
        }
        catch (Exception e)
        {
            Trace.Log("miniatura de vídeo: " + e.Message);
            return null;
        }
    }
}
