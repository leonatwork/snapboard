using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Media;
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

        private Panel canvasPanel;
        private ToolStrip mainToolbar;

        public EditorForm(Bitmap image)
        {
            this.baseImage = new Bitmap(image);
            this.DoubleBuffered = true;
            this.Text = "Snapboard Editor";
            this.StartPosition = FormStartPosition.CenterScreen;
            this.Size = new Size(Math.Max(850, baseImage.Width + 60), Math.Max(600, baseImage.Height + 120));
            this.Icon = SystemIcons.Application;

            InitializeComponents();
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
            var undoBtn = new ToolStripButton("↩ Undo", null, (s, e) => Undo());
            undoBtn.ShortcutKeys = Keys.Control | Keys.Z;
            mainToolbar.Items.Add(undoBtn);

            var redoBtn = new ToolStripButton("↪ Redo", null, (s, e) => Redo());
            redoBtn.ShortcutKeys = Keys.Control | Keys.Y;
            mainToolbar.Items.Add(redoBtn);

            mainToolbar.Items.Add(new ToolStripSeparator());

            // Actions
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
                g.DrawImage(baseImage, 0, 0);

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
                Clipboard.SetImage(finalBmp);
                SystemSounds.Asterisk.Play();
            }
            this.Close();
        }

        private void SaveToFile()
        {
            using (SaveFileDialog sfd = new SaveFileDialog())
            {
                sfd.Filter = "PNG Image (*.png)|*.png|JPEG Image (*.jpg)|*.jpg";
                sfd.FileName = $"Snapboard_{DateTime.Now:yyyyMMdd_HHmmss}.png";
                if (sfd.ShowDialog() == DialogResult.OK)
                {
                    using (Bitmap finalBmp = RenderFinalImage())
                    {
                        finalBmp.Save(sfd.FileName, ImageFormat.Png);
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

            public CanvasPanel(EditorForm form)
            {
                this.form = form;
                this.DoubleBuffered = true;
                this.BackColor = Color.FromArgb(30, 30, 30);
                this.AutoScroll = true;
            }

            protected override void OnMouseDown(MouseEventArgs e)
            {
                if (e.Button == MouseButtons.Left)
                {
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
                    form.FinishDrawing();
                }
            }

            private Point ScreenToImagePoint(Point pt)
            {
                int imgX = (this.Width - form.baseImage.Width) / 2;
                int imgY = (this.Height - form.baseImage.Height) / 2;
                return new Point(pt.X - imgX, pt.Y - imgY);
            }

            protected override void OnPaint(PaintEventArgs e)
            {
                Graphics g = e.Graphics;
                g.SmoothingMode = SmoothingMode.AntiAlias;

                int imgX = (this.Width - form.baseImage.Width) / 2;
                int imgY = (this.Height - form.baseImage.Height) / 2;

                g.DrawImage(form.baseImage, imgX, imgY);

                g.TranslateTransform(imgX, imgY);

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

                g.ResetTransform();
            }
        }
    }
}
