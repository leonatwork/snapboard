using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace Snapboard
{
    public class SnippingOverlay : Form
    {
        private Bitmap? screenBitmap;
        private Point startPoint;
        private Point currentPoint;
        private bool isSelecting = false;
        public Bitmap? SelectedImage { get; private set; }

        public SnippingOverlay()
        {
            this.DoubleBuffered = true;
            this.FormBorderStyle = FormBorderStyle.None;
            this.StartPosition = FormStartPosition.Manual;
            this.ShowInTaskbar = false;
            this.TopMost = true;
            this.Cursor = Cursors.Cross;

            // Cover all screens (VirtualScreen)
            Rectangle bounds = SystemInformation.VirtualScreen;
            this.Bounds = bounds;

            CaptureScreen(bounds);
        }

        private void CaptureScreen(Rectangle bounds)
        {
            screenBitmap = new Bitmap(bounds.Width, bounds.Height);
            using (Graphics g = Graphics.FromImage(screenBitmap))
            {
                g.CopyFromScreen(bounds.Location, Point.Empty, bounds.Size);
            }
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left)
            {
                isSelecting = true;
                startPoint = e.Location;
                currentPoint = e.Location;
                Invalidate();
            }
            else if (e.Button == MouseButtons.Right)
            {
                Cancel();
            }
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            if (isSelecting)
            {
                currentPoint = e.Location;
                Invalidate();
            }
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            if (isSelecting)
            {
                isSelecting = false;
                Rectangle rect = GetSelectionRect();

                if (rect.Width > 5 && rect.Height > 5 && screenBitmap != null)
                {
                    Bitmap crop = new Bitmap(rect.Width, rect.Height);
                    using (Graphics g = Graphics.FromImage(crop))
                    {
                        g.DrawImage(screenBitmap, new Rectangle(0, 0, crop.Width, crop.Height), rect, GraphicsUnit.Pixel);
                    }
                    SelectedImage = crop;
                    this.DialogResult = DialogResult.OK;
                }
                else
                {
                    Cancel();
                }
                Close();
            }
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Escape)
            {
                Cancel();
            }
        }

        private void Cancel()
        {
            SelectedImage = null;
            this.DialogResult = DialogResult.Cancel;
            Close();
        }

        private Rectangle GetSelectionRect()
        {
            int x = Math.Min(startPoint.X, currentPoint.X);
            int y = Math.Min(startPoint.Y, currentPoint.Y);
            int w = Math.Abs(currentPoint.X - startPoint.X);
            int h = Math.Abs(currentPoint.Y - startPoint.Y);
            return new Rectangle(x, y, w, h);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            if (screenBitmap == null) return;

            Graphics g = e.Graphics;
            g.DrawImage(screenBitmap, 0, 0);

            // Darken entire background
            using (SolidBrush darkBrush = new SolidBrush(Color.FromArgb(100, 0, 0, 0)))
            {
                g.FillRectangle(darkBrush, this.ClientRectangle);
            }

            if (isSelecting)
            {
                Rectangle rect = GetSelectionRect();
                if (rect.Width > 0 && rect.Height > 0)
                {
                    // Draw clear selected region
                    g.DrawImage(screenBitmap, rect, rect, GraphicsUnit.Pixel);

                    // Draw border around selection
                    using (Pen borderPen = new Pen(Color.FromArgb(0, 122, 255), 2))
                    {
                        borderPen.DashStyle = DashStyle.Solid;
                        g.DrawRectangle(borderPen, rect);
                    }

                    // Dimension label
                    string dimText = $"{rect.Width} × {rect.Height} px";
                    using (Font font = new Font("Segoe UI", 9, FontStyle.Bold))
                    using (SolidBrush bgBrush = new SolidBrush(Color.FromArgb(180, 0, 0, 0)))
                    using (SolidBrush textBrush = new SolidBrush(Color.White))
                    {
                        SizeF size = g.MeasureString(dimText, font);
                        Point textPt = new Point(rect.X, Math.Max(0, rect.Y - (int)size.Height - 6));
                        g.FillRectangle(bgBrush, textPt.X, textPt.Y, size.Width + 8, size.Height + 4);
                        g.DrawString(dimText, font, textBrush, textPt.X + 4, textPt.Y + 2);
                    }
                }
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                screenBitmap?.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
