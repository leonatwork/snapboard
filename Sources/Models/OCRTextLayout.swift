import Foundation

/// A recognized line in normalized image coordinates, with a top-left origin.
struct OCRTextLine: Sendable {
    let text: String
    let bounds: CGRect
}

enum OCRTextLayout {
    /// Plain text in top-to-bottom, left-to-right reading order. No layout preservation.
    /// Group against a fixed row anchor, rather than a non-transitive fuzzy comparator.
    static func plainText<S: Sequence>(_ lines: S, excluding redactions: [CGRect] = []) -> String
    where S.Element == OCRTextLine {
        let sorted = lines.filter { line in
            !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !redactions.contains(where: { $0.intersects(line.bounds) })
        }.sorted {
            if $0.bounds.midY != $1.bounds.midY { return $0.bounds.midY < $1.bounds.midY }
            if $0.bounds.minX != $1.bounds.minX { return $0.bounds.minX < $1.bounds.minX }
            return $0.text < $1.text
        }
        var rows: [[OCRTextLine]] = []
        for line in sorted {
            if let anchor = rows.last?.first,
               abs(line.bounds.midY - anchor.bounds.midY) <= min(line.bounds.height, anchor.bounds.height) / 2 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { row in
            row.sorted {
                if $0.bounds.minX != $1.bounds.minX { return $0.bounds.minX < $1.bounds.minX }
                return $0.text < $1.text
            }.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: " ")
        }.joined(separator: "\n")
    }
}
