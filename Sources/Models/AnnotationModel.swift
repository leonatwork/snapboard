import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

enum AnnotationTool: String, CaseIterable, Identifiable {
    case rectangle
    case circle
    case arrow
    case pen
    case highlighter
    case blur
    case text
    case stepNumber

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rectangle: return L10n.tr("tool.rectangle")
        case .circle: return L10n.tr("tool.circle")
        case .arrow: return L10n.tr("tool.arrow")
        case .pen: return L10n.tr("tool.pen")
        case .highlighter: return L10n.tr("tool.highlighter")
        case .blur: return L10n.tr("tool.blur")
        case .text: return L10n.tr("tool.text")
        case .stepNumber: return L10n.tr("tool.stepNumber")
        }
    }

    var iconName: String {
        switch self {
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .blur: return "theatermask.and.paintbrush"
        case .text: return "character.textbox"
        case .stepNumber: return "number.circle.fill"
        }
    }
}

enum AnnotationColor: String, CaseIterable, Identifiable {
    case red = "#FF3B30"
    case orange = "#FF9500"
    case yellow = "#FFCC00"
    case green = "#34C759"
    case blue = "#007AFF"
    case purple = "#AF52DE"
    case white = "#FFFFFF"
    case black = "#000000"

    var id: String { rawValue }

    var color: Color {
        Color(hex: rawValue) ?? .red
    }

    var nsColor: NSColor {
        NSColor(hex: rawValue) ?? .systemRed
    }
}

struct AnnotationItem: Identifiable, Equatable {
    let id: UUID = UUID()
    var tool: AnnotationTool
    var startPoint: CGPoint // Normalized (0...1, 0...1 with 0,0 at top-left)
    var endPoint: CGPoint   // Normalized (0...1, 0...1 with 0,0 at top-left)
    var points: [CGPoint] = [] // For pen / highlighter
    var color: AnnotationColor
    var lineWidth: CGFloat
    var text: String = ""
    var stepNumber: Int = 1

    static func == (lhs: AnnotationItem, rhs: AnnotationItem) -> Bool {
        lhs.id == rhs.id
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}

@MainActor
final class ImageRendererService {
    static let shared = ImageRendererService()

    private let ciContext = CIContext()

    func render(image: NSImage, annotations: [AnnotationItem]) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let pixelWidth = cgImage.width
        let pixelHeight = cgImage.height

        guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        let fullRect = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        context.draw(cgImage, in: fullRect)

        // Apply Blur / Pixellate
        let blurItems = annotations.filter { $0.tool == .blur }
        for item in blurItems {
            applyBlur(
                to: context,
                rect: item.cgRectInPixelSpace(width: pixelWidth, height: pixelHeight),
                originalCGImage: cgImage
            )
        }

        // Draw Vector Annotations in NSGraphicsContext
        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext

        for item in annotations where item.tool != .blur {
            drawAnnotation(item, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let resultCGImage = context.makeImage() else { return nil }
        // Keep the source's point size (and therefore DPI) without resampling its pixels.
        return NSImage(cgImage: resultCGImage, size: image.size)
    }

    private func applyBlur(to context: CGContext, rect: CGRect, originalCGImage: CGImage) {
        guard rect.width > 2 && rect.height > 2 else { return }

        let ciImage = CIImage(cgImage: originalCGImage)
        let pixellate = CIFilter.pixellate()
        pixellate.inputImage = ciImage
        pixellate.scale = Float(max(8.0, min(rect.width, rect.height) / 8.0))

        guard let outputCI = pixellate.outputImage else { return }
        let croppedCI = outputCI.cropped(to: rect)

        if let blurredCG = ciContext.createCGImage(croppedCI, from: rect) {
            context.saveGState()
            context.draw(blurredCG, in: rect)
            context.restoreGState()
        }
    }

    /// Draws in image pixels, bottom-left origin. The preview only transforms this space.
    func drawAnnotation(_ item: AnnotationItem, pixelWidth: Int, pixelHeight: Int) {
        let pW = CGFloat(pixelWidth)
        let pH = CGFloat(pixelHeight)
        let layout = AnnotationLayout(item: item, imagePixelSize: CGSize(width: pW, height: pH))
        let color = item.color.nsColor
        let lineWidth = layout.lineWidth
        let rect = layout.rect

        switch item.tool {
        case .rectangle:
            color.setStroke()
            let path = NSBezierPath(roundedRect: rect, xRadius: lineWidth, yRadius: lineWidth)
            path.lineWidth = lineWidth
            path.stroke()

        case .circle:
            color.setStroke()
            let path = NSBezierPath(ovalIn: rect)
            path.lineWidth = lineWidth
            path.stroke()

        case .arrow:
            drawArrow(layout: layout, color: color)

        case .pen:
            guard item.points.count > 1 else { break }
            color.setStroke()
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            path.move(to: layout.points[0])
            for point in layout.points.dropFirst() {
                path.line(to: point)
            }
            path.stroke()

        case .highlighter:
            guard item.points.count > 1 else { break }
            let hlColor = color.withAlphaComponent(0.4)
            hlColor.setStroke()
            let path = NSBezierPath()
            path.lineWidth = layout.highlighterWidth
            path.lineCapStyle = .square
            path.lineJoinStyle = .miter

            path.move(to: layout.points[0])
            for point in layout.points.dropFirst() {
                path.line(to: point)
            }
            path.stroke()

        case .text:
            TextAnnotationLayout(item: item, imagePixelSize: CGSize(width: pW, height: pH))?
                .draw(flipped: false)

        case .stepNumber:
            let badgeRect = layout.badgeRect

            color.setFill()
            let circle = NSBezierPath(ovalIn: badgeRect)
            circle.fill()

            NSColor.white.setStroke()
            circle.lineWidth = layout.badgeBorderWidth
            circle.stroke()

            let numStr = "\(item.stepNumber)"
            let font = NSFont.boldSystemFont(ofSize: layout.badgeFontSize)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white
            ]
            let str = NSAttributedString(string: numStr, attributes: attributes)
            let strSize = str.size()
            let strPt = CGPoint(
                x: badgeRect.midX - (strSize.width / 2.0),
                y: badgeRect.midY - (strSize.height / 2.0)
            )
            str.draw(at: strPt)

        case .blur:
            break
        }
    }

