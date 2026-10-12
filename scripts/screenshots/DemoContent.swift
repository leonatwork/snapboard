import AppKit

/// Neutral demo content for the README screenshots.
///
/// Everything here is drawn programmatically: the editor shows this fake dashboard instead of a
/// real screen capture, so the screenshots never contain anything from the machine they were
/// rendered on.
enum DemoContent {
    struct Strings {
        let appTitle: String
        let sidebar: [String]
        let heading: String
        let subheading: String
        let kpis: [(label: String, value: String, delta: String)]
        let months: [String]
        let tableTitle: String
        let annotation: String
    }

    static func strings(for language: String) -> Strings {
        if language.hasPrefix("de") {
            return Strings(
                appTitle: "Dashboard",
                sidebar: ["Übersicht", "Berichte", "Bestellungen", "Einstellungen"],
                heading: "Umsatz Q3",
                subheading: "April – September",
                kpis: [
                    ("Umsatz", "48.200 €", "+12 %"),
                    ("Bestellungen", "1.284", "+8 %"),
                    ("Konversion", "3,4 %", "+0,6")
                ],
                months: ["Apr", "Mai", "Jun", "Jul", "Aug", "Sep"],
                tableTitle: "Neueste Bestellungen",
                annotation: "Rekordmonat!"
            )
        }
        return Strings(
            appTitle: "Dashboard",
            sidebar: ["Overview", "Reports", "Orders", "Settings"],
            heading: "Revenue Q3",
            subheading: "April – September",
            kpis: [
                ("Revenue", "€48.2k", "+12%"),
                ("Orders", "1,284", "+8%"),
                ("Conversion", "3.4%", "+0.6")
            ],
            months: ["Apr", "May", "Jun", "Jul", "Aug", "Sep"],
            tableTitle: "Latest orders",
            annotation: "Record month!"
        )
    }

    /// Size of the demo "screenshot" in points (rendered at the backing scale).
    static let imageSize = NSSize(width: 780, height: 440)

    // Layout constants shared with the annotation positions below (top-left origin).
    static let chartRect = NSRect(x: 196, y: 186, width: 336, height: 214)
    static let barCount = 6
    static let barValues: [CGFloat] = [0.42, 0.55, 0.48, 0.63, 0.71, 0.94]
    static let kpiRects: [NSRect] = (0..<3).map { i in
        NSRect(x: 196 + CGFloat(i) * 192, y: 84, width: 176, height: 78)
    }
    static let tableRect = NSRect(x: 552, y: 186, width: 208, height: 214)

    static func barRect(_ index: Int) -> NSRect {
        let inner = chartRect.insetBy(dx: 20, dy: 0)
        let plotTop = chartRect.minY + 44
        let plotBottom = chartRect.maxY - 30
        let slot = inner.width / CGFloat(barCount)
        let barWidth = slot * 0.56
        let height = (plotBottom - plotTop) * barValues[index]
        return NSRect(
            x: inner.minX + slot * CGFloat(index) + (slot - barWidth) / 2,
            y: plotBottom - height,
            width: barWidth,
            height: height
        )
    }

    static func makeImage(language: String) -> NSImage {
        let s = strings(for: language)
        return NSImage(size: imageSize, flipped: true) { bounds in
            draw(s, in: bounds)
            return true
        }
    }

    // MARK: - Drawing

