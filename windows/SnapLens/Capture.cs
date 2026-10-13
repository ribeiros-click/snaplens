using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

namespace SnapLens;

/// Captura de tela com GDI (BitBlt). O app é Per-Monitor DPI aware: coordenadas em pixels físicos.
public static class Capture
{
    public static Screen ScreenUnderMouse() => Screen.FromPoint(Cursor.Position);

    public static Bitmap? ScreenImage(Screen screen)
    {
        try
        {
            var b = screen.Bounds;
            var bmp = new Bitmap(b.Width, b.Height, PixelFormat.Format32bppPArgb);
            using (var g = Graphics.FromImage(bmp))
            {
                var dst = g.GetHdc();
                var src = GetDC(IntPtr.Zero);
                try
                {
                    // CAPTUREBLT inclui janelas em camadas (menus, tooltips, apps com transparência).
                    if (!BitBlt(dst, 0, 0, b.Width, b.Height, src, b.Left, b.Top, 0x00CC0020 | 0x40000000))
                        throw new InvalidOperationException("BitBlt falhou");
                }
                finally { ReleaseDC(IntPtr.Zero, src); g.ReleaseHdc(dst); }
            }
            return bmp;
        }
        catch (Exception e)
        {
            Trace.Log("captura falhou: " + e.Message);
            return null;
        }
    }

    [System.Runtime.InteropServices.DllImport("gdi32.dll")] private static extern bool BitBlt(IntPtr hdc, int x, int y, int w, int h, IntPtr src, int sx, int sy, int rop);
    [System.Runtime.InteropServices.DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr hwnd);
    [System.Runtime.InteropServices.DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr hwnd, IntPtr dc);
}

/// Monta várias imagens em uma só, empilhadas verticalmente com espaçamento de 1 cm.
public static class Composer
{
    /// 1 cm em pixels na densidade da tela principal (96 dpi lógicos × escala do Windows).
    public static int GapPixels
    {
        get
        {
            using var g = Graphics.FromHwnd(IntPtr.Zero);
            return (int)Math.Round(37.8 * g.DpiX / 96.0);
        }
    }

    public static byte[]? Stack(IEnumerable<string> paths)
    {
        var images = paths.Select(Images.Load).Where(i => i != null).Cast<Bitmap>().ToList();
        try
        {
            if (images.Count == 0) return null;
            int gap = GapPixels;
            int width = images.Max(i => i.Width);
            int height = images.Sum(i => i.Height) + gap * (images.Count - 1);
            using var outImg = new Bitmap(width, height, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(outImg))
            {
                g.Clear(Color.White);
                g.InterpolationMode = InterpolationMode.NearestNeighbor;
                int y = 0;
                foreach (var img in images)
                {
                    g.DrawImage(img, new Rectangle(0, y, img.Width, img.Height));
                    y += img.Height + gap;
                }
            }
            return Images.ToPng(outImg);
        }
        finally { images.ForEach(i => i.Dispose()); }
    }
}
