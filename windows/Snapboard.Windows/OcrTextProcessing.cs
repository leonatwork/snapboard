using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;

namespace Snapboard
{
    // Image pixels, top-left origin, including when the OCR input was scaled.
    public sealed record OcrTextLine(string Text, RectangleF Bounds);

    public static class OcrTextProcessing
    {
        public static string Text(IEnumerable<OcrTextLine> lines, IEnumerable<RectangleF>? redactions = null)
        {
            var excluded = (redactions ?? Array.Empty<RectangleF>()).ToArray();
            var remaining = lines.Where(line => !string.IsNullOrWhiteSpace(line.Text) &&
                !excluded.Any(rect => rect.IntersectsWith(line.Bounds)))
                .OrderBy(line => line.Bounds.Top).ThenBy(line => line.Bounds.Left)
                .ThenBy(line => line.Text, StringComparer.Ordinal).ToList();
            var ordered = new List<string>();
            while (remaining.Count > 0)
            {
                var anchor = remaining[0];
                // Fixed row anchor avoids a non-transitive fuzzy sort comparator.
                bool InRow(OcrTextLine line) => line.Bounds.Top - anchor.Bounds.Top <=
                    Math.Min(anchor.Bounds.Height, line.Bounds.Height) / 2;
                ordered.AddRange(remaining.Where(InRow).OrderBy(line => line.Bounds.Left)
                    .ThenBy(line => line.Bounds.Top).ThenBy(line => line.Text, StringComparer.Ordinal)
                    .Select(line => line.Text.Trim()));
                remaining.RemoveAll(line => InRow(line));
            }
            return string.Join("\n", ordered);
        }
    }
}
