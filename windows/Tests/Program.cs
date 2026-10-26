using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Snapboard;

namespace Snapboard.Tests;

// Dependency-free regression runner. Run on Windows with the .NET 8 SDK.
internal static class RegressionTests
{
    [STAThread]
    private static int Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        if (args.Length == 2 && args[0] == "--verify-annotations")
        {
            try { AnnotationExports(args[1]); PixelationPreview(); return 0; }
            catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
        }
        var tests = new (string Name, Action Run)[]
        {
            ("Clipboard lock: three attempts and two 100 ms intervals", ClipboardLocked),
            ("Clipboard recovers on retry and stops immediately", ClipboardRecovers),
            ("Unexpected clipboard exceptions are not swallowed", ClipboardUnexpectedError),
            ("Both capture paths share a gate, reset after cancel/error", CaptureReentry),
            ("PNG/JPEG filters produce actual signatures and full dimensions", ExportFormats),
            ("Window bounds respect small and negative-origin working areas", WindowBounds),
            ("Fit and scrolled 100% coordinates reach all image corners", ViewCoordinates),
            ("Large editor fits screen, scrolls, and exports annotations at full size", LargeEditor),
            ("Completed pixelation matches export, caches, and follows undo/redo", PixelationPreview),
            ("All-tool exports stay identical to the frozen pre-fix renderer", () => AnnotationExports(null))
        };
        int failed = 0;
        foreach (var test in tests)
        {
            try { test.Run(); Console.WriteLine($"PASS {test.Name}"); }
            catch (Exception ex) { failed++; Console.Error.WriteLine($"FAIL {test.Name}: {ex}"); }
        }
        return failed == 0 ? 0 : 1;
    }

    private static void ClipboardLocked()
    {
        using var image = new Bitmap(1, 1);
        int attempts = 0;
        var delays = new List<int>();
        bool copied = ClipboardRetry.TrySetImage(image, _ =>
        {
            attempts++;
            throw new ExternalException("Clipboard locked");
        }, delays.Add);
        Equal(false, copied);
        Equal(3, attempts);
        Equal("100,100", string.Join(",", delays));
    }

    private static void ClipboardRecovers()
    {
        using var image = new Bitmap(1, 1);
        for (int succeedsOn = 1; succeedsOn <= 3; succeedsOn++)
        {
            int attempts = 0, delays = 0;
            Equal(true, ClipboardRetry.TrySetImage(image, _ =>
            {
                if (++attempts < succeedsOn) throw new ExternalException();
            }, _ => delays++));
            Equal(succeedsOn, attempts);
            Equal(succeedsOn - 1, delays);
        }
    }

    private static void ClipboardUnexpectedError()
    {
        using var image = new Bitmap(1, 1);
        Throws<InvalidOperationException>(() => ClipboardRetry.TrySetImage(image,
            _ => throw new InvalidOperationException(), _ => throw new Exception("Must not retry")));
    }

    private static void CaptureReentry()
    {
        var gate = new CaptureGate();
        int overlays = 0;
        Equal(true, gate.TryRun(() =>
        {
            overlays++;
            Equal(false, gate.TryRun(() => overlays++));
            Equal(false, gate.TryRun(() => overlays++));
        }));
        Equal(1, overlays);
        Equal(true, gate.TryRun(() => overlays++));
        Throws<InvalidOperationException>(() => gate.TryRun(() => throw new InvalidOperationException()));
        Equal(true, gate.TryRun(() => overlays++));
        Equal(3, overlays);
    }

    private static void ExportFormats()
    {
        using var image = new Bitmap(31, 17);
        using (var g = Graphics.FromImage(image)) g.Clear(Color.Orange);
        Equal(90L, ImageExport.JpegQuality);
        foreach (int filter in new[] { 1, 2 })
        {
            using var stream = new MemoryStream();
            ImageExport.Save(image, stream, filter);
            byte[] bytes = stream.ToArray();
            Equal(filter == 2 ? "FF-D8" : "89-50-4E-47-0D-0A-1A-0A",
                BitConverter.ToString(bytes, 0, filter == 2 ? 2 : 8));
            stream.Position = 0;
            using var decoded = Image.FromStream(stream);
            Equal(image.Size, decoded.Size);
        }
    }

    private static void WindowBounds()
    {
        foreach (var area in new[] { new Rectangle(0, 0, 1920, 1040),
            new Rectangle(-1280, -200, 1280, 720), new Rectangle(100, 50, 640, 480) })
        {
            Rectangle bounds = EditorGeometry.GetWindowBounds(new Size(7680, 2160), area);
            Equal(true, area.Contains(bounds));
            Equal(area.Size, bounds.Size);
        }
        Equal(new Size(850, 600), EditorGeometry.GetWindowBounds(new Size(100, 100),
            new Rectangle(0, 0, 1920, 1040)).Size);
    }

    private static void ViewCoordinates()
    {
        var image = new Size(4000, 2000);
        var viewport = new Size(1000, 700);
        RectangleF fit = EditorGeometry.GetImageBounds(image, viewport, true, Point.Empty);
        Equal(new RectangleF(0, 100, 1000, 500), fit);
        Equal(Point.Empty, EditorGeometry.ScreenToImagePoint(new Point(0, 100), fit, image));
        Equal(new Point(3999, 0), EditorGeometry.ScreenToImagePoint(new Point(1000, 100), fit, image));
        Equal(new Point(0, 1999), EditorGeometry.ScreenToImagePoint(new Point(0, 600), fit, image));
        Equal(new Point(2000, 1000), EditorGeometry.ScreenToImagePoint(new Point(500, 350), fit, image));
        Equal(new Point(3999, 1999), EditorGeometry.ScreenToImagePoint(new Point(1000, 600), fit, image));
        RectangleF scrolled = EditorGeometry.GetImageBounds(image, viewport, false, new Point(-3000, -1300));
        Equal(new Point(3000, 1300), EditorGeometry.ScreenToImagePoint(Point.Empty, scrolled, image));
        Equal(new Point(3999, 1999), EditorGeometry.ScreenToImagePoint(new Point(999, 699), scrolled, image));
        Equal(Point.Empty, EditorGeometry.ScreenToImagePoint(new Point(-100, -100), fit, image));
        Equal(new RectangleF(450, 300, 100, 100), EditorGeometry.GetImageBounds(
            new Size(100, 100), viewport, true, Point.Empty));
    }

    private static void LargeEditor()
    {
        var area = Screen.FromPoint(Cursor.Position).WorkingArea;
        using var image = new Bitmap(Math.Max(4000, area.Width + 1000), Math.Max(2000, area.Height + 1000));
        using (var g = Graphics.FromImage(image)) g.Clear(Color.White);
        using var editor = new EditorForm(image);
        editor.Show();
        Application.DoEvents();
        Equal(true, Screen.FromControl(editor).WorkingArea.Contains(editor.Bounds));
        var canvas = (Panel)Field(editor, "canvasPanel");
        Equal(Size.Empty, canvas.AutoScrollMinSize);
        RectangleF fitted = EditorGeometry.GetImageBounds(image.Size, canvas.ClientSize, true, Point.Empty);
        Point fittedMouseStart = new Point((int)(fitted.X + fitted.Width / 4), (int)(fitted.Y + fitted.Height / 4));
        Point fittedStart = EditorGeometry.ScreenToImagePoint(fittedMouseStart, fitted, image.Size);
        DrawWithMouse(canvas, fittedMouseStart, new Point(fittedMouseStart.X + 30, fittedMouseStart.Y + 30));
        var toolbar = (ToolStrip)Field(editor, "mainToolbar");
        var zoom = (ToolStripButton)toolbar.Items["actualSizeButton"]!;
        zoom.PerformClick();
        Application.DoEvents();
        Equal(image.Size, canvas.AutoScrollMinSize);
        Equal(true, canvas.HorizontalScroll.Visible);
        Equal(true, canvas.VerticalScroll.Visible);
        canvas.AutoScrollPosition = new Point(image.Width, image.Height);
        Application.DoEvents();
        Equal(true, canvas.AutoScrollPosition.X < 0 && canvas.AutoScrollPosition.Y < 0);
        RectangleF view = EditorGeometry.GetImageBounds(image.Size, canvas.ClientSize, false, canvas.AutoScrollPosition);
        Point start = EditorGeometry.ScreenToImagePoint(new Point((int)view.Right - 40, (int)view.Bottom - 40), view, image.Size);
        DrawWithMouse(canvas, new Point((int)view.Right - 40, (int)view.Bottom - 40),
            new Point((int)view.Right - 10, (int)view.Bottom - 10));
        zoom.PerformClick();
        Application.DoEvents();
        Equal(Size.Empty, canvas.AutoScrollMinSize);
        using var exported = (Bitmap)typeof(EditorForm).GetMethod("RenderFinalImage", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(editor, null)!;
        Equal(image.Size, exported.Size);
        Equal(Color.FromArgb(255, 59, 48).ToArgb(), exported.GetPixel(start.X + 10, start.Y).ToArgb());
        Equal(Color.FromArgb(255, 59, 48).ToArgb(), exported.GetPixel(fittedStart.X + 10, fittedStart.Y).ToArgb());
        Equal(Color.White.ToArgb(), exported.GetPixel(10, 10).ToArgb());
        editor.Close();
    }

    private static object Field(object target, string name) => target.GetType()
        .GetField(name, BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(target)!;

    private static void PixelationPreview()
    {
        using var image = new Bitmap(400, 300);
        for (int y = 0; y < image.Height; y++)
            for (int x = 0; x < image.Width; x++)
                image.SetPixel(x, y, Color.FromArgb((x * 17 + y * 31) % 256, x % 256, y % 256));
        using var editor = new EditorForm(image);
        var items = (List<Annotation>)Field(editor, "annotations");
        // Overlap order matters: Windows samples the already pixelated result.
        items.Add(new Annotation { Tool = ToolType.Blur, Start = new Point(21, 32), End = new Point(250, 220) });
        items.Add(new Annotation { Tool = ToolType.Blur, Start = new Point(110, 90), End = new Point(380, 290) });
        items.Add(new Annotation { Tool = ToolType.Blur, Start = new Point(-10, -5), End = new Point(12, 15) });
        items.Add(new Annotation { Tool = ToolType.Blur, Start = new Point(1, 1), End = new Point(2, 2) });
        using var exported = (Bitmap)Invoke(editor, "RenderFinalImage")!;
        // This assertion uses only pre-existing APIs and fails on the original gray box.
        var canvas = (Panel)Field(editor, "canvasPanel");
        canvas.Dock = DockStyle.None;
        canvas.Size = image.Size;
        using var painted = new Bitmap(image.Width, image.Height);
        canvas.DrawToBitmap(painted, new Rectangle(Point.Empty, image.Size));
        AssertPixels(exported, painted);

        Bitmap Preview() => (Bitmap)Invoke(editor, "GetPixelatedPreview")!;
        Bitmap cached = Preview();
        AssertPixels(exported, cached);
        Equal(true, ReferenceEquals(cached, Preview()));

        Point previousEnd = items[0].End;
        items[0].End = new Point(180, 170);
        using (var movedExport = (Bitmap)Invoke(editor, "RenderFinalImage")!) AssertPixels(movedExport, Preview());
        items[0].End = previousEnd;
        cached = Preview();
        AssertPixels(exported, cached);

        // Independent pre-fix algorithm checks block size, clipping and overlap.
        using var legacy = LegacyAnnotationRenderer.Render(image, items.ToArray());
        AssertPixels(legacy, exported);

        Invoke(editor, "SaveUndo");
        items.Add(new Annotation { Tool = ToolType.Rectangle, Start = new Point(10, 10),
            End = new Point(50, 50), Color = Color.Red, LineWidth = 4 });
        Equal(true, ReferenceEquals(cached, Preview()));
        Invoke(editor, "Undo");
        AssertPixels(exported, Preview());
        Invoke(editor, "SaveUndo");
        ((List<Annotation>)Field(editor, "annotations")).Clear();
        AssertPixels(image, Preview());
        Invoke(editor, "Undo");
        AssertPixels(exported, Preview());
        Invoke(editor, "Redo");
        AssertPixels(image, Preview());
    }

    private static object? Invoke(object target, string name) => target.GetType()
        .GetMethod(name, BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(target, null);

    private static void AnnotationExports(string? outputDirectory)
    {
        if (outputDirectory != null) Directory.CreateDirectory(outputDirectory);
        foreach (var size in new[] { new Size(400, 300), new Size(3000, 2000) })
        {
            using var image = new Bitmap(size.Width, size.Height);
            using (var g = Graphics.FromImage(image))
            {
                g.Clear(Color.White);
                for (int y = 0; y < size.Height; y += 6)
                    for (int x = 0; x < size.Width; x += 6)
                    {
                        using var brush = new SolidBrush(Color.FromArgb((x * 17 + y * 31) % 180,
                            (x * 7) % 180, (y * 13) % 180));
                        g.FillRectangle(brush, x, y, 3, 3);
                    }
                using var font = new Font("Segoe UI", Math.Max(12, size.Width / 100), FontStyle.Bold);
                g.DrawString("Account 1234", font, Brushes.Black, size.Width * 0.3f, size.Height * 0.5f);
            }
            using var editor = new EditorForm(image);
            var items = (List<Annotation>)Field(editor, "annotations");
            foreach (int width in new[] { 2, 4, 7 })
                foreach (ToolType tool in Enum.GetValues<ToolType>())
                {
                    items.Clear();
                    var item = new Annotation { Tool = tool, Start = new Point(size.Width / 5, size.Height * 3 / 10),
                        End = new Point(size.Width * 7 / 10, size.Height * 3 / 4),
                        Color = Color.FromArgb(255, 59, 48), LineWidth = width, Text = "Private 1234", StepNumber = 12 };
                    item.Points.AddRange(new[] { item.Start, new Point(size.Width * 2 / 5, size.Height * 3 / 5), item.End });
                    items.Add(item);
                    using var before = LegacyAnnotationRenderer.Render(image, items.ToArray());
                    using var after = (Bitmap)Invoke(editor, "RenderFinalImage")!;
                    string name = $"{size.Width}x{size.Height}-{tool}-{width}";
                    if (outputDirectory != null)
                    {
                        before.Save(Path.Combine(outputDirectory, name + "-before.png"), System.Drawing.Imaging.ImageFormat.Png);
                        after.Save(Path.Combine(outputDirectory, name + "-export.png"), System.Drawing.Imaging.ImageFormat.Png);
                    }
                    AssertPixels(before, after);
                    if (tool == ToolType.Blur)
                    {
                        Bitmap preview = (Bitmap)Invoke(editor, "GetPixelatedPreview")!;
                        if (outputDirectory != null)
                            preview.Save(Path.Combine(outputDirectory, name + "-preview.png"), System.Drawing.Imaging.ImageFormat.Png);
                        AssertPixels(after, preview);
                        // Actual fitted paint must equal the equally fitted exported bitmap.
                        var canvas = (Panel)Field(editor, "canvasPanel");
                        canvas.Dock = DockStyle.None;
                        canvas.Size = new Size(200, 150);
                        using var painted = new Bitmap(canvas.Width, canvas.Height);
                        canvas.DrawToBitmap(painted, new Rectangle(Point.Empty, canvas.Size));
                        using var fittedExport = new Bitmap(canvas.Width, canvas.Height);
                        using (var g = Graphics.FromImage(fittedExport))
                        {
                            g.Clear(Color.FromArgb(30, 30, 30));
                            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                            RectangleF bounds = EditorGeometry.GetImageBounds(image.Size, canvas.ClientSize, true, Point.Empty);
                            g.SetClip(bounds, System.Drawing.Drawing2D.CombineMode.Intersect);
                            g.DrawImage(after, bounds, new RectangleF(PointF.Empty, image.Size), GraphicsUnit.Pixel);
                        }
                        if (outputDirectory != null)
                            painted.Save(Path.Combine(outputDirectory, name + "-preview-fitted.png"), System.Drawing.Imaging.ImageFormat.Png);
                        AssertPixels(fittedExport, painted);
                    }
                    Console.WriteLine($"PASS {name}: export unchanged");
                }
        }
    }

    private static void AssertPixels(Bitmap expected, Bitmap actual)
    {
        Equal(expected.Size, actual.Size);
        var rect = new Rectangle(Point.Empty, expected.Size);
        var a = expected.LockBits(rect, System.Drawing.Imaging.ImageLockMode.ReadOnly, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        try
        {
            var b = actual.LockBits(rect, System.Drawing.Imaging.ImageLockMode.ReadOnly, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
            try
            {
                var rowA = new byte[expected.Width * 4];
                var rowB = new byte[rowA.Length];
                for (int y = 0; y < expected.Height; y++)
                {
                    Marshal.Copy(IntPtr.Add(a.Scan0, y * a.Stride), rowA, 0, rowA.Length);
                    Marshal.Copy(IntPtr.Add(b.Scan0, y * b.Stride), rowB, 0, rowB.Length);
                    for (int i = 0; i < rowA.Length; i++)
                        if (rowA[i] != rowB[i]) throw new Exception($"Pixel mismatch at {i / 4},{y}");
                }
            }
            finally { actual.UnlockBits(b); }
        }
        finally { expected.UnlockBits(a); }
    }

    private static void DrawWithMouse(Panel canvas, Point start, Point end)
    {
        foreach (var entry in new[] { ("OnMouseDown", start), ("OnMouseMove", end), ("OnMouseUp", end) })
            canvas.GetType().GetMethod(entry.Item1, BindingFlags.NonPublic | BindingFlags.Instance)!
                .Invoke(canvas, new object[] { new MouseEventArgs(MouseButtons.Left, 1, entry.Item2.X, entry.Item2.Y, 0) });
    }

    private static void Equal<T>(T expected, T actual)
    {
        if (!Equals(expected, actual)) throw new Exception($"Expected {expected}; got {actual}");
    }

    private static void Throws<T>(Action action) where T : Exception
    {
        try { action(); }
        catch (T) { return; }
        throw new Exception($"Expected {typeof(T).Name}");
    }
}
