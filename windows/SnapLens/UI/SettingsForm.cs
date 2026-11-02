using static SnapLens.Loc;

namespace SnapLens;

public sealed class SettingsForm : Form
{
    private FlowLayoutPanel root = null!;   // página (aba) onde Section() adiciona os grupos
    private readonly TabControl tabs;
    private const int W = 500;

    public SettingsForm()
    {
        Ui.Window(this, L("Ajustes"), 580, 640);
        MinimumSize = new Size(560, 400);
        MaximizeBox = false;
        BackColor = Color.FromArgb(243, 243, 245);
        tabs = new TabControl { Dock = DockStyle.Fill, Padding = new Point(14, 5) };
        Controls.Add(tabs);
        tabs.SelectedIndexChanged += (_, _) => lastTab = tabs.SelectedIndex;

        // Idioma
        root = Page(L("Geral"));
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
        root = Page(L("Atalhos"));
        var keys = Section(L("Atalhos globais"));
        foreach (var action in Shortcuts.All) keys.Controls.Add(ShortcutRow(action));
        keys.Controls.Add(Note(L("Clique no atalho e pressione a nova combinação (precisa incluir Ctrl, Alt ou Win).")));

        // Gravação
        root = Page(L("Gravação"));
        var rec = Section(L("Gravação de vídeo"));
        var sys = Check(L("Gravar áudio do sistema"), Settings.Data.RecSystem);
        sys.CheckedChanged += (_, _) => { Settings.Data.RecSystem = sys.Checked; Settings.Save(); };
        var mic = Check(L("Gravar microfone"), Settings.Data.RecMic);
        mic.CheckedChanged += (_, _) => { Settings.Data.RecMic = mic.Checked; Settings.Save(); };
        rec.Controls.Add(sys);
        rec.Controls.Add(mic);
        rec.Controls.Add(Note(L("Grava a tela inteira onde está o mouse, em MP4. Com os dois desligados, o vídeo fica sem áudio. Os vídeos vão para a Biblioteca.")));

        // Compartilhar
        root = Page(L("Compartilhar"));
        var share = Section(L("Compartilhar por link público"));
        var server = new TextBox { Width = 290, Text = Settings.Data.ShareServer, PlaceholderText = ShareConfig.DefaultServer };
        server.TextChanged += (_, _) => { Settings.Data.ShareServer = server.Text.Trim(); Settings.Save(); };
        Row(share, L("Servidor"), server);
        share.Controls.Add(Note(L("Ao clicar em “link” no overlay ou na Biblioteca, você escolhe a validade (ver uma vez, 1 dia, 5 dias, X dias ou nunca) antes do envio. Links são anônimos — nenhuma conta necessária. Guarde o token de exclusão para apagar um link fora do app.")));

        // Google Drive (OneDrive oculto por enquanto: ver Cloud.Visible)
        var cloud = Section(L("Salvar no Google Drive"));
        foreach (var d in Cloud.Visible) cloud.Controls.Add(CloudRow(d));
        cloud.Controls.Add(Note(L("Conecte uma conta para escolher, na hora de compartilhar, onde salvar a imagem. Ela vai para a pasta SnapLens do Drive e recebe um link de leitura público. O SnapLens só acessa os arquivos que ele mesmo cria (no Google Drive) e guarda o acesso no Gerenciador de Credenciais.")));
        var advanced = new LinkLabel { Text = L("Credenciais OAuth (avançado)"), AutoSize = true, Margin = new Padding(0, 6, 0, 2) };
        var advPanel = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoSize = true, Visible = false, Margin = Padding.Empty };
        advanced.LinkClicked += (_, _) => advPanel.Visible = !advPanel.Visible;
        if (Cloud.Visible.Contains(CloudDrive.OneDrive))
        {
            var odId = new TextBox { Width = 290, Text = Settings.Data.OneDriveClientId };
            odId.TextChanged += (_, _) => { Settings.Data.OneDriveClientId = odId.Text.Trim(); Settings.Save(); };
            Row(advPanel, L("OneDrive — ID do cliente"), odId);
        }
        var gId = new TextBox { Width = 290, Text = Settings.Data.GoogleClientId };
        gId.TextChanged += (_, _) => { Settings.Data.GoogleClientId = gId.Text.Trim(); Settings.Save(); };
        Row(advPanel, L("Google — ID do cliente"), gId);
        var gSecret = new TextBox { Width = 290, Text = Settings.Data.GoogleClientSecret, UseSystemPasswordChar = true };
        gSecret.TextChanged += (_, _) => { Settings.Data.GoogleClientSecret = gSecret.Text.Trim(); Settings.Save(); };
        Row(advPanel, L("Google — chave secreta do cliente"), gSecret);
        var gKey = new TextBox { Width = 290, Text = Settings.Data.GoogleApiKey, UseSystemPasswordChar = true };
        gKey.TextChanged += (_, _) => { Settings.Data.GoogleApiKey = gKey.Text.Trim(); Settings.Save(); };
        Row(advPanel, L("Google — chave de API (seletor de pastas)"), gKey);
        advPanel.Controls.Add(Note(L("Deixe em branco para usar as credenciais deste build. Preencha só se você registrou o seu próprio app na Microsoft ou no Google (redirecionamento: http://localhost).")));
        cloud.Controls.Add(advanced);
        cloud.Controls.Add(advPanel);
        BuildBackupSection(Section(L("Backup automático da Biblioteca")));

