using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Resources;
using System.Runtime.InteropServices;
using System.Windows.Forms;
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
            ("Windows UI follows en/de/ja and falls back from pl to English", LocalizedEditor),
            ("All ten satellite catalogs load and format every resource", LocalizedCatalogs),
            ("About text uses the app assembly version, not the runner version", AboutVersion)
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

    private static readonly ResourceManager Strings = new ResourceManager(
        "Snapboard.Resources.Strings", typeof(EditorForm).Assembly);

    private static string Localized(string key) => Strings.GetString(key, CultureInfo.CurrentUICulture)!;

    private static void LocalizedEditor()
    {
        CultureInfo original = CultureInfo.CurrentUICulture;
        try
        {
            foreach (var entry in new[] { ("en-US", "Note"), ("de-DE", "Hinweis"),
                ("ja-JP", "メモ"), ("pl-PL", "Note") })
            {
                CultureInfo.CurrentUICulture = CultureInfo.GetCultureInfo(entry.Item1);
                using var image = new Bitmap(20, 20);
                using var editor = new EditorForm(image);
                Equal(entry.Item2, (string)Field(editor, "currentText"));
                Equal(Localized("editor.windowTitle"), editor.Text);
                var toolbar = (ToolStrip)Field(editor, "mainToolbar");
                Equal(Localized("tool.rectangle"), toolbar.Items[0].Text);
                Equal(true, ContainsText(toolbar, Localized("windows.editor.copyToClipboard")));
                Equal(true, ContainsText(toolbar, Localized("windows.editor.saveAs")));
                Equal(true, Localized("windows.menu.captureDirect").Contains(
                    Localized("windows.shortcut.direct")));
                Equal(true, Localized("windows.statusItem.tooltip").Length <= 127);
                if (entry.Item1 == "pl-PL")
                    Equal(Strings.GetString("windows.about.message", CultureInfo.GetCultureInfo("en")),
                        Localized("windows.about.message"));
            }
        }
        finally { CultureInfo.CurrentUICulture = original; }
    }

    private static bool ContainsText(ToolStrip toolbar, string text)
    {
        foreach (ToolStripItem item in toolbar.Items) if (item.Text == text) return true;
        return false;
    }

    private static void LocalizedCatalogs()
    {
        var neutral = Strings.GetResourceSet(CultureInfo.InvariantCulture, true, false)!;
        foreach (string language in new[] { "en", "de", "fr", "es", "it", "pt-BR", "nl", "ja", "zh-Hans", "ko" })
        {
            var culture = CultureInfo.GetCultureInfo(language);
            var catalog = Strings.GetResourceSet(culture, true, false);
            Equal(true, catalog != null);
            Equal(true, catalog!.GetString("windows.statusItem.tooltip")!.Length <= 127);
            foreach (System.Collections.DictionaryEntry entry in neutral)
            {
                string value = catalog!.GetString((string)entry.Key)!;
                Equal(true, !string.IsNullOrWhiteSpace(value));
                Equal(false, value.Contains('⌘') || value.Contains('⇧'));
                // The catalog checker validates exact argument indices and multiplicity.
                object[] arguments = (string)entry.Key == "windows.editor.saveFileName"
                    ? new object[] { new DateTime(2026, 10, 26, 12, 34, 56) }
                    : new object[] { 12, 34, 56 };
                _ = string.Format(culture, value, arguments);
            }
        }
        // Parent-culture lookup and unsupported-language fallback use .NET ResourceManager.
        Equal(Strings.GetString("editor.defaultText", CultureInfo.GetCultureInfo("fr")),
            Strings.GetString("editor.defaultText", CultureInfo.GetCultureInfo("fr-CA")));
        Equal(Strings.GetString("editor.defaultText", CultureInfo.GetCultureInfo("zh-Hans")),
            Strings.GetString("editor.defaultText", CultureInfo.GetCultureInfo("zh-CN")));
    }

    private static void AboutVersion()
    {
        var helper = typeof(EditorForm).Assembly.GetType("Snapboard.L10n")!;
        string actual = (string)helper.GetProperty("AboutMessage", BindingFlags.Static | BindingFlags.Public)!
            .GetValue(null)!;
        string version = typeof(EditorForm).Assembly.GetName().Version!.ToString(3);
        Equal(string.Format(CultureInfo.CurrentUICulture, Localized("windows.about.message"), version), actual);
        Equal(true, actual.Contains(version));
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
