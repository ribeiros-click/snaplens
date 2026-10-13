using System.Drawing.Drawing2D;

namespace SnapLens;

/// Aviso flutuante no topo da tela (não rouba o foco), equivalente ao HUD do macOS.
public static class Toast
{
    private static ToastForm? current;

    public static void Dismiss()
    {
        current?.Close();
        current = null;
    }

    public static void Show(string message, string glyph = Icons.Check)
    {
        Trace.Log("toast: " + message);
        current?.Close();
        var f = new ToastForm(message, glyph);
        current = f;
        f.FormClosed += (_, _) => { if (current == f) current = null; };
        f.ShowToast();
    }

    private sealed class ToastForm : Form
    {
        private readonly string message, glyph;
        private readonly System.Windows.Forms.Timer timer = new() { Interval = 15 };
        private DateTime shownAt;
        private readonly Font font;
        private readonly bool dark = Icons.AppsAreDark();

        public ToastForm(string message, string glyph)
        {
            this.message = message;
            this.glyph = glyph;
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            TopMost = true;
            StartPosition = FormStartPosition.Manual;
            BackColor = dark ? Color.FromArgb(44, 44, 46) : Color.FromArgb(250, 250, 250);
            AutoScaleMode = AutoScaleMode.None;
            Opacity = 0;
            float scale = DeviceDpi / 96f;
            font = new Font("Segoe UI Semibold", 13.5f * scale, GraphicsUnit.Pixel);
            var screen = Screen.FromPoint(Cursor.Position).WorkingArea;
            int maxText = (int)(380 * scale);
            var size = TextRenderer.MeasureText(message, font, new Size(maxText, 0), TextFormatFlags.WordBreak);
            int h = Math.Max((int)(44 * scale), size.Height + (int)(22 * scale));
            int w = size.Width + (int)(62 * scale);
            Bounds = new Rectangle(screen.Left + (screen.Width - w) / 2, screen.Top + (int)(24 * scale), w, Math.Min(h, (int)(110 * scale)));
            Region = new Region(RoundedRect(new Rectangle(0, 0, Width, Height), (int)(12 * scale)));
            timer.Tick += Tick;
            Click += (_, _) => Close();
        }

        protected override bool ShowWithoutActivation => true;

        protected override CreateParams CreateParams
        {
            get
            {
                var cp = base.CreateParams;
                cp.ExStyle |= 0x08000000 /* NOACTIVATE */ | 0x00000080 /* TOOLWINDOW */ | 0x00000008 /* TOPMOST */;
                return cp;
            }
        }

        public void ShowToast()
        {
            shownAt = DateTime.Now;
            Show();
            timer.Start();
        }

        private void Tick(object? s, EventArgs e)
        {
            var t = (DateTime.Now - shownAt).TotalSeconds;
            if (t < 0.15) Opacity = t / 0.15;
            else if (t < 2.4) Opacity = 1;
            else if (t < 2.7) Opacity = 1 - (t - 2.4) / 0.3;
            else { timer.Stop(); Close(); }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            float scale = DeviceDpi / 96f;
            using (var pen = new Pen(dark ? Color.FromArgb(70, 70, 74) : Color.FromArgb(215, 215, 215)))
                g.DrawPath(pen, RoundedRect(new Rectangle(0, 0, Width - 1, Height - 1), (int)(12 * scale)));
            var accent = glyph == Icons.Warning ? Color.FromArgb(255, 159, 10) : Color.FromArgb(10, 132, 255);
            Icons.DrawGlyph(g, glyph, new RectangleF(10 * scale, 0, 28 * scale, Height), accent, 16 * scale);
            var r = new Rectangle((int)(44 * scale), 0, Width - (int)(56 * scale), Height);
            TextRenderer.DrawText(g, message, font, r, dark ? Color.White : Color.FromArgb(28, 28, 30),
                TextFormatFlags.VerticalCenter | TextFormatFlags.WordBreak | TextFormatFlags.EndEllipsis);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) { timer.Dispose(); font.Dispose(); }
            base.Dispose(disposing);
        }
    }

    public static GraphicsPath RoundedRect(Rectangle r, int radius)
    {
        var p = new GraphicsPath();
        int d = radius * 2;
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }
}
