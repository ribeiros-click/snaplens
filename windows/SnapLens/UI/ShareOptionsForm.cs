using static SnapLens.Loc;

namespace SnapLens;

/// Caixa mostrada ao clicar em "compartilhar": validade do link (ver uma vez, 1 dia, 5 dias, X dias, nunca).
public sealed class ShareOptionsForm : Form
{
    public ShareChoice Choice { get; private set; } = ShareConfig.LastChoice;
    public int CustomDays { get; private set; } = ShareConfig.CustomDays;

    public ShareOptionsForm()
    {
        Ui.Window(this, L("Compartilhar"), 400, 300);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = MinimizeBox = false;
        ShowInTaskbar = false;
        TopMost = true;

        var root = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, Padding = new Padding(20, 16, 20, 8) };
        Controls.Add(root);
        root.Controls.Add(Ui.Label(L("Compartilhar por link público"), Ui.Bold));
        root.Controls.Add(new Label { Height = 6, Width = 1, Margin = Padding.Empty });

        var hint = Ui.Label("", Ui.Small, Ui.Secondary, wrap: true);
        hint.MaximumSize = new Size(350, 0);
        var radios = new Dictionary<ShareChoice, RadioButton>();
        var days = new NumericUpDown { Minimum = 1, Maximum = 365, Value = CustomDays, Width = 60, TextAlign = HorizontalAlignment.Right, Margin = new Padding(6, 0, 6, 0) };

        void Select(ShareChoice c)
        {
            Choice = c;
            hint.Text = c switch
            {
                ShareChoice.Once => L("O link se apaga na primeira abertura (ou em 30 dias, o que vier primeiro)."),
                ShareChoice.Never => L("O link fica no ar até você revogá-lo na Biblioteca ou pela página de token."),
                _ => L("Passado o prazo, a imagem é apagada do servidor. Você pode revogar antes."),
            };
        }

        foreach (var c in ShareConfig.AllChoices)
        {
            var row = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Margin = new Padding(0, 2, 0, 2) };
            var rb = new RadioButton { Text = c.Title(), AutoSize = true, Checked = c == Choice, Margin = new Padding(0, 3, 0, 0) };
            rb.CheckedChanged += (_, _) => { if (rb.Checked) Select(c); };
            radios[c] = rb;
            row.Controls.Add(rb);
            if (c == ShareChoice.Custom)
            {
                days.ValueChanged += (_, _) => radios[ShareChoice.Custom].Checked = true;
                row.Controls.Add(days);
                row.Controls.Add(Ui.Label(L("dias")));
            }
            root.Controls.Add(row);
        }
        root.Controls.Add(hint);
        Select(Choice);

        var bottom = new FlowLayoutPanel { Dock = DockStyle.Bottom, FlowDirection = FlowDirection.RightToLeft, Height = 44, Padding = new Padding(16, 6, 16, 8) };
        var ok = Ui.Button(L("Compartilhar"), () =>
        {
            CustomDays = (int)days.Value;
            ShareConfig.LastChoice = Choice;
            ShareConfig.CustomDays = CustomDays;
            DialogResult = DialogResult.OK;
            Close();
        });
        var cancel = Ui.Button(L("Cancelar"), () => { DialogResult = DialogResult.Cancel; Close(); });
        bottom.Controls.Add(ok);
        bottom.Controls.Add(cancel);
        Controls.Add(bottom);
        AcceptButton = ok;
        CancelButton = cancel;
    }
}
