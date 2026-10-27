using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;

namespace Snapboard
{
    // Pixel coordinates in the source image, with a top-left origin.
    public sealed record OcrTextLine(string Text, RectangleF Bounds);

    public static class OcrTextLayout
    {
        // Fixed row anchors avoid a non-transitive fuzzy sort comparator.
        public static string PlainText(IEnumerable<OcrTextLine> lines, IReadOnlyList<RectangleF>? redactions = null)
        {
            var sorted = lines.Where(line => !string.IsNullOrWhiteSpace(line.Text) &&
                !(redactions?.Any(rect => rect.IntersectsWith(line.Bounds)) ?? false))
                .OrderBy(line => CenterY(line.Bounds)).ThenBy(line => line.Bounds.Left)
                .ThenBy(line => line.Text, StringComparer.Ordinal);
            var rows = new List<List<OcrTextLine>>();
            foreach (var line in sorted)
            {
                var anchor = rows.LastOrDefault()?.First();
                if (anchor != null && Math.Abs(CenterY(line.Bounds) - CenterY(anchor.Bounds)) <=
                    Math.Min(line.Bounds.Height, anchor.Bounds.Height) / 2)
                    rows[^1].Add(line);
                else
                    rows.Add(new List<OcrTextLine> { line });
            }
            return string.Join("\n", rows.Select(row => string.Join(" ", row.OrderBy(line => line.Bounds.Left)
                .ThenBy(line => line.Text, StringComparer.Ordinal).Select(line => line.Text.Trim()))));
        }

        private static float CenterY(RectangleF rect) => rect.Top + rect.Height / 2;
    }
}
