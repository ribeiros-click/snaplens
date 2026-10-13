using static SnapLens.Loc;

namespace SnapLens;

/// Janela mostrada após o upload: link público + token de exclusão.
public sealed class ShareResultForm : Form
{
    public ShareResultForm(string url, DateTime? expires, string token, bool once)
    {
        Ui.Window(this, L("Link compartilhado"), 500, once ? 380 : 350);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = MinimizeBox = false;
        TopMost = true;

        var copied = Ui.Label("", Ui.Small, Ui.Secondary);
        void Copy(string text, string label)
        {
            TrayApp.Instance.CopyText(text);
            copied.Text = L("%@ copiado ✓", label);
        }

        var root = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, Padding = new Padding(20, 16, 20, 12), AutoScroll = true };
        Controls.Add(root);

        var title = Ui.Label("✓  " + L("Link pronto para compartilhar"), new Font("Segoe UI Semibold", 12f), Color.FromArgb(30, 140, 60));
        root.Controls.Add(title);
        if (once) root.Controls.Add(Ui.Label(L("Visualização única — o link se apaga na primeira abertura."), Ui.Small, Ui.Orange));

        root.Controls.Add(Spacer(6));
        root.Controls.Add(Ui.Label(L("Link público"), Ui.Small, Ui.Secondary));
        var urlBox = new TextBox { Text = url, ReadOnly = true, Width = 450, Font = Ui.Mono, BorderStyle = BorderStyle.FixedSingle, BackColor = Color.FromArgb(248, 248, 250) };
        root.Controls.Add(urlBox);
        Shown += (_, _) => { urlBox.SelectionLength = 0; ActiveControl = null; };
        var row = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Margin = new Padding(0, 4, 0, 0) };
        row.Controls.Add(Ui.Button(L("Copiar link"), () => Copy(url, L("Link"))));
        row.Controls.Add(Ui.Button(L("Abrir"), () => TrayApp.Open(url)));
        var exp = Ui.Label(ExpiresText(expires, once), Ui.Small, Ui.Secondary, wrap: true);
        exp.MaximumSize = new Size(270, 0);
        exp.Margin = new Padding(8, 6, 0, 0);
        row.Controls.Add(exp);
        root.Controls.Add(row);

        root.Controls.Add(new Label { Height = 1, Width = 450, BackColor = Color.FromArgb(225, 225, 228), Margin = new Padding(0, 12, 0, 10) });

        root.Controls.Add(Ui.Label(L("Token de exclusão"), Ui.Small, Ui.Secondary));
        var tokenRow = new FlowLayoutPanel { AutoSize = true, WrapContents = false };
        var tokenBox = new TextBox { Text = token, ReadOnly = true, UseSystemPasswordChar = true, Width = 250, Font = Ui.Mono, BorderStyle = BorderStyle.FixedSingle, BackColor = Color.FromArgb(248, 248, 250) };
        tokenRow.Controls.Add(tokenBox);
        var tips = new ToolTip();
        System.Windows.Forms.Button? eye = null;
        eye = Ui.Glyph(Icons.Eye, L("Mostrar token"), () =>
        {
            tokenBox.UseSystemPasswordChar = !tokenBox.UseSystemPasswordChar;
            tips.SetToolTip(eye!, tokenBox.UseSystemPasswordChar ? L("Mostrar token") : L("Ocultar token"));
        }, tips);
        eye.Margin = new Padding(4, 0, 4, 0);
        tokenRow.Controls.Add(eye);
        tokenRow.Controls.Add(Ui.Button(L("Copiar token"), () => Copy(token, L("Token"))));
        root.Controls.Add(tokenRow);
        root.Controls.Add(Ui.Label(L("Guarde este token. Sem ele, não é possível apagar o link fora deste app."), Ui.Small, Ui.Orange, wrap: true));

        var bottom = new FlowLayoutPanel { Dock = DockStyle.Bottom, FlowDirection = FlowDirection.RightToLeft, Height = 44, Padding = new Padding(16, 6, 16, 8) };
        var close = Ui.Button(L("Fechar"), Close);
        bottom.Controls.Add(close);
        bottom.Controls.Add(copied);
        copied.Margin = new Padding(0, 8, 12, 0);
        Controls.Add(bottom);
        AcceptButton = close;
        CancelButton = close;
    }

    private static Label Spacer(int h) => new() { Height = h, Width = 1, Margin = Padding.Empty };

    private static string ExpiresText(DateTime? expires, bool once)
    {
        if (expires is not DateTime d) return L("Sem expiração definida");
        var b = L("Expira em %@", Format.DateTimeShort(d));
        return once ? b + L(" ou na primeira visualização, o que ocorrer primeiro") : b;
    }
}
