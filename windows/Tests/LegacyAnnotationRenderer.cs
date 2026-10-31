using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using Snapboard;

namespace Snapboard.Tests;

// Frozen export oracle from origin/main 2306fc6. No calls to the production renderer.
internal static class LegacyAnnotationRenderer
{
    internal static Bitmap Render(Bitmap source, Annotation[] annotations)
    {
        var result = new Bitmap(source.Width, source.Height);
        using var g = Graphics.FromImage(result);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
        g.DrawImage(source, new Rectangle(Point.Empty, source.Size),
            new Rectangle(Point.Empty, source.Size), GraphicsUnit.Pixel);
        foreach (var item in annotations)
            if (item.Tool == ToolType.Blur) Blur(result, Rect(item.Start, item.End));
        foreach (var item in annotations)
            if (item.Tool != ToolType.Blur) Draw(g, item);
        return result;
    }

    private static Rectangle Rect(Point a, Point b) => new Rectangle(
        Math.Min(a.X, b.X), Math.Min(a.Y, b.Y), Math.Abs(b.X - a.X), Math.Abs(b.Y - a.Y));

    private static void Blur(Bitmap bmp, Rectangle rect)
    {
        rect.Intersect(new Rectangle(0, 0, bmp.Width, bmp.Height));
        if (rect.Width <= 2 || rect.Height <= 2) return;
        int pixelSize = Math.Max(8, Math.Min(rect.Width, rect.Height) / 10);
        for (int y = rect.Y; y < rect.Bottom; y += pixelSize)
            for (int x = rect.X; x < rect.Right; x += pixelSize)
            {
                int blockW = Math.Min(pixelSize, rect.Right - x);
                int blockH = Math.Min(pixelSize, rect.Bottom - y);
                Color avgColor = bmp.GetPixel(x + blockW / 2, y + blockH / 2);
                for (int by = 0; by < blockH; by++)
                    for (int bx = 0; bx < blockW; bx++) bmp.SetPixel(x + bx, y + by, avgColor);
            }
    }

    private static void Draw(Graphics g, Annotation item)
    {
        Rectangle rect = Rect(item.Start, item.End);
        using var pen = new Pen(item.Color, item.LineWidth);
        pen.StartCap = LineCap.Round;
        pen.EndCap = LineCap.Round;
        pen.LineJoin = LineJoin.Round;
        switch (item.Tool)
        {
            case ToolType.Rectangle:
                g.DrawRectangle(pen, rect);
                break;
            case ToolType.Circle:
                g.DrawEllipse(pen, rect);
                break;
            case ToolType.Arrow:
                pen.CustomEndCap = new AdjustableArrowCap(6, 6, true);
                g.DrawLine(pen, item.Start, item.End);
                break;
            case ToolType.Pen:
                if (item.Points.Count > 1) g.DrawLines(pen, item.Points.ToArray());
                break;
            case ToolType.Highlighter:
                using (var hlPen = new Pen(Color.FromArgb(100, item.Color), item.LineWidth * 3))
                    if (item.Points.Count > 1) g.DrawLines(hlPen, item.Points.ToArray());
                break;
            case ToolType.Text:
                using (var font = new Font("Segoe UI", 12, FontStyle.Bold))
                using (var bgBrush = new SolidBrush(Color.FromArgb(180, 0, 0, 0)))
                using (var textBrush = new SolidBrush(item.Color))
                {
                    SizeF size = g.MeasureString(item.Text, font);
                    g.FillRectangle(bgBrush, item.Start.X, item.Start.Y, size.Width + 8, size.Height + 4);
                    g.DrawString(item.Text, font, textBrush, item.Start.X + 4, item.Start.Y + 2);
                }
                break;
            case ToolType.StepNumber:
                int radius = 14;
                var badgeRect = new Rectangle(item.Start.X - radius, item.Start.Y - radius, radius * 2, radius * 2);
                using (var brush = new SolidBrush(item.Color))
                using (var font = new Font("Segoe UI", 10, FontStyle.Bold))
                {
                    g.FillEllipse(brush, badgeRect);
                    g.DrawEllipse(Pens.White, badgeRect);
                    string numStr = item.StepNumber.ToString();
                    SizeF size = g.MeasureString(numStr, font);
                    g.DrawString(numStr, font, Brushes.White,
                        badgeRect.X + (badgeRect.Width - size.Width) / 2 + 1,
                        badgeRect.Y + (badgeRect.Height - size.Height) / 2 + 1);
                }
                break;
        }
    }
}
