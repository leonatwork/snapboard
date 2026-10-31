using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Media;
using System.Threading.Tasks;
using System.Windows.Forms;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage.Streams;

namespace Snapboard
{
    public sealed class OcrLanguageUnavailableException : Exception { }

    public sealed class OcrService
    {
        private readonly Func<Bitmap, Task<IReadOnlyList<OcrTextLine>>> recognize;
        private readonly Action<string> presentNotice;
        private bool isRecognizing;

        public OcrService(Func<Bitmap, Task<IReadOnlyList<OcrTextLine>>>? recognize = null,
            Action<string>? presentNotice = null)
        {
            this.recognize = recognize ?? RecognizeLocallyAsync;
            this.presentNotice = presentNotice ?? (message => MessageBox.Show(message,
                "Text erkennen", MessageBoxButtons.OK, MessageBoxIcon.Information));
        }

        // Call from the WinForms UI thread so clipboard writes stay on its STA.
        public async Task<bool> CopyTextAsync(Bitmap image, IEnumerable<RectangleF>? redactions = null)
        {
            if (isRecognizing) return false;
            isRecognizing = true;
            try
            {
                var lines = await recognize(image);
                string text = OcrTextProcessing.Text(lines, redactions);
                if (text.Length == 0)
                {
                    presentNotice("Kein Text erkannt. Die Zwischenablage bleibt unverändert. Wählen Sie einen Bereich mit gut lesbarem Text.");
                    return false;
                }
                if (!ClipboardRetry.TrySetText(text))
                {
                    presentNotice("Die Zwischenablage ist belegt. Der Text konnte nach 3 Versuchen nicht kopiert werden. Bitte versuchen Sie es erneut.");
                    return false;
                }
                SystemSounds.Asterisk.Play();
                return true;
            }
            catch (OcrLanguageUnavailableException)
            {
                presentNotice("Kein OCR-Sprachpaket für Ihre Benutzerprofil-Sprachen verfügbar. Installieren Sie unter Windows-Einstellungen → Zeit und Sprache → Sprache ein Sprachpaket mit Texterkennung (OCR), und versuchen Sie es erneut.");
                return false;
            }
            catch (Exception)
            {
                presentNotice("Der Text konnte nicht erkannt werden. Bitte versuchen Sie es mit einem anderen Bereich erneut.");
                return false;
            }
            finally { isRecognizing = false; }
        }

        private static async Task<IReadOnlyList<OcrTextLine>> RecognizeLocallyAsync(Bitmap image)
        {
            var engine = OcrEngine.TryCreateFromUserProfileLanguages();
            if (engine == null) throw new OcrLanguageUnavailableException();

            // PNG encoding and WinRT decoding stay in memory; no files or network.
            using var png = new MemoryStream();
            image.Save(png, ImageFormat.Png);
            using var stream = new InMemoryRandomAccessStream();
            using (var writer = new DataWriter(stream.GetOutputStreamAt(0)))
            {
                writer.WriteBytes(png.ToArray());
                await writer.StoreAsync();
                await writer.FlushAsync();
            }
            stream.Seek(0);
            var decoder = await BitmapDecoder.CreateAsync(stream);
            double scale = Math.Min(1, (double)OcrEngine.MaxImageDimension / Math.Max(image.Width, image.Height));
            uint width = (uint)Math.Max(1, Math.Floor(image.Width * scale));
            uint height = (uint)Math.Max(1, Math.Floor(image.Height * scale));
            using var bitmap = await decoder.GetSoftwareBitmapAsync(BitmapPixelFormat.Bgra8,
                BitmapAlphaMode.Premultiplied, new BitmapTransform { ScaledWidth = width, ScaledHeight = height },
                ExifOrientationMode.IgnoreExifOrientation, ColorManagementMode.DoNotColorManage);
            var result = await engine.RecognizeAsync(bitmap);
            float scaleX = (float)image.Width / width, scaleY = (float)image.Height / height;
            return result.Lines.Where(line => line.Words.Count > 0).Select(line =>
            {
                var boxes = line.Words.Select(word => word.BoundingRect).ToArray();
                double left = boxes.Min(box => box.X), top = boxes.Min(box => box.Y);
                double right = boxes.Max(box => box.X + box.Width), bottom = boxes.Max(box => box.Y + box.Height);
                return new OcrTextLine(line.Text, new RectangleF((float)left * scaleX, (float)top * scaleY,
                    (float)(right - left) * scaleX, (float)(bottom - top) * scaleY));
            }).ToArray();
        }
    }
}
