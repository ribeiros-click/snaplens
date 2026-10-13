using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using static SnapLens.Loc;

namespace SnapLens;

public enum ShotAction { copy, save, ocr, describe, share }

public enum Tool { rect, ellipse, line, arrow, pen, text }

public sealed class Annotation
{
    public Tool Tool;
    public Color Color;
    public PointF Start, End;
    public List<PointF> Points = new();
    public string Text = "";
}

/// Tela congelada para seleção de área + anotações (estilo Lightshot).
public sealed class OverlayForm : Form
{
    public static OverlayForm? Current { get; private set; }

    private readonly Bitmap clean, dimmed;
    private readonly ShotAction? autoAction;
    private readonly Action<ShotAction, byte[]> onFinish;
    private readonly float s; // escala de DPI desta tela

    private Rectangle? selection;
    public bool HasSelection => selection != null;
    private int? idleCountdown;
    private readonly List<Annotation> annotations = new();
    private Tool? tool;
    private Color color = Palette[0];
    private static readonly Color[] Palette =
    {
        Color.FromArgb(255, 59, 48), Color.FromArgb(255, 149, 0), Color.FromArgb(255, 204, 0), Color.FromArgb(52, 199, 89),
        Color.FromArgb(0, 122, 255), Color.White, Color.Black,
    };

    private enum Mode { Idle, Creating, Moving, Resizing, Drawing }
    private enum Grip { TL, T, TR, R, BR, B, BL, L }
    private Mode mode = Mode.Idle;
    private Point dragOrigin;
    private Grip dragHandle;

    private sealed class Button
    {
        public RectangleF Rect;
        public string Tip = "";
        public Action Click = () => { };
        public Action<Graphics, RectangleF, Color> Draw = (_, _, _) => { };
        public Func<bool> Active = () => false;
    }
    private readonly List<Button> toolbar = new();
    private RectangleF toolbarRect;
    private bool toolbarVisible;
    private Button? hover;
    private RectangleF cancelRect;

    private readonly System.Windows.Forms.Timer watchdog = new() { Interval = 500 };
    private DateTime lastActivity = DateTime.Now;
    private TextBox? textField;
    private bool finished;

    public OverlayForm(Screen screen, Bitmap image, ShotAction? autoAction, Action<ShotAction, byte[]> onFinish)
    {
        clean = image;
        this.autoAction = autoAction;
        this.onFinish = onFinish;
        dimmed = new Bitmap(image.Width, image.Height, PixelFormat.Format32bppPArgb);
        using (var g = Graphics.FromImage(dimmed))
        {
            g.DrawImageUnscaled(image, 0, 0);
            using var dim = new SolidBrush(Color.FromArgb(115, 0, 0, 0));
            g.FillRectangle(dim, 0, 0, image.Width, image.Height);
        }

        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        AutoScaleMode = AutoScaleMode.None;
        ShowInTaskbar = false;
        TopMost = true;
        KeyPreview = true;
        Bounds = screen.Bounds;
        Cursor = Cursors.Cross;
        BackColor = Color.Black;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.Opaque, true);
        s = GetDpiForScreen(screen) / 96f;