    private func drawArrow(layout: AnnotationLayout, color: NSColor) {
        color.setStroke()
        color.setFill()

        let path = NSBezierPath()
        path.lineWidth = layout.lineWidth
        path.lineCapStyle = .round
        path.move(to: layout.start)
        path.line(to: layout.end)
        path.stroke()

        let headPath = NSBezierPath()
        headPath.move(to: layout.end)
        for point in layout.arrowHeadPoints {
            headPath.line(to: point)
        }
        headPath.close()
        headPath.fill()
    }
}

/// Pure geometry/style values in image pixels. Bottom-left origin intentionally matches
/// the existing export arithmetic exactly (including floating-point operation order).
struct AnnotationLayout {
    let start: CGPoint
    let end: CGPoint
    let points: [CGPoint]
    let rect: CGRect
    let lineWidth: CGFloat

    var highlighterWidth: CGFloat { lineWidth * 3.5 }
    var arrowHeadLength: CGFloat { max(14.0, lineWidth * 3.5) }
    var badgeRadius: CGFloat { max(14.0, lineWidth * 3.5) }
    var badgeBorderWidth: CGFloat { max(1.5, badgeRadius * 0.1) }
    var badgeFontSize: CGFloat { badgeRadius * 1.1 }
    var badgeRect: CGRect {
        CGRect(x: start.x - badgeRadius, y: start.y - badgeRadius,
               width: badgeRadius * 2, height: badgeRadius * 2)
    }

    var arrowHeadPoints: [CGPoint] {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headAngle = CGFloat.pi / 6.0
        return [angle - headAngle, angle + headAngle].map { direction in
            CGPoint(x: end.x - arrowHeadLength * cos(direction),
                    y: end.y - arrowHeadLength * sin(direction))
        }
    }

    init(item: AnnotationItem, imagePixelSize: CGSize) {
        func place(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x * imagePixelSize.width, y: (1.0 - point.y) * imagePixelSize.height)
        }
        start = place(item.startPoint)
        end = place(item.endPoint)
        points = item.points.map(place)
        rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                      width: abs(end.x - start.x), height: abs(end.y - start.y))
        lineWidth = max(2.0, item.lineWidth * (imagePixelSize.width / 800.0))
    }
}

/// Geometry of a text annotation, shared by the editor preview and the exported image so
/// both look exactly the same.
///
/// All values are in the pixel space of the image with a top-left origin. The anchor point
/// (`startPoint`) is the bottom-left corner of the text; the background box adds a small
/// padding around it.
struct TextAnnotationLayout {
    static let backgroundColor = NSColor.black.withAlphaComponent(0.65)
    static let cornerRadius: CGFloat = 4

    let attributedString: NSAttributedString
    let textRect: CGRect
    let backgroundRect: CGRect
    let imagePixelSize: CGSize

    init?(item: AnnotationItem, imagePixelSize: CGSize) {
        guard item.tool == .text, !item.text.isEmpty,
              imagePixelSize.width > 0, imagePixelSize.height > 0 else { return nil }

        let lineWidth = max(2.0, item.lineWidth * (imagePixelSize.width / 800.0))
        let font = NSFont.boldSystemFont(ofSize: max(14.0, lineWidth * 4.5))
        let attributedString = NSAttributedString(string: item.text, attributes: [
            .font: font,
            .foregroundColor: item.color.nsColor
        ])
        let size = attributedString.size()
        let anchor = CGPoint(
            x: item.startPoint.x * imagePixelSize.width,
            y: item.startPoint.y * imagePixelSize.height
        )

        self.attributedString = attributedString
        self.imagePixelSize = imagePixelSize
        self.textRect = CGRect(x: anchor.x, y: anchor.y - size.height, width: size.width, height: size.height)
        self.backgroundRect = textRect.insetBy(dx: -4, dy: -2)
    }

    /// Draws background and text into the current `NSGraphicsContext`, whose coordinate
    /// space is the image's pixel space. `flipped` tells whether its origin is top-left.
    func draw(flipped: Bool) {
        func place(_ rect: CGRect) -> CGRect {
            flipped ? rect : CGRect(
                x: rect.minX, y: imagePixelSize.height - rect.maxY,
                width: rect.width, height: rect.height
            )
        }

        Self.backgroundColor.setFill()
        NSBezierPath(
            roundedRect: place(backgroundRect),
            xRadius: Self.cornerRadius,
            yRadius: Self.cornerRadius
        ).fill()

        attributedString.draw(at: place(textRect).origin)
    }
}

extension AnnotationItem {
    func cgRectInPixelSpace(width: Int, height: Int) -> CGRect {
        let pW = CGFloat(width)
        let pH = CGFloat(height)

        let y1 = (1.0 - startPoint.y) * pH
        let y2 = (1.0 - endPoint.y) * pH
        let x1 = startPoint.x * pW
        let x2 = endPoint.x * pW

        return CGRect(
            x: min(x1, x2),
            y: min(y1, y2),
            width: abs(x2 - x1),
            height: abs(y2 - y1)
        )
    }
}
