using static SnapLens.Loc;

namespace SnapLens;

/// Resultado do OCR: texto editável + tradução (pelo provedor de IA ativo).
public sealed class OcrResultForm : Form
{
    private static OcrResultForm? current;

    private static readonly (string Code, string Key)[] Targets =
    {
        ("pt-BR", "Português (Brasil)"), ("en", "Inglês"), ("es", "Espanhol"), ("fr", "Francês"), ("de", "Alemão"),
        ("it", "Italiano"), ("ja", "Japonês"), ("ko", "Coreano"), ("zh-Hans", "Chinês (simplificado)"),
    };

    public static void ShowResult(string text, Action<string> onCopy)
    {
        current?.Close();
        current = new OcrResultForm(text, onCopy);
        current.FormClosed += (_, _) => current = null;
        current.Show();
        current.Activate();
        OverlayForm.SetForegroundWindow(current.Handle);
    }

    private OcrResultForm(string original, Action<string> onCopy)
    {
        Ui.Window(this, L("Resultado do OCR"), 600, 460);
        TopMost = true;
        MinimumSize = new Size(480, 320);

        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(14), ColumnCount = 1, RowCount = 6 };
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 55));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 45));
        Controls.Add(layout);

        var header = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill, WrapContents = false };
        header.Controls.Add(Ui.Label(L("Texto reconhecido"), Ui.Bold));
        header.Controls.Add(Ui.Label("   " + L("Já copiado para a área de transferência"), Ui.Small, Ui.Secondary));
        layout.Controls.Add(header);

        var text = new TextBox { Multiline = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill, Text = original.Replace("\n", "\r\n"), Font = new Font("Segoe UI", 10.5f) };
        layout.Controls.Add(text);

        var bar = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill, WrapContents = false, Margin = new Padding(0, 8, 0, 4) };
        var target = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 210, Margin = new Padding(12, 2, 6, 0) };
        foreach (var t in Targets) target.Items.Add(L(t.Key));
        int sel = Array.FindIndex(Targets, t => t.Code == L10n.Code);
        target.SelectedIndex = Math.Max(0, sel);
        var status = Ui.Label("", Ui.Small, Ui.Secondary, wrap: true);
        var translatedHeader = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill, WrapContents = false, Visible = false };
        var translatedLabel = Ui.Label(L("Tradução"), Ui.Bold);
        translatedHeader.Controls.Add(translatedLabel);
        var translated = new TextBox { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill, Visible = false, BackColor = Color.FromArgb(248, 248, 250), Font = new Font("Segoe UI", 10.5f) };
        translatedHeader.Controls.Add(Ui.Button(L("Copiar tradução"), () => onCopy(translated.Text.Replace("\r\n", "\n"))));

        System.Windows.Forms.Button? translateButton = null;
        translateButton = Ui.Button(L("Traduzir"), async () =>
        {
            status.ForeColor = Ui.Secondary;
            if (Providers.Active is not Provider p)
            {
                status.ForeColor = Color.Firebrick;
                status.Text = L("Configure um provedor de IA em Ajustes para traduzir.");
                return;
            }
            var src = text.Text.Trim();
            if (src.Length == 0) return;
            translateButton!.Enabled = false;
            status.Text = L("Traduzindo com %@…", p.ShortName());
            try
            {
                var result = await AIClient.Translate(src, L(Targets[target.SelectedIndex].Key), p);
                translated.Text = result.Replace("\n", "\r\n");
                translatedLabel.Text = L("Tradução") + $"  ({p.ShortName()})";
                translatedHeader.Visible = translated.Visible = true;
                status.Text = "";
            }
            catch (Exception e)
            {
                status.ForeColor = Color.Firebrick;
                status.Text = L("Falha na tradução: %@", e.Message);
            }
            finally { translateButton.Enabled = true; }
        });

        bar.Controls.Add(Ui.Button(L("Copiar"), () => onCopy(text.Text.Replace("\r\n", "\n"))));
        bar.Controls.Add(Ui.Label(L("Traduzir para"), null, null));
        bar.Controls[^1].Margin = new Padding(16, 6, 0, 0);
        bar.Controls.Add(target);
        bar.Controls.Add(translateButton);
        layout.Controls.Add(bar);
        layout.Controls.Add(status);
        layout.Controls.Add(translatedHeader);
        layout.Controls.Add(translated);
        AcceptButton = null;
    }
}