        // IA
        aiPage = Page(L("IA"));
        BuildAiPage();
        tabs.SelectedIndex = Math.Clamp(lastTab, 0, tabs.TabCount - 1);
    }

    private static int lastTab;   // aba reaberta na próxima vez (enquanto o app estiver aberto)
    private readonly FlowLayoutPanel aiPage;

    private FlowLayoutPanel Page(string title)
    {
        var page = new TabPage(title) { BackColor = BackColor, UseVisualStyleBackColor = false };
        var panel = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = true, Padding = new Padding(12, 12, 12, 16) };
        page.Controls.Add(panel);
        tabs.TabPages.Add(page);
        return panel;
    }

    /// Aba IA: só os provedores adicionados aparecem (até 4); "Adicionar provedor" lista os que faltam.
    /// Reconstruída a cada adição/remoção.
    private void BuildAiPage()
    {
        aiPage.SuspendLayout();
        foreach (Control c in aiPage.Controls.Cast<Control>().ToList()) { aiPage.Controls.Remove(c); c.Dispose(); }
        root = aiPage;
        var added = Providers.Added;

        var ai = Section(L("Provedor de IA"));
        var active = Combo(260);
        active.Items.Add(L("Nativo (Windows OCR, offline)"));
        foreach (var p in added) active.Items.Add(p.Name());
        active.SelectedIndex = Enum.TryParse<Provider>(Settings.Data.ActiveProvider, out var cur) && added.Contains(cur) ? added.IndexOf(cur) + 1 : 0;
        var titles = new Dictionary<Provider, GroupBox>();
        void RefreshTitles()
        {
            foreach (var (p, box) in titles)
                box.Text = p.Name() + (Settings.Data.ActiveProvider == p.ToString() ? "  ✓ " + L("ativo") : "");
        }
        active.SelectedIndexChanged += (_, _) =>
        {
            Settings.Data.ActiveProvider = active.SelectedIndex <= 0 ? "" : added[active.SelectedIndex - 1].ToString();
            Settings.Save();
            RefreshTitles();
        };
        Row(ai, L("Provedor ativo"), active);
        ai.Controls.Add(Note(L("“Descrever com IA” usa o provedor ativo. Sem provedor (ou sem chave configurada), usa o modo nativo. O OCR de texto sempre roda localmente com o Windows OCR.")));

        var addRow = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Margin = new Padding(0, 6, 0, 2) };
        var remaining = Providers.All.Where(p => !added.Contains(p)).ToList();
        System.Windows.Forms.Button? addButton = null;
        addButton = Ui.Button("+  " + L("Adicionar provedor"), () =>
        {
            var menu = new ContextMenuStrip();
            foreach (var p in remaining)
                menu.Items.Add(p.Name(), null, (_, _) =>
                {
                    var list = Providers.Added;
                    if (list.Count >= Providers.MaxAdded || list.Contains(p)) return;
                    list.Add(p);
                    Providers.Added = list;
                    BeginInvoke(BuildAiPage);
                });
            menu.Show(addButton!, new Point(0, addButton!.Height));
        });
        addButton.Enabled = added.Count < Providers.MaxAdded && remaining.Count > 0;
        addRow.Controls.Add(addButton);
        var count = Ui.Label(L("%@ de %@", added.Count, Providers.MaxAdded), Ui.Small, Ui.Secondary);
        count.Margin = new Padding(8, 7, 0, 0);
        addRow.Controls.Add(count);
        ai.Controls.Add(addRow);

        foreach (var p in added)
        {
            var box = Section(p.Name());
            titles[p] = (GroupBox)box.Parent!;
            var key = new TextBox { Width = 290, UseSystemPasswordChar = true, Text = p.ApiKey() };
            key.TextChanged += (_, _) =>
            {
                p.SetApiKey(key.Text);
                // Primeira chave salva: o provedor vira o ativo (como no macOS).
                if (key.Text.Trim().Length > 0 && Settings.Data.ActiveProvider == "")
                    active.SelectedIndex = added.IndexOf(p) + 1;
            };
            Row(box, p.NeedsKey() ? "API key" : L("API key (opcional)"), key);
            var model = new TextBox { Width = 290, Text = Settings.Data.Models.GetValueOrDefault(p.ToString(), ""), PlaceholderText = p.DefaultModel().Length == 0 ? L("ex.: llava, gpt-4o…") : p.DefaultModel() };
            model.TextChanged += (_, _) => { Settings.Data.Models[p.ToString()] = model.Text.Trim(); Settings.Save(); };
            Row(box, L("Modelo"), model);
            var baseUrl = new TextBox { Width = 290, Text = Settings.Data.Bases.GetValueOrDefault(p.ToString(), ""), PlaceholderText = p.DefaultBase() };
            baseUrl.TextChanged += (_, _) => { Settings.Data.Bases[p.ToString()] = baseUrl.Text.Trim(); Settings.Save(); };
            Row(box, L("URL base"), baseUrl);
            box.Controls.Add(Note(p.Hint()));
            var remove = new LinkLabel { Text = L("Remover"), AutoSize = true, LinkColor = Color.Firebrick, Margin = new Padding(0, 4, 0, 2) };
            remove.LinkClicked += (_, _) =>
            {
                var ok = MessageBox.Show(this, L("A chave de API, o modelo e a URL deste provedor serão apagados."), L("Remover %@?", p.Name()),
                    MessageBoxButtons.OKCancel, MessageBoxIcon.Warning) == DialogResult.OK;
                if (!ok) return;
                p.Remove();
                BeginInvoke(BuildAiPage);
            };
            box.Controls.Add(remove);
        }
        RefreshTitles();
        aiPage.ResumeLayout();
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
    /// Backup automático da Biblioteca para um Drive conectado (mão única).
    private void BuildBackupSection(FlowLayoutPanel box)
    {
        var target = Combo(260);
        var images = Check(L("Screenshots e imagens"), Settings.Data.BackupImages);
        images.CheckedChanged += (_, _) => { Settings.Data.BackupImages = images.Checked; Settings.Save(); };
        var videos = Check(L("Gravações de vídeo"), Settings.Data.BackupVideos);
        videos.CheckedChanged += (_, _) => { Settings.Data.BackupVideos = videos.Checked; Settings.Save(); };
        var texts = Check(L("Textos (OCR, IA e copiados)"), Settings.Data.BackupTexts);
        texts.CheckedChanged += (_, _) => { Settings.Data.BackupTexts = texts.Checked; Settings.Save(); };
        var status = Ui.Label("", Ui.Small, Ui.Secondary);
        status.Margin = new Padding(8, 7, 0, 0);
        var sendAll = Ui.Button(L("Enviar a Biblioteca agora"), () => DriveBackup.Run(all: true));
        var actions = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Margin = new Padding(0, 4, 0, 2) };
        actions.Controls.Add(sendAll);
        actions.Controls.Add(status);
        var note = Note("");
        var options = new Control[] { images, videos, texts, actions };

        Row(box, L("Enviar para"), target);
        foreach (var c in options) box.Controls.Add(c);
        box.Controls.Add(note);

        var drives = new List<CloudDrive>();
        bool updating = false;
        void Refresh()
        {
            if (box.IsDisposed) return;
            if (box.InvokeRequired) { box.BeginInvoke(Refresh); return; }
            updating = true;
            drives = Cloud.Visible.Where(d => d.IsConnected()).ToList();
            target.Items.Clear();
            target.Items.Add(L("Desligado"));
            foreach (var d in drives) target.Items.Add(d.Name());
            var current = DriveBackup.Drive;
            target.SelectedIndex = current is CloudDrive c && drives.Contains(c) ? drives.IndexOf(c) + 1 : 0;
            foreach (var o in options) o.Visible = current != null;
            note.Text = current is CloudDrive cd
                ? L("Pasta: %@. Cada captura nova vai sozinha para lá. É uma cópia de segurança: apagar na Biblioteca não apaga no Drive.", cd.FolderDisplay())
                : drives.Count == 0
                    ? L("Conecte o Google Drive acima para ativar o backup.")
                    : L("Escolha um Drive para copiar sozinho cada captura nova, e a Biblioteca inteira quando quiser.");
            status.Text = DriveBackup.Status;
            sendAll.Enabled = !DriveBackup.Running;
            updating = false;
        }
        target.SelectedIndexChanged += (_, _) =>
        {
            if (updating) return;
            DriveBackup.Drive = target.SelectedIndex <= 0 ? null : drives[target.SelectedIndex - 1];
            DriveBackup.Run();
        };
        Settings.Changed += Refresh;
        DriveBackup.StatusChanged += Refresh;
        box.Disposed += (_, _) => { Settings.Changed -= Refresh; DriveBackup.StatusChanged -= Refresh; };
        Refresh();
    }

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
        var folderRow = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Margin = new Padding(0, 2, 0, 0) };
        var folderLabel = Ui.Label("", Ui.Small, Ui.Secondary);
        folderLabel.Margin = new Padding(0, 6, 8, 0);
        folderLabel.MaximumSize = new Size(W - 24 - 200, 0);
        folderLabel.AutoEllipsis = true;
        System.Windows.Forms.Button? choose = null;
        choose = Ui.Button(L("Escolher…"), async () =>
        {
            error.Visible = false;
            choose!.Enabled = false;
            try
            {
                if (await Cloud.PickGoogleFolder() is DriveFolderInfo f) drive.SetFolder(f);
                if (panel.FindForm() is Form form) form.Activate();
            }
            catch (Exception e) { error.Text = e.Message; error.Visible = true; }
            choose.Enabled = true;
        });
        var reset = Ui.Button(L("Padrão"), () => drive.SetFolder(null));
        folderRow.Controls.Add(folderLabel);
        folderRow.Controls.Add(choose);
        folderRow.Controls.Add(reset);

        void Refresh()
        {
            if (status.IsDisposed) return;
            if (status.InvokeRequired) { status.BeginInvoke(Refresh); return; }
            folderRow.Visible = drive.IsConnected();
            folderLabel.Text = L("Pasta: %@", drive.FolderDisplay());
            choose!.Enabled = drive.CanPickFolder();
            reset.Visible = drive.Folder() != null;
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
        panel.Controls.Add(folderRow);
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
