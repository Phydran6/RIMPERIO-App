// ---------------------------------------------------------------------------
// Datei:        scripts/store/StoreGraphics.cs
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.22.14.00.00
// Beschreibung: Grafiken für den Google Play Store aus dem Logo und den
//               Handy-Screenshots: App-Symbol 512², Vorstellungsgrafik
//               1024×500, Screenshots für Telefon / 7"- / 10"-Tablet.
//               Persönliche Daten in Screenshots werden vorher
//               unwiederbringlich weichgezeichnet (Redact).
//               Wird von make_store_graphics.ps1 per Add-Type geladen —
//               reines .NET (System.Drawing), kein Python/ImageMagick nötig.
// ---------------------------------------------------------------------------
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Runtime.InteropServices;

public static class StoreGraphics {
    static Color Gold = Color.FromArgb(222, 184, 92);
    static Color Bg = Color.FromArgb(3, 11, 26);

    static Bitmap Scale(Image src, int w, int h, Rectangle r, WrapMode wrap) {
        var b = new Bitmap(Math.Max(1, w), Math.Max(1, h), PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(b)) {
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            using (var ia = new ImageAttributes()) {
                ia.SetWrapMode(wrap);
                g.DrawImage(src, new Rectangle(0, 0, b.Width, b.Height), r.X, r.Y, r.Width, r.Height, GraphicsUnit.Pixel, ia);
            }
        }
        return b;
    }

    // Rechtecke [x1,y1,x2,y2, …] in Pixeln des Original-Screenshots stark
    // weichzeichnen. Verkleinern auf ~1/28 zerstört den Text — er lässt sich
    // daraus nicht zurückrechnen.
    public static Bitmap Redact(string path, int[] rects) {
        var img = new Bitmap(path);
        var b = new Bitmap(img.Width, img.Height, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(b)) {
            g.DrawImage(img, 0, 0, img.Width, img.Height);
            for (int i = 0; i + 3 < rects.Length; i += 4) {
                int x1 = Math.Max(0, rects[i] - 6), y1 = Math.Max(0, rects[i + 1] - 6);
                int x2 = Math.Min(img.Width, rects[i + 2] + 6), y2 = Math.Min(img.Height, rects[i + 3] + 6);
                var r = new Rectangle(x1, y1, x2 - x1, y2 - y1);
                // auf ~1/28 verkleinern (Text unwiederbringlich), weich zurückskalieren
                using (var tiny = Scale(b, Math.Max(2, r.Width / 28), Math.Max(2, r.Height / 28), r, WrapMode.TileFlipXY))
                using (var up = Scale(tiny, r.Width, r.Height, new Rectangle(0, 0, tiny.Width, tiny.Height), WrapMode.TileFlipXY)) {
                    g.SetClip(r);
                    g.DrawImage(up, r.X, r.Y);
                    g.ResetClip();
                }
            }
        }
        img.Dispose();
        return b;
    }

    // App-Symbol 512×512 für den Store-Eintrag (ohne Transparenz)
    public static void Icon(string logoPath, string dst) {
        using (var s = Image.FromFile(logoPath))
        using (var scaled = Scale(s, 512, 512, new Rectangle(0, 0, s.Width, s.Height), WrapMode.TileFlipXY))
        using (var o = new Bitmap(512, 512, PixelFormat.Format24bppRgb)) {
            using (var g = Graphics.FromImage(o)) { g.Clear(Bg); g.DrawImage(scaled, 0, 0); }
            o.Save(dst, ImageFormat.Png);
        }
    }

