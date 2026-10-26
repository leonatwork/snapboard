using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

namespace Snapboard
{
    public static class ClipboardRetry
    {
        public static bool TrySetImage(Image image) => TrySetImage(image, SetImageOnce, Thread.Sleep);

        private static void SetImageOnce(Image image)
        {
            var data = new DataObject();
            data.SetImage(image);
            // Clipboard.SetImage adds WinForms' own retries. Disable those so the
            // three attempts / 100 ms policy is controlled only by this helper.
            Clipboard.SetDataObject(data, true, 0, 0);
        }

        public static bool TrySetImage(Image image, Action<Image> setImage, Action<int> delay)
        {
            for (int attempt = 0; attempt < 3; attempt++)
            {
                try { setImage(image); return true; }
                catch (ExternalException)
                {
                    if (attempt < 2) delay(100);
                }
            }
            return false;
        }
    }
}
