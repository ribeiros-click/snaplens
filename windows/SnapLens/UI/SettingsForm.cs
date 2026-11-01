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
        share.Controls.Add(Note(L("Ao clicar em “link” no overlay ou na Biblioteca, você escolhe a validade (ver uma vez, 1 dia, 5 dias, X dias ou nunca) antes do envio. Links são anônimos — nenhuma conta necessária. Guarde o token de exclusão para apagar um link fora do app.")));

        // OneDrive / Google Drive
        var cloud = Section(L("Salvar no OneDrive ou Google Drive"));
        foreach (var d in Enum.GetValues<CloudDrive>()) cloud.Controls.Add(CloudRow(d));
        cloud.Controls.Add(Note(L("Conecte uma conta para escolher, na hora de compartilhar, onde salvar a imagem. Ela vai para a pasta SnapLens do Drive e recebe um link de leitura público. O SnapLens só acessa os arquivos que ele mesmo cria (no Google Drive) e guarda o acesso no Gerenciador de Credenciais.")));
        var advanced = new LinkLabel { Text = L("Credenciais OAuth (avançado)"), AutoSize = true, Margin = new Padding(0, 6, 0, 2) };
        var advPanel = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoSize = true, Visible = false, Margin = Padding.Empty };
        advanced.LinkClicked += (_, _) => advPanel.Visible = !advPanel.Visible;
        var odId = new TextBox { Width = 290, Text = Settings.Data.OneDriveClientId };
        odId.TextChanged += (_, _) => { Settings.Data.OneDriveClientId = odId.Text.Trim(); Settings.Save(); };
        Row(advPanel, L("OneDrive — ID do cliente"), odId);
        var gId = new TextBox { Width = 290, Text = Settings.Data.GoogleClientId };
        gId.TextChanged += (_, _) => { Settings.Data.GoogleClientId = gId.Text.Trim(); Settings.Save(); };
        Row(advPanel, L("Google — ID do cliente"), gId);
        var gSecret = new TextBox { Width = 290, Text = Settings.Data.GoogleClientSecret, UseSystemPasswordChar = true };
        gSecret.TextChanged += (_, _) => { Settings.Data.GoogleClientSecret = gSecret.Text.Trim(); Settings.Save(); };
        Row(advPanel, L("Google — chave secreta do cliente"), gSecret);
        advPanel.Controls.Add(Note(L("Deixe em branco para usar as credenciais deste build. Preencha só se você registrou o seu próprio app na Microsoft ou no Google (redirecionamento: http://localhost).")));
        cloud.Controls.Add(advanced);
        cloud.Controls.Add(advPanel);

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

    /// Linha "OneDrive · conectado como x  [Desconectar]" / "[Conectar…]".
    private static Control CloudRow(CloudDrive drive)
    {
        var panel = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoSize = true, Margin = new Padding(0, 2, 0, 4) };
        var row = new TableLayoutPanel { ColumnCount = 2, AutoSize = true, Width = W - 24 };
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, W - 24 - 130));
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 130));
        var status = Ui.Label("", Ui.Body);
        status.Anchor = AnchorStyles.Left;
        status.MaximumSize = new Size(W - 24 - 136, 0);
        var error = Ui.Label("", Ui.Small, Color.Firebrick, wrap: true);
        error.MaximumSize = new Size(W - 30, 0);
        error.Visible = false;
        System.Windows.Forms.Button? button = null;

        void Refresh()
        {
            if (status.IsDisposed) return;
            if (status.InvokeRequired) { status.BeginInvoke(Refresh); return; }
            var account = drive.AccountName();
            status.Text = drive.IsConnected()
                ? drive.Name() + " · " + (account.Length > 0 ? L("Conectado como %@", account) : L("Conectado"))
                : drive.Name() + (drive.IsConfigured() ? "" : " · " + L("Sem credenciais OAuth neste build (veja “avançado”)."));
            button!.Text = drive.IsConnected() ? L("Desconectar") : L("Conectar…");
            button.Enabled = drive.IsConnected() || drive.IsConfigured();
        }

        button = Ui.Button(L("Conectar…"), async () =>
        {
            error.Visible = false;
            if (drive.IsConnected()) { drive.Disconnect(); Refresh(); return; }
            button!.Enabled = false;
            try
            {
                await Cloud.Connect(drive);
                if (panel.FindForm() is Form f) { f.Activate(); }
            }
            catch (Exception e) { error.Text = e.Message; error.Visible = true; }
            Refresh();
        });
        button.Anchor = AnchorStyles.Right;
        // As credenciais do "avançado" podem mudar enquanto a janela está aberta.
        panel.VisibleChanged += (_, _) => Refresh();
        Settings.Changed += Refresh;
        panel.Disposed += (_, _) => Settings.Changed -= Refresh;
        row.Controls.Add(status, 0, 0);
        row.Controls.Add(button, 1, 0);
        panel.Controls.Add(row);
        panel.Controls.Add(error);
        Refresh();
        return panel;
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
