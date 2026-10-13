using System.Drawing.Drawing2D;
using System.Drawing.Text;
using Microsoft.Win32;

namespace SnapLens;

/// Ícones: glifos da fonte de ícones do Windows (Segoe Fluent Icons no 11, Segoe MDL2 Assets no 10)
/// e alguns desenhados à mão (formas da barra de anotação, ícone da bandeja).
public static class Icons
{
    // Códigos presentes nas duas fontes.
    public const string Cancel = "", Link = "", Save = "", Copy = "", Undo = "",
        Pen = "", Delete = "", Play = "", Folder = "", Export = "", Settings = "",
        Check = "", Warning = "", Info = "", Video = "", Record = "", Eye = "",
        Globe = "", Search = "", Text = "", Sparkle = "", Clipboard = "", Translate = "",
        Download = "", Clear = "", Camera = "", Screen = "", Select = "";

    private static string? family;
    public static string Family => family ??= PickFamily();

    private static string PickFamily()
    {
        using var fonts = new InstalledFontCollection();
        var names = fonts.Families.Select(f => f.Name).ToHashSet();
        return names.Contains("Segoe Fluent Icons") ? "Segoe Fluent Icons" : "Segoe MDL2 Assets";
    }

    public static Font Font(float size) => new(Family, size, FontStyle.Regular, GraphicsUnit.Pixel);

    public static void DrawGlyph(Graphics g, string glyph, RectangleF r, Color color, float size)
    {
        using var f = Font(size);
        using var b = new SolidBrush(color);
        using var fmt = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
        g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
        g.DrawString(glyph, f, b, r, fmt);
    }

    public static bool TaskbarIsLight()
    {
        using var k = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        return k?.GetValue("SystemUsesLightTheme") is int v && v == 1;
    }

    public static bool AppsAreDark()
    {
        using var k = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        return k?.GetValue("AppsUseLightTheme") is int v && v == 0;
    }

    /// Ícone da bandeja: visor (cantos) monocromático; gravando = círculo vermelho.
    public static Icon Tray(bool recording, int size = 32)
    {
        using var bmp = new Bitmap(size, size);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            float s = size / 32f;
            var color = TaskbarIsLight() ? Color.FromArgb(30, 30, 30) : Color.White;
            using var pen = new Pen(color, 2.6f * s) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round };
            float a = 4 * s, b = 28 * s, l = 8 * s;
            g.DrawLines(pen, new[] { new PointF(a, a + l), new PointF(a, a), new PointF(a + l, a) });
            g.DrawLines(pen, new[] { new PointF(b - l, a), new PointF(b, a), new PointF(b, a + l) });
            g.DrawLines(pen, new[] { new PointF(b, b - l), new PointF(b, b), new PointF(b - l, b) });
            g.DrawLines(pen, new[] { new PointF(a + l, b), new PointF(a, b), new PointF(a, b - l) });
            if (recording)
            {
                using var red = new SolidBrush(Color.FromArgb(235, 59, 48));
                g.FillEllipse(red, 9 * s, 9 * s, 14 * s, 14 * s);
            }
            else
            {
                using var dot = new SolidBrush(color);
                g.FillEllipse(dot, 13 * s, 13 * s, 6 * s, 6 * s);
            }
        }
        var h = bmp.GetHicon();
        using var tmp = Icon.FromHandle(h);
        var icon = (Icon)tmp.Clone();
        DestroyIcon(h);
        return icon;
    }

    public static Icon App()
    {
        using var s = typeof(Icons).Assembly.GetManifestResourceStream("SnapLens.ico");
        return s != null ? new Icon(s) : SystemIcons.Application;
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")] private static extern bool DestroyIcon(IntPtr h);
}
