using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Threading.Tasks;
using Snapboard;

namespace Snapboard.Tests;

// Dependency-free regression runner. Run on Windows with the .NET 8 SDK.
internal static class RegressionTests
{
    [STAThread]
    private static int Main()
    {
        ApplicationConfiguration.Initialize();
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
            ("OCR reading order, newlines, and redaction exclusion", OcrReadingOrder),
            ("OCR capture gate stays closed across asynchronous recognition", OcrCaptureReentry),
            ("OCR empty, missing language, and errors preserve clipboard", OcrFailures),
            ("OCR text clipboard uses Unicode without an image and retries", OcrClipboard),
            ("Editor OCR receives rendered annotations, excludes redactions, stays open", EditorOcr)
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

    private static OcrTextLine OcrLine(string text, float x, float y) =>
        new OcrTextLine(text, new RectangleF(x, y, 20, 10));

    private static void OcrReadingOrder()
    {
        var lines = new[] { OcrLine("last", 0, 70), OcrLine("right", 40, 12),
            OcrLine("left", 0, 10), OcrLine("middle", 0, 40), OcrLine("  ", 0, 0) };
        Equal("left right\nmiddle\nlast", OcrTextLayout.PlainText(lines));
        Array.Reverse(lines);
        Equal("left right\nmiddle\nlast", OcrTextLayout.PlainText(lines));
        Equal("", OcrTextLayout.PlainText(Array.Empty<OcrTextLine>()));
        Equal("visible", OcrTextLayout.PlainText(new[] { OcrLine("secret", 0, 10), OcrLine("visible", 0, 40) },
            new[] { new RectangleF(10, 10, 10, 10) }));
    }

    private static void OcrFailures()
    {
        using var image = new Bitmap(10, 10);
        foreach (int failure in new[] { 0, 1, 2 })
        {
            int writes = 0;
            var notices = new List<string>();
            Equal(false, OcrService.CopyTextAsync(image, Array.Empty<RectangleF>(), _ => failure switch
            {
                1 => Task.FromException<IReadOnlyList<OcrTextLine>>(new OcrLanguageUnavailableException()),
                2 => Task.FromException<IReadOnlyList<OcrTextLine>>(new InvalidOperationException("OCR failed")),
                _ => Task.FromResult<IReadOnlyList<OcrTextLine>>(Array.Empty<OcrTextLine>())
            }, _ => { writes++; return true; }, notices.Add).GetAwaiter().GetResult());
            Equal(0, writes);
            Equal(1, notices.Count);
            if (failure == 1) Equal(true, notices[0].Contains("Sprachpaket"));
        }
    }

    private static void OcrCaptureReentry()
    {
        var gate = new CaptureGate();
        var pending = new TaskCompletionSource();
        Task<bool> capture = gate.TryRunAsync(() => pending.Task);
        Equal(false, gate.TryRun(() => throw new Exception("Must not capture")));
        Equal(false, gate.TryRunAsync(() => Task.CompletedTask).GetAwaiter().GetResult());
        pending.SetResult();
        Equal(true, capture.GetAwaiter().GetResult());
        Equal(true, gate.TryRun(() => { }));
        Throws<InvalidOperationException>(() => gate.TryRunAsync(() =>
            Task.FromException(new InvalidOperationException())).GetAwaiter().GetResult());
        Equal(true, gate.TryRun(() => { }));
    }

    private static void OcrClipboard()
    {
        var data = ClipboardRetry.TextData("Deutsch\nEnglish");
        Equal(true, data.GetDataPresent(DataFormats.UnicodeText, false));
        Equal("Deutsch\nEnglish", (string)data.GetData(DataFormats.UnicodeText)!);
        Equal(false, data.GetDataPresent(DataFormats.Bitmap));
        int attempts = 0;
        var delays = new List<int>();
        Equal(true, ClipboardRetry.TrySetText("text", text =>
        {
            Equal("text", text);
            if (++attempts < 3) throw new ExternalException();
        }, delays.Add));
        Equal(3, attempts);
        Equal("100,100", string.Join(",", delays));
        attempts = 0;
        Equal(false, ClipboardRetry.TrySetText("text", _ =>
        {
            attempts++;
            throw new ExternalException();
        }, _ => { }));
        Equal(3, attempts);
        Throws<InvalidOperationException>(() => ClipboardRetry.TrySetText("text",
            _ => throw new InvalidOperationException(), _ => throw new Exception("Must not retry")));
    }

    private static void EditorOcr()
    {
        using var image = new Bitmap(320, 180);
        using (var g = Graphics.FromImage(image)) g.Clear(Color.White);
        string copied = "";
        var notices = new List<string>();
        using var editor = new EditorForm(image, rendered =>
        {
            Equal(image.Size, rendered.Size);
            Equal(Color.FromArgb(255, 59, 48).ToArgb(), rendered.GetPixel(74, 36).ToArgb());
            return Task.FromResult<IReadOnlyList<OcrTextLine>>(new[] {
                OcrLine("secret", 0, 10), OcrLine("annotation", 0, 40) });
        }, text => { copied = text; return true; }, notices.Add);
        editor.Show();
        Application.DoEvents();
        ((List<Annotation>)Field(editor, "annotations")).Add(new Annotation {
            Tool = ToolType.Rectangle, Start = new Point(64, 36), End = new Point(256, 144),
            Color = Color.FromArgb(255, 59, 48), LineWidth = 4 });
        ((List<Annotation>)Field(editor, "annotations")).Add(new Annotation {
            Tool = ToolType.Blur, Start = new Point(0, 10), End = new Point(20, 20) });
        editor.CopyTextAsync().GetAwaiter().GetResult();
        Equal("annotation", copied);
        Equal(0, notices.Count);
        Equal(true, editor.Visible);
        Equal(true, ((ToolStrip)Field(editor, "mainToolbar")).Items["copyTextButton"]!.Enabled);
        editor.Close();
    }

    private static object Field(object target, string name) => target.GetType()
        .GetField(name, BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(target)!;

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
