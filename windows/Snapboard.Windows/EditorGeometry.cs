using System;
using System.Drawing;

namespace Snapboard
{
    public static class EditorGeometry
    {
        public static Rectangle GetWindowBounds(Size image, Rectangle workingArea)
        {
            int width = (int)Math.Min(workingArea.Width, Math.Max(850L, (long)image.Width + 60));
            int height = (int)Math.Min(workingArea.Height, Math.Max(600L, (long)image.Height + 120));
            return new Rectangle(workingArea.X + (workingArea.Width - width) / 2,
                workingArea.Y + (workingArea.Height - height) / 2, width, height);
        }

        public static RectangleF GetImageBounds(Size image, Size viewport, bool fit, Point scrollPosition)
        {
            float scale = fit ? Math.Min(1f, Math.Min((float)Math.Max(1, viewport.Width) / image.Width,
                (float)Math.Max(1, viewport.Height) / image.Height)) : 1f;
            float width = image.Width * scale, height = image.Height * scale;
            return new RectangleF(Math.Max(0, (viewport.Width - width) / 2) + (fit ? 0 : scrollPosition.X),
                Math.Max(0, (viewport.Height - height) / 2) + (fit ? 0 : scrollPosition.Y), width, height);
        }

        public static Point ScreenToImagePoint(Point point, RectangleF imageBounds, Size image)
        {
            return new Point(Math.Clamp((int)Math.Floor((point.X - imageBounds.X) * image.Width / imageBounds.Width), 0, image.Width - 1),
                Math.Clamp((int)Math.Floor((point.Y - imageBounds.Y) * image.Height / imageBounds.Height), 0, image.Height - 1));
        }
    }
}
