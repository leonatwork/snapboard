using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;

namespace Snapboard
{
    public static class ImageExport
    {
        public const long JpegQuality = 90L;

        // The selected dialog filter is authoritative, even with a manually entered extension.
        public static void Save(Image image, Stream destination, int filterIndex)
        {
            if (filterIndex != 2)
            {
                image.Save(destination, ImageFormat.Png);
                return;
            }

            ImageCodecInfo jpeg = Array.Find(ImageCodecInfo.GetImageEncoders(),
                codec => codec.FormatID == ImageFormat.Jpeg.Guid)
                ?? throw new InvalidOperationException("Der JPEG-Encoder ist nicht verfügbar.");
            using var parameters = new EncoderParameters(1);
            parameters.Param[0] = new EncoderParameter(Encoder.Quality, JpegQuality);
            image.Save(destination, jpeg, parameters);
        }
    }
}