    static byte[] Bytes(Bitmap b) {
        var d = b.LockBits(new Rectangle(0, 0, b.Width, b.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        var a = new byte[d.Stride * b.Height]; Marshal.Copy(d.Scan0, a, 0, a.Length); b.UnlockBits(d); return a;
    }

    // Vorstellungsgrafik 1024×500: Logo mittig, weicher Übergang in die Textur
    public static void Feature(string logoPath, string dst) {
        const int W = 1024, H = 500;
        using (var s = Image.FromFile(logoPath))
        using (var bg = Background(s, W, H)) {
            var crop = new Rectangle(20, 70, 984, 860); // Logo ohne runde Ecken
            int fh = H + 20, fw = (int)Math.Round(crop.Width * (double)fh / crop.Height);
            using (var fg = Scale(s, fw, fh, crop, WrapMode.TileFlipXY)) {
                int ox = (W - fw) / 2, oy = (H - fh) / 2;
                var bb = Bytes(bg); var fb = Bytes(fg);
                for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) {
                    int fx = x - ox, fy = y - oy;
                    if (fx < 0 || fy < 0 || fx >= fw || fy >= fh) continue;
                    int i = (y * W + x) * 4, j = (fy * fw + fx) * 4;
                    double ex = (fx - fw / 2.0) / (fw / 2.0), ey = (fy - fh / 2.0) / (fh / 2.0);
                    double d = Math.Sqrt(ex * ex * 0.92 + ey * ey * 0.35);
                    double a = d < 0.80 ? 1.0 : d > 1.0 ? 0.0 : 1.0 - (d - 0.80) / 0.20;
                    a = a * a * (3 - 2 * a) * fb[j + 3] / 255.0;
                    for (int c = 0; c < 3; c++) bb[i + c] = (byte)(bb[i + c] * (1 - a) + fb[j + c] * a);
                }
                using (var o32 = new Bitmap(W, H, PixelFormat.Format32bppArgb)) {
                    var dd = o32.LockBits(new Rectangle(0, 0, W, H), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
                    Marshal.Copy(bb, 0, dd.Scan0, bb.Length); o32.UnlockBits(dd);
                    Save(o32, dst);
                }
            }
        }
    }

    // Hintergrund: goldfreier Streifen der Logo-Textur, weich + Vignette
    static Bitmap Background(Image logo, int W, int H) {
        var strip = new Rectangle(260, 12, 500, 78); // goldfreie Textur
        var outp = new Bitmap(W, H, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(outp))
        using (var tiny = Scale(logo, 16, 8, strip, WrapMode.TileFlipXY))
        using (var smooth = Scale(tiny, W, H, new Rectangle(0, 0, 16, 8), WrapMode.TileFlipXY))
        using (var tex = Scale(logo, W, H, strip, WrapMode.TileFlipXY)) {
            g.Clear(Bg);
            g.DrawImage(smooth, 0, 0);
            var cm = new ColorMatrix(); cm.Matrix33 = 0.45f;
            using (var ia = new ImageAttributes()) {
                ia.SetColorMatrix(cm);
                g.DrawImage(tex, new Rectangle(0, 0, W, H), 0, 0, W, H, GraphicsUnit.Pixel, ia);
            }
            using (var dark = new SolidBrush(Color.FromArgb(70, 0, 0, 0))) g.FillRectangle(dark, 0, 0, W, H);
            using (var path = new GraphicsPath()) {
                path.AddEllipse(-W * 0.35f, -H * 0.35f, W * 1.7f, H * 1.7f);
                using (var pg = new PathGradientBrush(path)) {
                    pg.CenterColor = Color.FromArgb(0, 0, 0, 0);
                    pg.SurroundColors = new[] { Color.FromArgb(150, 0, 0, 0) };
                    g.FillRectangle(pg, 0, 0, W, H);
                }
            }
        }
        return outp;
    }

    static GraphicsPath Rounded(RectangleF r, float rad) {
        var p = new GraphicsPath(); float d = rad * 2;
        p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure(); return p;
    }

    static void DrawShot(Graphics g, Bitmap shot, RectangleF r) {
        float rad = r.Width * 0.06f;
        for (int i = 6; i >= 1; i--) {
            using (var sp = Rounded(new RectangleF(r.X - i * 2, r.Y - i * 2 + 10, r.Width + i * 4, r.Height + i * 4), rad + i * 2))
            using (var sb = new SolidBrush(Color.FromArgb(18, 0, 0, 0))) g.FillPath(sb, sp);
        }
        using (var p = Rounded(r, rad)) {
            g.SetClip(p);
            g.DrawImage(shot, r);
            g.ResetClip();
            using (var pen = new Pen(Gold, Math.Max(3f, r.Width / 160f))) g.DrawPath(pen, p);
        }
    }

    static void Caption(Graphics g, string text, RectangleF r, float size) {
        using (var f = new Font("Segoe UI Semibold", size, FontStyle.Regular, GraphicsUnit.Pixel))
        using (var br = new SolidBrush(Gold))
        using (var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center }) {
            g.DrawString(text, f, br, r, sf);
        }
    }

    static Graphics G(Bitmap b) {
        var g = Graphics.FromImage(b);
        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
        g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
        return g;
    }

    static void Save(Bitmap b, string path) {
        using (var o = new Bitmap(b.Width, b.Height, PixelFormat.Format24bppRgb)) {
            using (var g = Graphics.FromImage(o)) g.DrawImage(b, 0, 0, b.Width, b.Height);
            o.Save(path, ImageFormat.Png);
        }
    }

    // Hochformat (Telefon 1080x1920, 7"-Tablet 1200x1920): Text oben, Screenshot darunter
    public static void Portrait(string logoPath, Bitmap shot, string caption, int W, int H, string dst) {
        using (var logo = Image.FromFile(logoPath))
        using (var b = Background(logo, W, H))
        using (var g = G(b)) {
            float top = H * 0.145f;
            Caption(g, caption, new RectangleF(W * 0.06f, H * 0.02f, W * 0.88f, top), Math.Min(W, H * 0.5625f) * 0.062f);
            float sh = H - top - H * 0.04f, sw = sh * shot.Width / shot.Height;
            DrawShot(g, shot, new RectangleF((W - sw) / 2f, top, sw, sh));
            Save(b, dst);
        }
    }

    // Querformat (10"-Tablet 1920x1200): Wortmarke + Text links, Screenshot rechts
    public static void Landscape(string logoPath, string markPath, Bitmap shot, string caption, int W, int H, string dst) {
        using (var logo = Image.FromFile(logoPath))
        using (var markImg = Image.FromFile(markPath))
        using (var b = Background(logo, W, H))
        using (var g = G(b)) {
            float sh = H * 0.90f, sw = sh * shot.Width / shot.Height;
            float sx = W * 0.66f - sw / 2f;
            DrawShot(g, shot, new RectangleF(sx, (H - sh) / 2f, sw, sh));
            // komplettes Logo (transparente Ecken), links zentriert über dem Text
            float colX = W * 0.05f, colW = W * 0.36f;
            float ms = H * 0.46f, mx = colX + (colW - ms) / 2f, my = H * 0.14f;
            g.DrawImage(markImg, new RectangleF(mx, my, ms, ms));
            Caption(g, caption, new RectangleF(colX, my + ms + H * 0.03f, colW, H * 0.24f), W * 0.030f);
            Save(b, dst);
        }
    }
}