    private static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    private static func text(
        _ string: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight = .regular,
        color: NSColor, align: NSTextAlignment = .left, width: CGFloat = 0
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: style
        ]
        let str = NSAttributedString(string: string, attributes: attrs)
        if width > 0 {
            str.draw(in: NSRect(x: point.x, y: point.y, width: width, height: size * 1.5))
        } else {
            str.draw(at: point)
        }
    }

    private static func fill(_ rect: NSRect, _ color: NSColor, radius: CGFloat = 0) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    private static func card(_ rect: NSRect) {
        let shadow = NSShadow()
        shadow.shadowColor = color(0x1B2A4A, 0.08)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        fill(rect, .white, radius: 10)
        NSGraphicsContext.restoreGraphicsState()
        color(0xE3E8F0).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        border.lineWidth = 1
        border.stroke()
    }

    private static func draw(_ s: Strings, in bounds: NSRect) {
        let ink = color(0x1E293B)
        let muted = color(0x64748B)
        let accent = color(0x4F46E5)

        // Window background + fake title bar of the demo app
        fill(bounds, color(0xF4F6FA))
        fill(NSRect(x: 0, y: 0, width: bounds.width, height: 40), .white)
        fill(NSRect(x: 0, y: 40, width: bounds.width, height: 1), color(0xE3E8F0))
        for (i, hex) in [UInt32(0xFF5F57), 0xFEBC2E, 0x28C840].enumerated() {
            color(hex).setFill()
            NSBezierPath(ovalIn: NSRect(x: 16 + CGFloat(i) * 20, y: 14, width: 12, height: 12)).fill()
        }
        text(s.appTitle, at: NSPoint(x: 0, y: 11), size: 13, weight: .semibold, color: ink,
             align: .center, width: bounds.width)

        // Sidebar
        fill(NSRect(x: 0, y: 41, width: 176, height: bounds.height - 41), .white)
        fill(NSRect(x: 176, y: 41, width: 1, height: bounds.height - 41), color(0xE3E8F0))
        fill(NSRect(x: 16, y: 58, width: 28, height: 28), accent, radius: 7)
        fill(NSRect(x: 54, y: 66, width: 84, height: 10), color(0xCBD5E1), radius: 5)
        for (i, item) in s.sidebar.enumerated() {
            let y = 108 + CGFloat(i) * 38
            if i == 0 {
                fill(NSRect(x: 10, y: y - 8, width: 156, height: 32), color(0xEEF0FF), radius: 8)
            }
            fill(NSRect(x: 22, y: y + 1, width: 14, height: 14), i == 0 ? accent : color(0xCBD5E1), radius: 4)
            text(item, at: NSPoint(x: 46, y: y), size: 13, weight: i == 0 ? .semibold : .regular,
                 color: i == 0 ? accent : muted)
        }

        // Heading
        text(s.heading, at: NSPoint(x: 196, y: 52), size: 20, weight: .bold, color: ink)
        text(s.subheading, at: NSPoint(x: 330, y: 58), size: 12, color: muted)

        // KPI cards
        for (i, kpi) in s.kpis.enumerated() {
            let r = kpiRects[i]
            card(r)
            text(kpi.label, at: NSPoint(x: r.minX + 14, y: r.minY + 12), size: 12, color: muted)
            text(kpi.value, at: NSPoint(x: r.minX + 14, y: r.minY + 33), size: 20, weight: .bold, color: ink)
            fill(NSRect(x: r.maxX - 58, y: r.minY + 40, width: 46, height: 20), color(0xDCFCE7), radius: 10)
            text(kpi.delta, at: NSPoint(x: r.maxX - 58, y: r.minY + 42), size: 11, weight: .semibold,
                 color: color(0x15803D), align: .center, width: 46)
        }

        // Bar chart
        card(chartRect)
        text(s.heading, at: NSPoint(x: chartRect.minX + 16, y: chartRect.minY + 14), size: 13,
             weight: .semibold, color: ink)
        let plotTop = chartRect.minY + 44
        let plotBottom = chartRect.maxY - 30
        for step in 0...3 {
            let y = plotBottom - (plotBottom - plotTop) * CGFloat(step) / 3
            fill(NSRect(x: chartRect.minX + 16, y: y, width: chartRect.width - 32, height: 1), color(0xEEF2F7))
        }
        for i in 0..<barCount {
            let r = barRect(i)
            fill(r, i == barCount - 1 ? accent : color(0xA5B4FC), radius: 5)
            text(s.months[i], at: NSPoint(x: r.midX - 20, y: plotBottom + 8), size: 11, color: muted,
                 align: .center, width: 40)
        }

        // Table with placeholder rows (gets "redacted" in the demo)
        card(tableRect)
        text(s.tableTitle, at: NSPoint(x: tableRect.minX + 16, y: tableRect.minY + 14), size: 13,
             weight: .semibold, color: ink)
        let widths: [CGFloat] = [92, 74, 104, 66, 86]
        for (i, w) in widths.enumerated() {
            let y = tableRect.minY + 50 + CGFloat(i) * 32
            fill(NSRect(x: tableRect.minX + 16, y: y, width: 22, height: 22), color(0xE0E7FF), radius: 11)
            fill(NSRect(x: tableRect.minX + 46, y: y + 3, width: w, height: 8), color(0xCBD5E1), radius: 4)
            fill(NSRect(x: tableRect.minX + 46, y: y + 14, width: w * 0.6, height: 6), color(0xE2E8F0), radius: 3)
            fill(NSRect(x: tableRect.maxX - 52, y: y + 6, width: 36, height: 9), color(0xBBF7D0), radius: 4)
        }
    }
}
