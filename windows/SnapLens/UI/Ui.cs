using static SnapLens.Loc;

namespace SnapLens;

/// Pequenos utilitários de interface compartilhados pelas janelas.
public static class Ui
{
    public static readonly Font Body = new("Segoe UI", 9.75f);
    public static readonly Font Small = new("Segoe UI", 8.5f);
    public static readonly Font Bold = new("Segoe UI Semibold", 10.5f);
    public static readonly Font Mono = new("Cascadia Mono", 10f);
    public static readonly Color Secondary = Color.FromArgb(105, 105, 110);
    public static readonly Color Accent = Color.FromArgb(0, 103, 192);
    public static readonly Color Orange = Color.FromArgb(200, 110, 0);

    public static void Window(Form f, string title, int width, int height)
    {
        f.Text = "SnapLens — " + title;
        f.Icon = Icons.App();
        f.Font = Body;
        f.AutoScaleMode = AutoScaleMode.Dpi;
        f.StartPosition = FormStartPosition.CenterScreen;
        f.ClientSize = new Size(width, height);
        f.BackColor = Color.White;
    }

    public static Label Label(string text, Font? font = null, Color? color = null, bool wrap = false) => new()
    {
        Text = text,
        Font = font ?? Body,
        ForeColor = color ?? SystemColors.ControlText,
        AutoSize = true,
        MaximumSize = wrap ? new Size(440, 0) : Size.Empty,
        Margin = new Padding(0, 3, 0, 3),
    };

    /// Botão só com glifo (barra de ações de cartões da biblioteca).
    public static System.Windows.Forms.Button Glyph(string glyph, string tip, Action click, ToolTip tips)
    {
        var b = new System.Windows.Forms.Button
        {
            Text = glyph,
            Font = Icons.Font(14),
            FlatStyle = FlatStyle.Flat,
            Size = new Size(28, 26),
            Margin = new Padding(0),
            Cursor = Cursors.Hand,
            TabStop = false,
            ForeColor = Color.FromArgb(50, 50, 55),
        };
        b.FlatAppearance.BorderSize = 0;
        b.FlatAppearance.MouseOverBackColor = Color.FromArgb(225, 225, 230);
        b.Click += (_, _) => click();
        tips.SetToolTip(b, tip);
        return b;
    }

    public static System.Windows.Forms.Button Button(string text, Action click, string? glyph = null)
    {
        var b = new System.Windows.Forms.Button
        {
            Text = text,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Padding = new Padding(6, 1, 6, 1),
            Margin = new Padding(0, 0, 6, 0),
            UseVisualStyleBackColor = true,
        };
        b.Click += (_, _) => click();
        return b;
    }

    public static string SaveDialog(string fileName, string filter)
    {
        using var d = new SaveFileDialog { FileName = fileName, Filter = filter, OverwritePrompt = true };
        return d.ShowDialog() == DialogResult.OK ? d.FileName : "";
    }

    public static string FilterPng => L("Imagem PNG") + " (*.png)|*.png";
}
