using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Forms;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage.Streams;

namespace Snapboard
{
    public sealed class OcrLanguageUnavailableException : Exception { }

    public static class OcrService
    {
        public static async Task<bool> CopyTextAsync(Bitmap image, IReadOnlyList<RectangleF> redactions,
            Func<Bitmap, Task<IReadOnlyList<OcrTextLine>>>? recognize = null,
            Func<string, bool>? setText = null, Action<string>? presentNotice = null)
        {
            recognize ??= RecognizeAsync;
            setText ??= ClipboardRetry.TrySetText;
            presentNotice ??= message => MessageBox.Show(message, "Text erkennen",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            try
            {
                var lines = await recognize(image);
                string text = OcrTextLayout.PlainText(lines, redactions);
                if (text.Length == 0)
                {
                    presentNotice("Kein Text erkannt. Die Zwischenablage bleibt unverändert.");
                    return false;
                }
                // The continuation stays on the WinForms STA thread for clipboard access.
                if (!setText(text))
                {
                    presentNotice("Die Zwischenablage ist belegt. Der Text konnte nach 3 Versuchen nicht kopiert werden. Bitte versuchen Sie es erneut.");
                    return false;
                }
                return true;
            }
            catch (OcrLanguageUnavailableException)
            {
                presentNotice("Kein OCR-Sprachpaket für Ihre Benutzerprofil-Sprachen verfügbar. Installieren Sie in den Windows-Einstellungen unter Zeit und Sprache ein Sprachpaket mit Texterkennung (OCR). Die Zwischenablage bleibt unverändert.");
                return false;
            }
            catch (Exception)
            {
                presentNotice("Die lokale Texterkennung ist fehlgeschlagen. Die Zwischenablage bleibt unverändert. Bitte versuchen Sie es erneut.");
                return false;
            }
        }

        public static async Task<IReadOnlyList<OcrTextLine>> RecognizeAsync(Bitmap image)
        {
            var engine = OcrEngine.TryCreateFromUserProfileLanguages();
            if (engine == null) throw new OcrLanguageUnavailableException();

            // Windows OCR has a maximum dimension; fit large/HiDPI captures in memory.
            double scale = Math.Min(1, (double)OcrEngine.MaxImageDimension / Math.Max(image.Width, image.Height));
            using var input = new Bitmap(Math.Max(1, (int)(image.Width * scale)), Math.Max(1, (int)(image.Height * scale)));
            using (var graphics = Graphics.FromImage(input))
            {
                graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
                graphics.DrawImage(image, new Rectangle(Point.Empty, input.Size),
                    new Rectangle(Point.Empty, image.Size), GraphicsUnit.Pixel);
            }
            using var encoded = new MemoryStream();
            input.Save(encoded, ImageFormat.Png);
            using var stream = new InMemoryRandomAccessStream();
            using (var writer = new DataWriter(stream))
            {
                writer.WriteBytes(encoded.ToArray());
                await writer.StoreAsync();
                writer.DetachStream();
            }
            stream.Seek(0);
            var decoder = await BitmapDecoder.CreateAsync(stream);
            using var bitmap = await decoder.GetSoftwareBitmapAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied);
            var result = await engine.RecognizeAsync(bitmap);
            float scaleX = (float)image.Width / input.Width;
            float scaleY = (float)image.Height / input.Height;
            return result.Lines.Where(line => line.Words.Count > 0).Select(line =>
            {
                double left = line.Words.Min(word => word.BoundingRect.Left);
                double top = line.Words.Min(word => word.BoundingRect.Top);
                double right = line.Words.Max(word => word.BoundingRect.Right);
                double bottom = line.Words.Max(word => word.BoundingRect.Bottom);
                return new OcrTextLine(line.Text, new RectangleF((float)left * scaleX, (float)top * scaleY,
                    (float)(right - left) * scaleX, (float)(bottom - top) * scaleY));
            }).ToArray();
        }
    }
}