        watchdog.Tick += (_, _) => Watchdog();
    }

    private static float GetDpiForScreen(Screen screen)
    {
        var hmon = MonitorFromPoint(new POINT { X = screen.Bounds.Left + 1, Y = screen.Bounds.Top + 1 }, 2);
        return GetDpiForMonitor(hmon, 0, out uint dx, out _) == 0 ? dx : 96;
    }

    public static void Present(Screen screen, Bitmap image, ShotAction? autoAction, Action<ShotAction, byte[]> onFinish)
    {
        Trace.Log($"present: screen={screen.Bounds} image={image.Width}x{image.Height} auto={autoAction}");
        CloseAll(); // nunca empilha dois overlays
        var f = new OverlayForm(screen, image, autoAction, onFinish);
        Current = f;
        f.Show();
        f.Bounds = screen.Bounds; // reafirma após eventual troca de DPI ao criar a janela
        f.Activate();
        SetForegroundWindow(f.Handle);
        f.lastActivity = DateTime.Now;
        f.watchdog.Start();
    }

    /// Fecha qualquer overlay aberto. É a garantia final contra "tela presa".
    public static void CloseAll()
    {
        var c = Current;
        Current = null;
        if (c != null && !c.IsDisposed) { Trace.Log("overlay: fechando"); c.Dismiss(); }
        foreach (var f in Application.OpenForms.OfType<OverlayForm>().ToList()) f.Dismiss();
    }

    public static bool AnyVisible => Application.OpenForms.OfType<OverlayForm>().Any(f => f.Visible);

    private void Dismiss()
    {
        finished = true;
        watchdog.Stop();
        if (!IsDisposed) Close();
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        if (Current == this) Current = null;
        watchdog.Dispose();
        clean.Dispose();
        dimmed.Dispose();
        base.OnFormClosed(e);
    }

    private void Watchdog()
    {
        // Sem seleção: 10 s sem mexer o mouse ou teclar encerra a captura. Com seleção: 60 s.
        var idle = (DateTime.Now - lastActivity).TotalSeconds;
        double limit = HasSelection ? 60 : 10;
        int? countdown = HasSelection ? null : Math.Max(0, (int)Math.Ceiling(limit - idle));
        if (countdown != idleCountdown) { idleCountdown = countdown; Invalidate(); }
        if (idle > limit) { Trace.Log($"overlay: inatividade {limit}s"); Dismiss(); }
    }

    private void Touch() => lastActivity = DateTime.Now;

    // MARK: Desenho

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.CompositingMode = CompositingMode.SourceCopy;
        g.InterpolationMode = InterpolationMode.NearestNeighbor;
        g.DrawImage(dimmed, e.ClipRectangle, e.ClipRectangle, GraphicsUnit.Pixel);
        if (selection is Rectangle sel)
        {
            g.DrawImage(clean, sel, sel, GraphicsUnit.Pixel);
        }
        g.CompositingMode = CompositingMode.SourceOver;
        g.SmoothingMode = SmoothingMode.AntiAlias;

        DrawPill(g, "✕  " + L("Cancelar") + "  (Esc)", new PointF(Width / 2f, 16 * s), centered: true, out cancelRect);

        if (selection is not Rectangle r)
        {
            var timer = idleCountdown is int c ? L(" · fecha sozinho em %@s", c) : "";
            DrawPill(g, L("Arraste para selecionar · botão direito refaz · Esc cancela") + timer, new PointF(Width / 2f, 64 * s), true, out _);
            return;
        }

        var state = g.Save();
        g.SetClip(r);
        foreach (var a in annotations) DrawAnnotation(g, a, s);
        g.Restore(state);

        using (var border = new Pen(Color.FromArgb(0, 122, 255), 1))
            g.DrawRectangle(border, r.X, r.Y, r.Width - 1, r.Height - 1);
        foreach (Grip h in Enum.GetValues<Grip>())
        {
            var p = PointOf(h, r);
            var hr = new RectangleF(p.X - 4 * s, p.Y - 4 * s, 8 * s, 8 * s);
            g.FillEllipse(Brushes.White, hr);
            using var pen = new Pen(Color.FromArgb(0, 122, 255), 1);
            g.DrawEllipse(pen, hr);
        }
        DrawPill(g, $"{r.Width} × {r.Height}", new PointF(r.Left, Math.Max(r.Top - 26 * s, 4)), false, out _);

        if (toolbarVisible) DrawToolbar(g);
    }

    private void DrawPill(Graphics g, string text, PointF p, bool centered, out RectangleF box)
    {
        using var font = new Font("Segoe UI Semibold", 12.5f * s, GraphicsUnit.Pixel);
        var size = TextRenderer.MeasureText(g, text, font);
        box = new RectangleF(centered ? p.X - size.Width / 2f - 10 * s : p.X, p.Y, size.Width + 20 * s, size.Height + 8 * s);
        using (var path = Toast.RoundedRect(Rectangle.Round(box), (int)(7 * s)))
        using (var bg = new SolidBrush(Color.FromArgb(185, 0, 0, 0)))
            g.FillPath(bg, path);
        TextRenderer.DrawText(g, text, font, Rectangle.Round(box), Color.White,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
    }

    public static void DrawAnnotation(Graphics g, Annotation a, float s)
    {
        g.SmoothingMode = SmoothingMode.AntiAlias;
        if (a.Tool == Tool.text)
        {
            using var font = new Font("Segoe UI", 20 * s, FontStyle.Bold, GraphicsUnit.Pixel);
            TextRenderer.DrawText(g, a.Text, font, Point.Round(new PointF(a.Start.X, a.Start.Y)), a.Color, TextFormatFlags.NoPadding);
            return;
        }
        using var pen = new Pen(a.Color, 3 * s) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round };
        var rect = RectangleF.FromLTRB(Math.Min(a.Start.X, a.End.X), Math.Min(a.Start.Y, a.End.Y), Math.Max(a.Start.X, a.End.X), Math.Max(a.Start.Y, a.End.Y));
        switch (a.Tool)
        {
            case Tool.rect: g.DrawRectangle(pen, rect.X, rect.Y, rect.Width, rect.Height); break;
            case Tool.ellipse: g.DrawEllipse(pen, rect); break;
            case Tool.line: g.DrawLine(pen, a.Start, a.End); break;
            case Tool.arrow:
            {
                double angle = Math.Atan2(a.End.Y - a.Start.Y, a.End.X - a.Start.X);
                float len = 18 * s; double spread = Math.PI / 7;
                var p1 = new PointF(a.End.X - len * (float)Math.Cos(angle - spread), a.End.Y - len * (float)Math.Sin(angle - spread));
                var p2 = new PointF(a.End.X - len * (float)Math.Cos(angle + spread), a.End.Y - len * (float)Math.Sin(angle + spread));
                // A haste termina na base da ponta, para a ponta ficar nítida.
                var baseMid = new PointF((p1.X + p2.X) / 2, (p1.Y + p2.Y) / 2);
                if (Math.Abs(a.End.X - a.Start.X) + Math.Abs(a.End.Y - a.Start.Y) > len) g.DrawLine(pen, a.Start, baseMid);
                using var b = new SolidBrush(a.Color);
                g.FillPolygon(b, new[] { a.End, p1, p2 });
                break;
            }
            case Tool.pen:
                if (a.Points.Count > 1) g.DrawLines(pen, a.Points.ToArray());
                break;
        }
    }

    // MARK: Geometria

    private static PointF PointOf(Grip h, Rectangle r) => h switch
    {
        Grip.TL => new(r.Left, r.Top),
        Grip.T => new(r.Left + r.Width / 2f, r.Top),
        Grip.TR => new(r.Right, r.Top),
        Grip.R => new(r.Right, r.Top + r.Height / 2f),
        Grip.BR => new(r.Right, r.Bottom),
        Grip.B => new(r.Left + r.Width / 2f, r.Bottom),
        Grip.BL => new(r.Left, r.Bottom),
        _ => new(r.Left, r.Top + r.Height / 2f),
    };

    private Grip? HandleAt(Point p)
    {
        if (selection is not Rectangle r) return null;
        foreach (Grip h in Enum.GetValues<Grip>())
        {
            var q = PointOf(h, r);
            if (Math.Abs(q.X - p.X) <= 9 * s && Math.Abs(q.Y - p.Y) <= 9 * s) return h;
        }
        return null;
    }

    private Point Clamp(Point p) => new(Math.Clamp(p.X, 0, Width), Math.Clamp(p.Y, 0, Height));

    private static Rectangle RectOf(Point a, Point b) =>
        Rectangle.FromLTRB(Math.Min(a.X, b.X), Math.Min(a.Y, b.Y), Math.Max(a.X, b.X), Math.Max(a.Y, b.Y));

    private static Rectangle ResizeRect(Rectangle r, Grip h, Point p)
    {
        int minX = r.Left, maxX = r.Right, minY = r.Top, maxY = r.Bottom;
        switch (h)
        {
            case Grip.TL: minX = p.X; minY = p.Y; break;
            case Grip.T: minY = p.Y; break;
            case Grip.TR: maxX = p.X; minY = p.Y; break;
            case Grip.R: maxX = p.X; break;
            case Grip.BR: maxX = p.X; maxY = p.Y; break;
            case Grip.B: maxY = p.Y; break;
            case Grip.BL: minX = p.X; maxY = p.Y; break;
            case Grip.L: minX = p.X; break;
        }
        return Rectangle.FromLTRB(Math.Min(minX, maxX), Math.Min(minY, maxY), Math.Max(minX, maxX), Math.Max(minY, maxY));
    }

    // MARK: Mouse

    protected override void OnMouseDown(MouseEventArgs e)
    {
        Touch();
        var p = Clamp(e.Location);
        if (e.Button == MouseButtons.Right)
        {
            if (selection != null) ResetSelection(); else Cancel();
            return;
        }
        if (e.Button != MouseButtons.Left) return;
        Trace.Log($"mouseDown p={p} sel={selection} tool={tool} mode={mode}");

        if (cancelRect.Contains(p) && !(toolbarVisible && toolbarRect.Contains(p))) { Cancel(); return; }
        if (toolbarVisible && toolbarRect.Contains(p))
        {
            toolbar.FirstOrDefault(b => b.Rect.Contains(p))?.Click();
            Invalidate();
            return;
        }
        if (selection is Rectangle sel)
        {
            if (tool == Tool.text && sel.Contains(p)) { BeginText(p); return; }
            if (tool is Tool t && sel.Contains(p))
            {
                CommitText();
                annotations.Add(new Annotation { Tool = t, Color = color, Start = p, End = p, Points = { p } });
                mode = Mode.Drawing;
                return;
            }
            if (HandleAt(p) is Grip h) { mode = Mode.Resizing; dragHandle = h; toolbarVisible = false; Invalidate(); return; }
            if (sel.Contains(p)) { mode = Mode.Moving; dragOrigin = new Point(p.X - sel.X, p.Y - sel.Y); toolbarVisible = false; Invalidate(); return; }
        }
        CommitText();
        selection = null;
        annotations.Clear();
        toolbarVisible = false;
        mode = Mode.Creating;
        dragOrigin = p;
        Invalidate();
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        Touch();
        var p = Clamp(e.Location);
        if (e.Button != MouseButtons.Left || mode == Mode.Idle)
        {
            UpdateHover(p);
            return;
        }
        switch (mode)
        {
            case Mode.Creating:
                selection = RectOf(dragOrigin, p);
                break;
            case Mode.Moving when selection is Rectangle sel:
                int x = Math.Clamp(p.X - dragOrigin.X, 0, Width - sel.Width), y = Math.Clamp(p.Y - dragOrigin.Y, 0, Height - sel.Height);
                selection = new Rectangle(x, y, sel.Width, sel.Height);
                break;
            case Mode.Resizing when selection is Rectangle sel:
                selection = ResizeRect(sel, dragHandle, p);
                break;
            case Mode.Drawing when annotations.Count > 0:
                var a = annotations[^1];
                a.End = p;
                if (a.Tool == Tool.pen) a.Points.Add(p);
                break;
        }
        Invalidate();
    }

    private void UpdateHover(Point p)
    {
        var h = toolbarVisible && toolbarRect.Contains(p) ? toolbar.FirstOrDefault(b => b.Rect.Contains(p)) : null;
        bool overUi = h != null || (toolbarVisible && toolbarRect.Contains(p)) || cancelRect.Contains(p);
        Cursor = overUi ? Cursors.Hand
            : HandleAt(p) is Grip hd ? (hd is Grip.T or Grip.B ? Cursors.SizeNS : hd is Grip.L or Grip.R ? Cursors.SizeWE
                                         : hd is Grip.TL or Grip.BR ? Cursors.SizeNWSE : Cursors.SizeNESW)
            : selection is Rectangle sel && sel.Contains(p) && tool == null ? Cursors.SizeAll
            : tool == Tool.text && selection is Rectangle sel2 && sel2.Contains(p) ? Cursors.IBeam
            : Cursors.Cross;
        if (h != hover) { hover = h; Invalidate(Rectangle.Round(RectangleF.Inflate(toolbarRect, 4, 40 * s))); }
    }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        if (e.Button != MouseButtons.Left) return;
        Trace.Log($"mouseUp mode={mode} sel={selection}");
        var was = mode;
        mode = Mode.Idle;
        try
        {
            if (selection is not Rectangle sel) return;
            if (sel.Width < 4 || sel.Height < 4) { selection = null; return; }
            if (was == Mode.Drawing) return;
            if (was == Mode.Idle) return;
            if (autoAction is ShotAction auto) { Finish(auto); return; }
            ShowToolbar();
        }
        finally { if (!IsDisposed) Invalidate(); }
    }

    // MARK: Cancelamento

    public void HandleEscape()
    {
        Trace.Log($"handleEscape textField={textField != null}");
        if (textField != null) { textField.Text = ""; CommitText(); }
        else Cancel();
    }

    private void Cancel()
    {
        if (finished) return;
        Dismiss();
    }

    private void ResetSelection()
    {
        CommitText();
        selection = null;
        annotations.Clear();
        toolbarVisible = false;
        mode = Mode.Idle;
        Invalidate();
    }

    // MARK: Texto

    private void BeginText(Point p)
    {
        CommitText();
        var f = new TextBox
        {
            BorderStyle = BorderStyle.None,
            Font = new Font("Segoe UI", 20 * s, FontStyle.Bold, GraphicsUnit.Pixel),
            ForeColor = color,
            BackColor = color.GetBrightness() > 0.6 ? Color.FromArgb(40, 40, 40) : Color.FromArgb(245, 245, 245),
            PlaceholderText = L("Digite…"),
            Location = new Point(p.X, p.Y - (int)(4 * s)),
            Width = (int)(260 * s),
        };
        f.KeyDown += (_, e) =>
        {
            Touch();
            if (e.KeyCode == Keys.Enter) { e.SuppressKeyPress = true; CommitText(); }
            else if (e.KeyCode == Keys.Escape) { e.SuppressKeyPress = true; f.Text = ""; CommitText(); }
        };
        f.LostFocus += (_, _) => BeginInvoke(CommitText);
        Controls.Add(f);
        textField = f;
        f.Focus();
    }

    private void CommitText()
    {
        if (textField is not TextBox f) return;
        textField = null;
        var text = f.Text.Trim();
        if (text.Length > 0)
            annotations.Add(new Annotation { Tool = Tool.text, Color = color, Start = new PointF(f.Left, f.Top + 4 * s), Text = text });
        Controls.Remove(f);
        f.Dispose();
        if (!IsDisposed) { Focus(); Invalidate(); }
    }

    // MARK: Teclado

    protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
    {
        Touch();
        if (textField != null && textField.Focused && keyData != Keys.Escape) return base.ProcessCmdKey(ref msg, keyData);
        var key = keyData & Keys.KeyCode;
        bool ctrl = (keyData & Keys.Control) != 0, shift = (keyData & Keys.Shift) != 0;
        switch (key)
        {
            case Keys.Escape: HandleEscape(); return true;
            case Keys.Enter: if (selection != null) Finish(ShotAction.copy); return true;
            case Keys.Left or Keys.Right or Keys.Up or Keys.Down: Nudge(key, shift); return true;
            case Keys.Z when ctrl: Undo(); return true;
            case Keys.C when ctrl && selection != null: Finish(ShotAction.copy); return true;
            case Keys.S when ctrl && selection != null: Finish(ShotAction.save); return true;
        }
        return base.ProcessCmdKey(ref msg, keyData);
    }

    private void Nudge(Keys key, bool shift)
    {
        if (selection is not Rectangle sel) return;
        int step = shift ? 10 : 1;
        switch (key)
        {
            case Keys.Left: sel.X -= step; break;
            case Keys.Right: sel.X += step; break;
            case Keys.Down: sel.Y += step; break;
            default: sel.Y -= step; break;
        }
        sel.X = Math.Clamp(sel.X, 0, Width - sel.Width);
        sel.Y = Math.Clamp(sel.Y, 0, Height - sel.Height);
        selection = sel;
        if (toolbarVisible) LayoutToolbar();
        Invalidate();
    }

    private void Undo()
    {
        if (annotations.Count > 0) annotations.RemoveAt(annotations.Count - 1);
        Invalidate();
    }

    // MARK: Barra de ferramentas

    private void ShowToolbar()
    {
        if (toolbar.Count == 0) BuildToolbar();
        toolbarVisible = true;
        LayoutToolbar();
    }

    private void BuildToolbar()
    {
        foreach (var t in Enum.GetValues<Tool>())
        {
            var tt = t;
            toolbar.Add(new Button
            {
                Tip = ToolTitle(t),
                Click = () => tool = tool == tt ? null : tt,
                Active = () => tool == tt,
                Draw = (g, r, c) => DrawToolIcon(g, tt, r, c),
            });
        }
        toolbar.Add(new Button { Tip = "|" });
        foreach (var c in Palette)
        {
            var cc = c;
            toolbar.Add(new Button
            {
                Tip = "color",
                Click = () => { color = cc; tool ??= Tool.arrow; },
                Active = () => color == cc,
                Draw = (g, r, _) =>
                {
                    bool sel = color == cc;
                    float inset = sel ? 3 * s : 5 * s;
                    var dot = RectangleF.Inflate(r, -(r.Width - 18 * s) / 2 - (inset - 3 * s), -(r.Height - 18 * s) / 2 - (inset - 3 * s));
                    using var b = new SolidBrush(cc);
                    g.FillEllipse(b, dot);
                    using var o = new Pen(Color.FromArgb(150, 128, 128, 128), 1);
                    g.DrawEllipse(o, dot);
                    if (sel)
                    {
                        using var ring = new Pen(Color.FromArgb(10, 132, 255), 2 * s);
                        g.DrawEllipse(ring, RectangleF.Inflate(dot, 2.5f * s, 2.5f * s));
                    }
                },
            });
        }
        toolbar.Add(new Button { Tip = "|" });
        toolbar.Add(GlyphButton(Icons.Undo, L("Desfazer (Ctrl+Z)"), Undo));
        toolbar.Add(new Button { Tip = "|" });
        toolbar.Add(new Button { Tip = L("Descrever com IA"), Click = () => Finish(ShotAction.describe), Draw = DrawSparkles });
        toolbar.Add(new Button { Tip = L("Extrair texto (OCR)"), Click = () => Finish(ShotAction.ocr), Draw = DrawOcrIcon });
        toolbar.Add(GlyphButton(Icons.Link, L("Compartilhar por link público"), () => Finish(ShotAction.share)));
        toolbar.Add(GlyphButton(Icons.Save, L("Salvar (Ctrl+S)"), () => Finish(ShotAction.save)));
        toolbar.Add(GlyphButton(Icons.Copy, L("Copiar (Ctrl+C / Enter)"), () => Finish(ShotAction.copy)));
        toolbar.Add(new Button { Tip = L("Refazer seleção (botão direito)"), Click = ResetSelection, Draw = DrawDashedRect });
        toolbar.Add(GlyphButton(Icons.Cancel, L("Cancelar captura (Esc)"), Cancel));
    }

    private Button GlyphButton(string glyph, string tip, Action click) => new()
    {
        Tip = tip, Click = click, Draw = (g, r, c) => Icons.DrawGlyph(g, glyph, r, c, 16 * s),
    };

    private static string ToolTitle(Tool t) => t switch
    {
        Tool.rect => L("Retângulo"),
        Tool.ellipse => L("Elipse"),
        Tool.line => L("Linha"),
        Tool.arrow => L("Seta"),
        Tool.pen => L("Caneta"),
        _ => L("Texto"),
    };

    private void DrawToolIcon(Graphics g, Tool t, RectangleF r, Color c)
    {
        using var pen = new Pen(c, 1.7f * s) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round };
        var box = RectangleF.Inflate(r, -9 * s, -9 * s);
        switch (t)
        {
            case Tool.rect: g.DrawRectangle(pen, box.X, box.Y + 1.5f * s, box.Width, box.Height - 3 * s); break;
            case Tool.ellipse: g.DrawEllipse(pen, box); break;
            case Tool.line: g.DrawLine(pen, box.Left, box.Bottom, box.Right, box.Top); break;
            case Tool.arrow:
                g.DrawLine(pen, box.Left, box.Bottom, box.Right, box.Top);
                g.DrawLines(pen, new[] { new PointF(box.Right - 6 * s, box.Top), new PointF(box.Right, box.Top), new PointF(box.Right, box.Top + 6 * s) });
                break;
            case Tool.pen: Icons.DrawGlyph(g, Icons.Pen, r, c, 16 * s); break;
            case Tool.text:
                using (var f = new Font("Segoe UI", 15 * s, FontStyle.Bold, GraphicsUnit.Pixel))
                    TextRenderer.DrawText(g, "A", f, Rectangle.Round(r), c, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
                break;
        }
    }

    private void DrawSparkles(Graphics g, RectangleF r, Color c)
    {
        using var b = new SolidBrush(c);
        void Star(float cx, float cy, float rad)
        {
            float k = rad * 0.28f;
            g.FillPolygon(b, new[]
            {
                new PointF(cx, cy - rad), new PointF(cx + k, cy - k), new PointF(cx + rad, cy), new PointF(cx + k, cy + k),
                new PointF(cx, cy + rad), new PointF(cx - k, cy + k), new PointF(cx - rad, cy), new PointF(cx - k, cy - k),
            });
        }
        float mx = r.X + r.Width / 2, my = r.Y + r.Height / 2;
        Star(mx - 2 * s, my + 1.5f * s, 6.5f * s);
        Star(mx + 5 * s, my - 5 * s, 3.2f * s);
    }

    private void DrawOcrIcon(Graphics g, RectangleF r, Color c)
    {
        using var pen = new Pen(c, 1.6f * s) { StartCap = LineCap.Round, EndCap = LineCap.Round };
        var b = RectangleF.Inflate(r, -8.5f * s, -8.5f * s);
        float l = 4 * s;
        g.DrawLines(pen, new[] { new PointF(b.Left, b.Top + l), new PointF(b.Left, b.Top), new PointF(b.Left + l, b.Top) });
        g.DrawLines(pen, new[] { new PointF(b.Right - l, b.Top), new PointF(b.Right, b.Top), new PointF(b.Right, b.Top + l) });
        g.DrawLines(pen, new[] { new PointF(b.Right, b.Bottom - l), new PointF(b.Right, b.Bottom), new PointF(b.Right - l, b.Bottom) });
        g.DrawLines(pen, new[] { new PointF(b.Left + l, b.Bottom), new PointF(b.Left, b.Bottom), new PointF(b.Left, b.Bottom - l) });
        using var f = new Font("Segoe UI", 10.5f * s, FontStyle.Bold, GraphicsUnit.Pixel);
        TextRenderer.DrawText(g, "T", f, Rectangle.Round(r), c, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
    }

    private void DrawDashedRect(Graphics g, RectangleF r, Color c)
    {
        using var pen = new Pen(c, 1.5f * s) { DashStyle = DashStyle.Dash };
        var b = RectangleF.Inflate(r, -8.5f * s, -9.5f * s);
        g.DrawRectangle(pen, b.X, b.Y, b.Width, b.Height);
    }

    private void LayoutToolbar()
    {
        if (selection is not Rectangle sel) return;
        float bw = 32 * s, cw = 24 * s, sepW = 9 * s, h = 36 * s, pad = 8 * s;
        float width = pad * 2 + toolbar.Sum(b => b.Tip == "|" ? sepW : b.Tip == "color" ? cw : bw);
        float x = Math.Clamp(sel.Right - width, 8, Width - width - 8);
        float y = sel.Bottom + 10 * s;
        if (y + h > Height - 8) y = sel.Top - h - 10 * s;
        if (y < 8) y = sel.Bottom - h - 10 * s;
        toolbarRect = new RectangleF(x, y, width, h);
        float cx = x + pad;
        foreach (var b in toolbar)
        {
            float w = b.Tip == "|" ? sepW : b.Tip == "color" ? cw : bw;
            b.Rect = new RectangleF(cx, y + 2 * s, w, h - 4 * s);
            cx += w;
        }
    }

    private void DrawToolbar(Graphics g)
    {
        var dark = Color.FromArgb(242, 36, 36, 38);
        using (var path = Toast.RoundedRect(Rectangle.Round(toolbarRect), (int)(10 * s)))
        using (var bg = new SolidBrush(dark))
        using (var edge = new Pen(Color.FromArgb(70, 255, 255, 255)))
        {
            g.FillPath(bg, path);
            g.DrawPath(edge, path);
        }
        foreach (var b in toolbar)
        {
            if (b.Tip == "|")
            {
                using var sep = new Pen(Color.FromArgb(80, 255, 255, 255));
                float mx = b.Rect.X + b.Rect.Width / 2;
                g.DrawLine(sep, mx, b.Rect.Y + 7 * s, mx, b.Rect.Bottom - 7 * s);
                continue;
            }
            if (b == hover || (b.Active() && b.Tip != "color"))
            {
                using var path = Toast.RoundedRect(Rectangle.Round(RectangleF.Inflate(b.Rect, -1.5f * s, -1 * s)), (int)(6 * s));
                using var hb = new SolidBrush(b.Active() && b.Tip != "color" ? Color.FromArgb(10, 132, 255) : Color.FromArgb(60, 255, 255, 255));
                g.FillPath(hb, path);
            }
            b.Draw(g, b.Rect, Color.White);
        }
        if (hover != null && hover.Tip != "color")
        {
            float above = toolbarRect.Top - 34 * s;
            var at = above > 4 ? new PointF(hover.Rect.X + hover.Rect.Width / 2, above) : new PointF(hover.Rect.X + hover.Rect.Width / 2, toolbarRect.Bottom + 6 * s);
            DrawPill(g, hover.Tip, at, true, out _);
        }
    }

    // MARK: Saída

    private void Finish(ShotAction action)
    {
        if (finished) return;
        Trace.Log($"finish({action}) sel={selection} annotations={annotations.Count}");
        CommitText();
        var data = RenderSelection(annotated: action is not (ShotAction.ocr or ShotAction.describe));
        Dismiss();
        if (data != null) onFinish(action, data);
    }

    private byte[]? RenderSelection(bool annotated)
    {
        if (selection is not Rectangle sel || sel.Width <= 0 || sel.Height <= 0) return null;
        using var bmp = new Bitmap(sel.Width, sel.Height, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bmp))
        {
            g.DrawImage(clean, new Rectangle(0, 0, sel.Width, sel.Height), sel, GraphicsUnit.Pixel);
            if (annotated)
            {
                g.TranslateTransform(-sel.X, -sel.Y);
                foreach (var a in annotations) DrawAnnotation(g, a, s);
            }
        }
        return Images.ToPng(bmp);
    }

    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            cp.ExStyle |= 0x00000080; // TOOLWINDOW: fora do Alt+Tab
            return cp;
        }
    }

    [StructLayout(LayoutKind.Sequential)] private struct POINT { public int X, Y; }
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromPoint(POINT pt, uint flags);
    [DllImport("shcore.dll")] private static extern int GetDpiForMonitor(IntPtr hmonitor, int dpiType, out uint dpiX, out uint dpiY);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
}
