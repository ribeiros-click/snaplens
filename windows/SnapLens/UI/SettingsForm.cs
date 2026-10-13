using static SnapLens.Loc;

namespace SnapLens;

public sealed class SettingsForm : Form
{
    private readonly FlowLayoutPanel root;
    private const int W = 500;

    public SettingsForm()
    {
        Ui.Window(this, L("Ajustes"), 560, 760);
        MinimumSize = new Size(540, 400);
        MaximizeBox = false;
        BackColor = Color.FromArgb(243, 243, 245);
        root = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = true, Padding = new Padding(16, 12, 16, 16) };
        Controls.Add(root);

        // Idioma
        var lang = Section(L("Idioma"));
        var langBox = Combo();
        langBox.Items.Add(L("Mesmo do sistema"));
        foreach (var l in L10n.Languages) langBox.Items.Add(l.Name);
        langBox.SelectedIndex = L10n.Selection == "system" ? 0 : Array.FindIndex(L10n.Languages, l => l.Code == L10n.Selection) + 1;
        langBox.SelectedIndexChanged += (_, _) =>
        {
            var code = langBox.SelectedIndex == 0 ? "system" : L10n.Languages[langBox.SelectedIndex - 1].Code;
            if (code != L10n.Selection) BeginInvoke(() => L10n.Selection = code);
        };
        Row(lang, L("Idioma do app"), langBox);

        // Geral
        var general = Section(L("Geral"));
        var login = Check(L("Iniciar com o Windows"), Settings.LaunchAtLogin);
        var loginError = Note("", Color.Firebrick);
        loginError.Visible = false;
        login.CheckedChanged += (_, _) =>
        {
            try { Settings.LaunchAtLogin = login.Checked; loginError.Visible = false; }
            catch (Exception e) { loginError.Text = e.Message; loginError.Visible = true; }
        };
        general.Controls.Add(login);
        general.Controls.Add(loginError);

        // Atalhos
        var keys = Section(L("Atalhos globais"));
        foreach (var action in Shortcuts.All) keys.Controls.Add(ShortcutRow(action));
        keys.Controls.Add(Note(L("Clique no atalho e pressione a nova combinação (precisa incluir Ctrl, Alt ou Win).")));

        // Gravação
        var rec = Section(L("Gravação de vídeo"));
        var sys = Check(L("Gravar áudio do sistema"), Settings.Data.RecSystem);
        sys.CheckedChanged += (_, _) => { Settings.Data.RecSystem = sys.Checked; Settings.Save(); };
        var mic = Check(L("Gravar microfone"), Settings.Data.RecMic);
        mic.CheckedChanged += (_, _) => { Settings.Data.RecMic = mic.Checked; Settings.Save(); };
        rec.Controls.Add(sys);
        rec.Controls.Add(mic);
        rec.Controls.Add(Note(L("Grava a tela inteira onde está o mouse, em MP4. Com os dois desligados, o vídeo fica sem áudio. Os vídeos vão para a Biblioteca.")));

        // Compartilhar
        var share = Section(L("Compartilhar por link público"));
        var server = new TextBox { Width = 290, Text = Settings.Data.ShareServer, PlaceholderText = ShareConfig.DefaultServer };
        server.TextChanged += (_, _) => { Settings.Data.ShareServer = server.Text.Trim(); Settings.Save(); };
        Row(share, L("Servidor"), server);
        var expiry = Combo();
        foreach (var e in ShareConfig.AllExpiries) expiry.Items.Add(e.Title());
        expiry.SelectedIndex = Array.IndexOf(ShareConfig.AllExpiries, ShareConfig.Expiry);
        expiry.SelectedIndexChanged += (_, _) => { Settings.Data.ShareExpiry = (int)ShareConfig.AllExpiries[expiry.SelectedIndex]; Settings.Save(); };
        Row(share, L("Validade padrão do link"), expiry);
        var once = Check(L("Visualização única"), Settings.Data.ShareOnce);
        var shareNote = Note("");
        void UpdateShareNote() => shareNote.Text = once.Checked
            ? L("O link se apaga automaticamente após a primeira abertura. A validade continua valendo como tempo máximo de vida do link — vale o que ocorrer primeiro.")
            : L("O botão “link” no overlay e na Biblioteca envia a imagem e copia a URL. Links são anônimos — nenhuma conta necessária. Guarde o token de exclusão para apagar um link fora do app.");
        once.CheckedChanged += (_, _) => { Settings.Data.ShareOnce = once.Checked; Settings.Save(); UpdateShareNote(); };
        UpdateShareNote();
        share.Controls.Add(once);
        share.Controls.Add(shareNote);

