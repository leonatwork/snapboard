using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Media;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace Snapboard
{
    public enum ToolType
    {
        Rectangle,
        Circle,
        Arrow,
        Pen,
        Highlighter,
        Blur,
        Text,
        StepNumber
    }

    public class Annotation
    {
        public ToolType Tool { get; set; }
        public Point Start { get; set; }
        public Point End { get; set; }
        public List<Point> Points { get; set; } = new List<Point>();
        public Color Color { get; set; }
        public int LineWidth { get; set; }
        public string Text { get; set; } = "";
        public int StepNumber { get; set; } = 1;
    }

    public class EditorForm : Form
    {
        private Bitmap baseImage;
        private List<Annotation> annotations = new List<Annotation>();
        private Stack<List<Annotation>> undoStack = new Stack<List<Annotation>>();
        private Stack<List<Annotation>> redoStack = new Stack<List<Annotation>>();

        private ToolType currentTool = ToolType.Rectangle;
        private Color currentColor = Color.FromArgb(255, 59, 48); // Red
        private int currentLineWidth = 4;
        private int nextStepNumber = 1;
        private string currentText = "Hinweis";

        private Annotation? currentDraft;
        private bool isDrawing = false;

        private CanvasPanel canvasPanel = null!;
        private ToolStrip mainToolbar = null!;
        private bool isRecognizingText;
        private readonly Func<Bitmap, Task<IReadOnlyList<OcrTextLine>>>? recognizeText;
        private readonly Func<string, bool>? setClipboardText;
        private readonly Action<string>? presentOcrNotice;

        public EditorForm(Bitmap image, Func<Bitmap, Task<IReadOnlyList<OcrTextLine>>>? recognizeText = null,
            Func<string, bool>? setClipboardText = null, Action<string>? presentOcrNotice = null)
        {
            this.baseImage = new Bitmap(image);
            this.recognizeText = recognizeText;
            this.setClipboardText = setClipboardText;
            this.presentOcrNotice = presentOcrNotice;
            this.DoubleBuffered = true;
            this.KeyPreview = true;
            this.Text = "Snapboard Editor";
            this.StartPosition = FormStartPosition.Manual;
            this.Icon = SystemIcons.Application;

            InitializeComponents();
        }

        protected override void OnLoad(EventArgs e)
        {
            base.OnLoad(e);
            // Apply after WinForms' initial DPI scaling, using outer window bounds.
            this.Bounds = EditorGeometry.GetWindowBounds(baseImage.Size, Screen.FromPoint(Cursor.Position).WorkingArea);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) baseImage.Dispose();
            base.Dispose(disposing);
        }

        private void InitializeComponents()
        {
            mainToolbar = new ToolStrip
            {
                GripStyle = ToolStripGripStyle.Hidden,
                ImageScalingSize = new Size(20, 20),
                Padding = new Padding(6)
            };

            // Tools
            AddToolButton("⬜ Rechteck", ToolType.Rectangle);
            AddToolButton("⭕ Kreis", ToolType.Circle);
            AddToolButton("➡️ Pfeil", ToolType.Arrow);
            AddToolButton("✏️ Stift", ToolType.Pen);
            AddToolButton("🖍️ Marker", ToolType.Highlighter);
            AddToolButton("🌫️ Blur", ToolType.Blur);
            AddToolButton("🔤 Text", ToolType.Text);
            AddToolButton("① Schritt", ToolType.StepNumber);

            mainToolbar.Items.Add(new ToolStripSeparator());

            // Colors
            AddColorButton(Color.FromArgb(255, 59, 48), "Rot");
            AddColorButton(Color.FromArgb(255, 149, 0), "Orange");
            AddColorButton(Color.FromArgb(255, 204, 0), "Gelb");
            AddColorButton(Color.FromArgb(52, 199, 89), "Grün");
            AddColorButton(Color.FromArgb(0, 122, 255), "Blau");
            AddColorButton(Color.FromArgb(175, 82, 222), "Lila");
            AddColorButton(Color.Black, "Schwarz");
            AddColorButton(Color.White, "Weiß");

            mainToolbar.Items.Add(new ToolStripSeparator());

            // Undo / Redo
            var undoBtn = new ToolStripButton("↩ Undo", null, (s, e) => Undo()) { ToolTipText = "Rückgängig (Strg+Z)" };
            mainToolbar.Items.Add(undoBtn);

            var redoBtn = new ToolStripButton("↪ Redo", null, (s, e) => Redo()) { ToolTipText = "Wiederholen (Strg+Y)" };
            mainToolbar.Items.Add(redoBtn);

            mainToolbar.Items.Add(new ToolStripSeparator());

            // Actions
            var actualSizeButton = new ToolStripButton("100 %")
            {
                Name = "actualSizeButton",
                CheckOnClick = true,
                ToolTipText = "Zwischen Einpassen und 100 % mit Scrollbalken umschalten"
            };
            actualSizeButton.CheckedChanged += (s, e) => canvasPanel.SetActualSize(actualSizeButton.Checked);
            mainToolbar.Items.Add(actualSizeButton);

            mainToolbar.Items.Add(new ToolStripButton("Text kopieren", null, async (s, e) => await CopyTextAsync())
            {
                Name = "copyTextButton",
                ToolTipText = "Text im bearbeiteten Bild lokal erkennen und als Klartext kopieren"
            });

            var copyBtn = new ToolStripButton("📋 In Zwischenablage kopieren (Strg+C)", null, (s, e) => CopyAndClose());
            copyBtn.Font = new Font(mainToolbar.Font, FontStyle.Bold);
            copyBtn.BackColor = Color.FromArgb(0, 122, 255);
            copyBtn.ForeColor = Color.White;
            mainToolbar.Items.Add(copyBtn);

            var saveBtn = new ToolStripButton("💾 Speichern unter... (Strg+S)", null, (s, e) => SaveToFile());
            mainToolbar.Items.Add(saveBtn);

            this.Controls.Add(mainToolbar);

            // Canvas Panel
            canvasPanel = new CanvasPanel(this);
            canvasPanel.Dock = DockStyle.Fill;
            this.Controls.Add(canvasPanel);
            canvasPanel.BringToFront();
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (e.Control && e.KeyCode == Keys.Z)
            {
                Undo();
                e.Handled = true;
            }
            else if (e.Control && e.KeyCode == Keys.Y)
            {
                Redo();
                e.Handled = true;
            }
            else if (e.Control && e.KeyCode == Keys.C)
            {
                CopyAndClose();
                e.Handled = true;
            }
            else if (e.Control && e.KeyCode == Keys.S)
            {
                SaveToFile();
                e.Handled = true;
            }
            else if (e.KeyCode == Keys.Escape)
            {
                this.Close();
                e.Handled = true;
            }
            base.OnKeyDown(e);
        }

        private void AddToolButton(string label, ToolType tool)
        {
            var btn = new ToolStripButton(label);
            btn.CheckOnClick = true;
            btn.Checked = (currentTool == tool);
            btn.Click += (s, e) =>
            {
                foreach (ToolStripItem item in mainToolbar.Items)
                {
                    if (item is ToolStripButton tb && tb.Tag is ToolType)
                        tb.Checked = false;
                }
                btn.Checked = true;
                currentTool = tool;

                if (tool == ToolType.Text)
                {
                    string input = Microsoft.VisualBasic.Interaction.InputBox("Text für Hinweisfeld eingeben:", "Text eingeben", currentText);
                    if (!string.IsNullOrWhiteSpace(input))
                    {
                        currentText = input;
                    }
                }
            };
            btn.Tag = tool;
            mainToolbar.Items.Add(btn);
        }

        private void AddColorButton(Color c, string name)
        {
            Bitmap bmp = new Bitmap(16, 16);
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.FillEllipse(new SolidBrush(c), 1, 1, 14, 14);
                g.DrawEllipse(Pens.Gray, 1, 1, 14, 14);
            }
            var btn = new ToolStripButton(name, bmp, (s, e) =>
            {
                currentColor = c;
            });
            mainToolbar.Items.Add(btn);
        }

        public void StartDrawing(Point pt)
        {
            isDrawing = true;
            if (currentTool == ToolType.Pen || currentTool == ToolType.Highlighter)
            {
                currentDraft = new Annotation
                {
                    Tool = currentTool,
                    Start = pt,
                    End = pt,
                    Points = new List<Point> { pt },
                    Color = currentColor,
                    LineWidth = currentLineWidth
                };
            }
            else if (currentTool == ToolType.Text)
            {
                SaveUndo();
                annotations.Add(new Annotation
                {
                    Tool = ToolType.Text,
                    Start = pt,
                    End = pt,
                    Color = currentColor,
                    LineWidth = currentLineWidth,
                    Text = currentText
                });
                isDrawing = false;
                canvasPanel.Invalidate();
            }
            else if (currentTool == ToolType.StepNumber)
            {
                SaveUndo();
                annotations.Add(new Annotation
                {
                    Tool = ToolType.StepNumber,
                    Start = pt,
                    End = pt,
                    Color = currentColor,
                    LineWidth = currentLineWidth,
                    StepNumber = nextStepNumber++
                });
                isDrawing = false;
                canvasPanel.Invalidate();
            }
            else
            {
                currentDraft = new Annotation
                {
                    Tool = currentTool,
                    Start = pt,
                    End = pt,
                    Color = currentColor,
                    LineWidth = currentLineWidth
                };
            }
        }

        public void UpdateDrawing(Point pt)
        {
            if (!isDrawing || currentDraft == null) return;
            currentDraft.End = pt;
            if (currentDraft.Tool == ToolType.Pen || currentDraft.Tool == ToolType.Highlighter)
            {
                currentDraft.Points.Add(pt);
            }
            canvasPanel.Invalidate();
        }

        public void FinishDrawing()
        {
            if (!isDrawing) return;
            isDrawing = false;
            if (currentDraft != null)
            {
                SaveUndo();
                annotations.Add(currentDraft);
                currentDraft = null;
                canvasPanel.Invalidate();
            }
        }

        private void SaveUndo()
        {
            undoStack.Push(new List<Annotation>(annotations));
            redoStack.Clear();
        }

        private void Undo()
        {
            if (undoStack.Count > 0)
            {
                redoStack.Push(new List<Annotation>(annotations));
                annotations = undoStack.Pop();
                canvasPanel.Invalidate();
            }
        }

        private void Redo()
        {
            if (redoStack.Count > 0)
            {
                undoStack.Push(new List<Annotation>(annotations));
                annotations = redoStack.Pop();
                canvasPanel.Invalidate();
            }
        }

        private Bitmap RenderFinalImage()
        {
            Bitmap result = new Bitmap(baseImage.Width, baseImage.Height);
            using (Graphics g = Graphics.FromImage(result))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.DrawImage(baseImage, new Rectangle(Point.Empty, baseImage.Size),
                    new Rectangle(Point.Empty, baseImage.Size), GraphicsUnit.Pixel);

                // Apply blur items
                foreach (var item in annotations)
                {
                    if (item.Tool == ToolType.Blur)
                    {
                        ApplyBlur(result, GetRect(item.Start, item.End));
                    }
                }

                // Draw vector annotations
                foreach (var item in annotations)
                {
                    if (item.Tool != ToolType.Blur)
                    {
                        DrawAnnotation(g, item);
                    }
                }
            }
            return result;
        }

        private void ApplyBlur(Bitmap bmp, Rectangle rect)
        {
            rect.Intersect(new Rectangle(0, 0, bmp.Width, bmp.Height));
            if (rect.Width <= 2 || rect.Height <= 2) return;

            int pixelSize = Math.Max(8, Math.Min(rect.Width, rect.Height) / 10);
            for (int y = rect.Y; y < rect.Bottom; y += pixelSize)
            {
                for (int x = rect.X; x < rect.Right; x += pixelSize)
                {
                    int blockW = Math.Min(pixelSize, rect.Right - x);
                    int blockH = Math.Min(pixelSize, rect.Bottom - y);
                    Color avgColor = bmp.GetPixel(x + blockW / 2, y + blockH / 2);

                    for (int by = 0; by < blockH; by++)
                    {
                        for (int bx = 0; bx < blockW; bx++)
                        {
                            bmp.SetPixel(x + bx, y + by, avgColor);
                        }
                    }
                }
            }
        }

        private void CopyAndClose()
        {
            using (Bitmap finalBmp = RenderFinalImage())
            {
                if (!ClipboardRetry.TrySetImage(finalBmp))
                {
                    MessageBox.Show(this,
                        "Die Zwischenablage ist belegt. Das Bild konnte nach 3 Versuchen nicht kopiert werden. Ihre Anmerkungen bleiben erhalten. Bitte versuchen Sie es erneut.",
                        "Snapboard", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }
                SystemSounds.Asterisk.Play();
            }
            this.Close();
        }

        public async Task CopyTextAsync()
        {
            if (isRecognizingText) return;
            isRecognizingText = true;
            mainToolbar.Items["copyTextButton"]!.Enabled = false;
            try
            {
                using var rendered = RenderFinalImage();
                var redactions = annotations.Where(item => item.Tool == ToolType.Blur)
                    .Select(item => (RectangleF)GetRect(item.Start, item.End)).ToArray();
                await OcrService.CopyTextAsync(rendered, redactions, recognizeText, setClipboardText, presentOcrNotice);
            }
            finally
            {
                isRecognizingText = false;
                if (!IsDisposed) mainToolbar.Items["copyTextButton"]!.Enabled = true;
            }
        }

        private void SaveToFile()
        {
            using (SaveFileDialog sfd = new SaveFileDialog())
            {
                sfd.Filter = "PNG Image (*.png)|*.png|JPEG Image (*.jpg)|*.jpg";
                sfd.FileName = $"Snapboard_{DateTime.Now:yyyyMMdd_HHmmss}";
                sfd.DefaultExt = "png";
                sfd.AddExtension = true;
                if (sfd.ShowDialog(this) == DialogResult.OK)
                {
                    using (Bitmap finalBmp = RenderFinalImage())
                    {
                        using var destination = File.Create(sfd.FileName);
                        ImageExport.Save(finalBmp, destination, sfd.FilterIndex);
                    }
                }
            }
        }

        private static Rectangle GetRect(Point p1, Point p2)
        {
            return new Rectangle(
                Math.Min(p1.X, p2.X),
                Math.Min(p1.Y, p2.Y),
                Math.Abs(p2.X - p1.X),
                Math.Abs(p2.Y - p1.Y)
            );
        }

        private static void DrawAnnotation(Graphics g, Annotation item)
        {
            Rectangle rect = GetRect(item.Start, item.End);
            using (Pen pen = new Pen(item.Color, item.LineWidth))
            {
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
                        if (item.Points.Count > 1)
                            g.DrawLines(pen, item.Points.ToArray());
                        break;
                    case ToolType.Highlighter:
                        using (Pen hlPen = new Pen(Color.FromArgb(100, item.Color), item.LineWidth * 3))
                        {
                            if (item.Points.Count > 1)
                                g.DrawLines(hlPen, item.Points.ToArray());
                        }
                        break;
                    case ToolType.Text:
                        using (Font font = new Font("Segoe UI", 12, FontStyle.Bold))
                        using (SolidBrush bgBrush = new SolidBrush(Color.FromArgb(180, 0, 0, 0)))
                        using (SolidBrush textBrush = new SolidBrush(item.Color))
                        {
                            SizeF size = g.MeasureString(item.Text, font);
                            g.FillRectangle(bgBrush, item.Start.X, item.Start.Y, size.Width + 8, size.Height + 4);
                            g.DrawString(item.Text, font, textBrush, item.Start.X + 4, item.Start.Y + 2);
                        }
                        break;
                    case ToolType.StepNumber:
                        int radius = 14;
                        Rectangle badgeRect = new Rectangle(item.Start.X - radius, item.Start.Y - radius, radius * 2, radius * 2);
                        using (SolidBrush brush = new SolidBrush(item.Color))
                        using (Font font = new Font("Segoe UI", 10, FontStyle.Bold))
                        {
                            g.FillEllipse(brush, badgeRect);
                            g.DrawEllipse(Pens.White, badgeRect);

                            string numStr = item.StepNumber.ToString();
                            SizeF size = g.MeasureString(numStr, font);
                            g.DrawString(numStr, font, Brushes.White, badgeRect.X + (badgeRect.Width - size.Width) / 2 + 1, badgeRect.Y + (badgeRect.Height - size.Height) / 2 + 1);
                        }
                        break;
                }
            }
        }

        private class CanvasPanel : Panel
        {
            private EditorForm form;
            private bool actualSize;

            public CanvasPanel(EditorForm form)
            {
                this.form = form;
                this.DoubleBuffered = true;
                this.BackColor = Color.FromArgb(30, 30, 30);
                this.AutoScroll = true;
            }

            public void SetActualSize(bool value)
            {
                form.FinishDrawing();
                Capture = false;
                actualSize = value;
                AutoScrollPosition = Point.Empty;
                AutoScrollMinSize = value ? form.baseImage.Size : Size.Empty;
                Invalidate();
            }

            protected override void OnResize(EventArgs e)
            {
                base.OnResize(e);
                Invalidate();
            }

            protected override void OnScroll(ScrollEventArgs e)
            {
                base.OnScroll(e);
                Invalidate();
            }

            private RectangleF ImageBounds => EditorGeometry.GetImageBounds(form.baseImage.Size,
                ClientSize, !actualSize, AutoScrollPosition);

            protected override void OnMouseDown(MouseEventArgs e)
            {
                if (e.Button == MouseButtons.Left && ImageBounds.Contains(e.Location))
                {
                    Capture = true;
                    Point imgPt = ScreenToImagePoint(e.Location);
                    form.StartDrawing(imgPt);
                }
            }

            protected override void OnMouseMove(MouseEventArgs e)
            {
                Point imgPt = ScreenToImagePoint(e.Location);
                form.UpdateDrawing(imgPt);
            }

            protected override void OnMouseUp(MouseEventArgs e)
            {
                if (e.Button == MouseButtons.Left)
                {
                    form.UpdateDrawing(ScreenToImagePoint(e.Location));
                    form.FinishDrawing();
                    Capture = false;
                }
            }

            protected override void OnMouseCaptureChanged(EventArgs e)
            {
                base.OnMouseCaptureChanged(e);
                if (!Capture) form.FinishDrawing();
            }

            private Point ScreenToImagePoint(Point pt)
            {
                return EditorGeometry.ScreenToImagePoint(pt, ImageBounds, form.baseImage.Size);
            }

            protected override void OnPaint(PaintEventArgs e)
            {
                Graphics g = e.Graphics;
                g.SmoothingMode = SmoothingMode.AntiAlias;

                RectangleF bounds = ImageBounds;
                var state = g.Save();
                g.SetClip(bounds, CombineMode.Intersect);

                g.DrawImage(form.baseImage, bounds,
                    new RectangleF(PointF.Empty, form.baseImage.Size), GraphicsUnit.Pixel);

                g.TranslateTransform(bounds.X, bounds.Y);
                g.ScaleTransform(bounds.Width / form.baseImage.Width, bounds.Height / form.baseImage.Height);

                foreach (var item in form.annotations)
                {
                    if (item.Tool == ToolType.Blur)
                    {
                        Rectangle rect = GetRect(item.Start, item.End);
                        using (SolidBrush brush = new SolidBrush(Color.FromArgb(160, 120, 120, 120)))
                        using (Pen dashPen = new Pen(Color.White, 1) { DashStyle = DashStyle.Dash })
                        {
                            g.FillRectangle(brush, rect);
                            g.DrawRectangle(dashPen, rect);
                        }
                    }
                    else
                    {
                        DrawAnnotation(g, item);
                    }
                }

                if (form.currentDraft != null)
                {
                    if (form.currentDraft.Tool == ToolType.Blur)
                    {
                        Rectangle rect = GetRect(form.currentDraft.Start, form.currentDraft.End);
                        using (SolidBrush brush = new SolidBrush(Color.FromArgb(160, 120, 120, 120)))
                        using (Pen dashPen = new Pen(Color.White, 1) { DashStyle = DashStyle.Dash })
                        {
                            g.FillRectangle(brush, rect);
                            g.DrawRectangle(dashPen, rect);
                        }
                    }
                    else
                    {
                        DrawAnnotation(g, form.currentDraft);
                    }
                }

                g.Restore(state);
            }
        }
    }
}
