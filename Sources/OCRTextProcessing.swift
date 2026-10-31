import Foundation

/// Bounds use image pixels with the origin at the top left on both platforms.
struct OCRLine: Sendable {
    let text: String
    let bounds: CGRect
}

enum OCRTextProcessing {
    /// Plain text only: top to bottom, left to right within a row; one OCR line
    /// per newline. Row membership uses a fixed anchor, not a non-transitive
    /// fuzzy sort comparator. No layout reconstruction or language rewriting.
    static func text(from lines: [OCRLine], excluding redactions: [CGRect] = []) -> String {
        var remaining = lines.filter { line in
            !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !redactions.contains { $0.intersects(line.bounds) }
        }.sorted {
            if $0.bounds.minY != $1.bounds.minY { return $0.bounds.minY < $1.bounds.minY }
            if $0.bounds.minX != $1.bounds.minX { return $0.bounds.minX < $1.bounds.minX }
            return $0.text < $1.text
        }
        var ordered: [String] = []
        while let anchor = remaining.first {
            let row = remaining.filter {
                $0.bounds.minY - anchor.bounds.minY <= min(anchor.bounds.height, $0.bounds.height) / 2
            }
            remaining.removeAll {
                $0.bounds.minY - anchor.bounds.minY <= min(anchor.bounds.height, $0.bounds.height) / 2
            }
            ordered.append(contentsOf: row.sorted {
                if $0.bounds.minX != $1.bounds.minX { return $0.bounds.minX < $1.bounds.minX }
                if $0.bounds.minY != $1.bounds.minY { return $0.bounds.minY < $1.bounds.minY }
                return $0.text < $1.text
            }.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) })
        }
        return ordered.joined(separator: "\n")
    }
}