        // Provedor de IA
        var ai = Section(L("Provedor de IA"));
        var active = Combo(260);
        active.Items.Add(L("Nativo (Windows OCR, offline)"));
        foreach (var p in Providers.All) active.Items.Add(p.Name());
        active.SelectedIndex = Enum.TryParse<Provider>(Settings.Data.ActiveProvider, out var cur) ? Array.IndexOf(Providers.All, cur) + 1 : 0;
        var titles = new Dictionary<Provider, GroupBox>();
        void RefreshTitles()
        {
            foreach (var (p, box) in titles)
                box.Text = p.Name() + (Settings.Data.ActiveProvider == p.ToString() ? "  ✓ " + L("ativo") : "");
        }
        active.SelectedIndexChanged += (_, _) =>
        {
            Settings.Data.ActiveProvider = active.SelectedIndex == 0 ? "" : Providers.All[active.SelectedIndex - 1].ToString();
            Settings.Save();
            RefreshTitles();
        };
        Row(ai, L("Provedor ativo"), active);
        ai.Controls.Add(Note(L("“Descrever com IA” usa o provedor ativo. Sem provedor (ou sem chave configurada), usa o modo nativo. O OCR de texto sempre roda localmente com o Windows OCR.")));

        foreach (var p in Providers.All)
        {
            var box = Section(p.Name());
            titles[p] = (GroupBox)box.Parent!;
            var key = new TextBox { Width = 290, UseSystemPasswordChar = true, Text = p.ApiKey() };
            key.TextChanged += (_, _) =>
            {
                p.SetApiKey(key.Text);
                // Primeira chave salva: o provedor vira o ativo (como no macOS).
                if (key.Text.Trim().Length > 0 && Settings.Data.ActiveProvider == "")
                    active.SelectedIndex = Array.IndexOf(Providers.All, p) + 1;
            };
            Row(box, p.NeedsKey() ? "API key" : L("API key (opcional)"), key);
            var model = new TextBox { Width = 290, Text = Settings.Data.Models.GetValueOrDefault(p.ToString(), ""), PlaceholderText = p.DefaultModel().Length == 0 ? L("ex.: llava, gpt-4o…") : p.DefaultModel() };
            model.TextChanged += (_, _) => { Settings.Data.Models[p.ToString()] = model.Text.Trim(); Settings.Save(); };
            Row(box, L("Modelo"), model);
            var baseUrl = new TextBox { Width = 290, Text = Settings.Data.Bases.GetValueOrDefault(p.ToString(), ""), PlaceholderText = p.DefaultBase() };
            baseUrl.TextChanged += (_, _) => { Settings.Data.Bases[p.ToString()] = baseUrl.Text.Trim(); Settings.Save(); };
            Row(box, L("URL base"), baseUrl);
            box.Controls.Add(Note(p.Hint()));
        }
        RefreshTitles();
    }

    // MARK: Construção

    private FlowLayoutPanel Section(string title)
    {
        var g = new GroupBox { Text = title, Width = W, AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, Padding = new Padding(10, 6, 10, 8), Margin = new Padding(0, 0, 0, 12), BackColor = Color.White, Font = Ui.Bold };
        var inner = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoSize = true, Dock = DockStyle.Fill, Font = Ui.Body, MinimumSize = new Size(W - 24, 0) };
        g.Controls.Add(inner);
        root.Controls.Add(g);
        return inner;
    }

    private static void Row(FlowLayoutPanel parent, string label, Control control)
    {
        var row = new TableLayoutPanel { ColumnCount = 2, AutoSize = true, Width = W - 24, Margin = new Padding(0, 2, 0, 2) };
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, W - 24 - 300));
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 300));
        var l = Ui.Label(label);
        l.Anchor = AnchorStyles.Left;
        l.MaximumSize = new Size(W - 24 - 306, 0);
        control.Anchor = AnchorStyles.Left;
        row.Controls.Add(l, 0, 0);
        row.Controls.Add(control, 1, 0);
        parent.Controls.Add(row);
    }

    private static ComboBox Combo(int width = 290) => new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = width };

    private static CheckBox Check(string text, bool value) => new() { Text = text, Checked = value, AutoSize = true, Margin = new Padding(0, 4, 0, 4) };

    private static Label Note(string text, Color? color = null)
    {
        var l = Ui.Label(text, Ui.Small, color ?? Ui.Secondary);
        l.MaximumSize = new Size(W - 30, 0);
        l.Margin = new Padding(0, 4, 0, 2);
        return l;
    }

    private Control ShortcutRow(ShortcutAction action)
    {
        var row = new TableLayoutPanel { ColumnCount = 3, AutoSize = true, Width = W - 24, Margin = new Padding(0, 1, 0, 1) };
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, W - 24 - 250));
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 216));
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 34));
        var l = Ui.Label(action.Title());
        l.Anchor = AnchorStyles.Left;
        var button = new ShortcutButton(action) { Width = 210, Anchor = AnchorStyles.Left };
        var tips = new ToolTip();
        var reset = Ui.Glyph("", L("Restaurar padrão"), () => { action.Reset(); button.Refresh(); }, tips);
        row.Controls.Add(l, 0, 0);
        row.Controls.Add(button, 1, 0);
        row.Controls.Add(reset, 2, 0);
        return row;
    }

    /// Botão que grava uma combinação de teclas ao ser clicado.
    private sealed class ShortcutButton : System.Windows.Forms.Button
    {
        private readonly ShortcutAction action;
        private bool recording;

        public ShortcutButton(ShortcutAction action)
        {
            this.action = action;
            UseVisualStyleBackColor = true;
            Text = action.Get().Display;
            Click += (_, _) => { if (recording) Stop(); else Start(); };
            LostFocus += (_, _) => Stop();
        }

        public override void Refresh()
        {
            Text = action.Get().Display;
            base.Refresh();
        }

        private void Start()
        {
            recording = true;
            Shortcuts.SetSuspended(true);
            Text = L("Pressione as teclas… (Esc cancela)");
        }

        private void Stop()
        {
            if (!recording) return;
            recording = false;
            Text = action.Get().Display;
            Shortcuts.SetSuspended(false);
        }

        protected override bool IsInputKey(Keys keyData) => recording || base.IsInputKey(keyData);

        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            if (!recording) return base.ProcessCmdKey(ref msg, keyData);
            var key = keyData & Keys.KeyCode;
            if (key == Keys.Escape) { Stop(); return true; }
            if (key is Keys.ControlKey or Keys.ShiftKey or Keys.Menu or Keys.LWin or Keys.RWin) return true;
            bool win = (Control.ModifierKeys & Keys.LWin) != 0 || GetKeyState(0x5B) < 0 || GetKeyState(0x5C) < 0;
            int mods = 0;
            if ((keyData & Keys.Control) != 0) mods |= Shortcut.Ctrl;
            if ((keyData & Keys.Alt) != 0) mods |= Shortcut.Alt;
            if ((keyData & Keys.Shift) != 0) mods |= Shortcut.Shift;
            if (win) mods |= Shortcut.Win;
            if ((mods & (Shortcut.Ctrl | Shortcut.Alt | Shortcut.Win)) == 0) return true; // exige modificador
            recording = false;
            var s = new Shortcut((int)key, mods);
            action.Set(s);
            Text = s.Display;
            return true;
        }

        [System.Runtime.InteropServices.DllImport("user32.dll")] private static extern short GetKeyState(int key);
    }
}
