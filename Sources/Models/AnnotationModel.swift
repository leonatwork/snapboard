import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

enum AnnotationTool: String, CaseIterable, Identifiable {
    case circle
    case rectangle
    case arrow
    case pen
    case highlighter
    case blur
    case text
    case stepNumber

    var id: String { rawValue }

    var title: String {
        switch self {
        case .circle: return "Kreis"
        case .rectangle: return "Rechteck"
        case .arrow: return "Pfeil"
        case .pen: return "Stift"
        case .highlighter: return "Marker"
        case .blur: return "Zensieren / Blur"
        case .text: return "Text"
        case .stepNumber: return "Schritt"
        }
    }

    var iconName: String {
        switch self {
        case .circle: return "circle"
        case .rectangle: return "rectangle"
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

struct AnnotationItem: Identifiable {
    let id: UUID = UUID()
    var tool: AnnotationTool
    var startPoint: CGPoint
    var endPoint: CGPoint
    var points: [CGPoint] = []
    var color: AnnotationColor
    var lineWidth: CGFloat
    var text: String = ""
    var stepNumber: Int = 1
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

// Renderer to export the final image at full original resolution
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

        // Draw original base image
        let fullRect = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        context.draw(cgImage, in: fullRect)

        // Apply Blur / Pixellate annotations directly to base image in CGContext
        let blurItems = annotations.filter { $0.tool == .blur }
        for item in blurItems {
            applyBlur(to: context, rect: item.rectInPixelSpace(canvasSize: CGSize(width: pixelWidth, height: pixelHeight)), originalCGImage: cgImage)
        }

        // Setup NSGraphicsContext for drawing vector annotations over the image
        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext

        for item in annotations where item.tool != .blur {
            drawAnnotation(item, context: context, pixelSize: CGSize(width: pixelWidth, height: pixelHeight))
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let resultCGImage = context.makeImage() else { return nil }
        return NSImage(cgImage: resultCGImage, size: NSSize(width: pixelWidth, height: pixelHeight))
    }

    private func applyBlur(to context: CGContext, rect: CGRect, originalCGImage: CGImage) {
        guard rect.width > 2 && rect.height > 2 else { return }

        let ciImage = CIImage(cgImage: originalCGImage)
        
        // Pixelate filter for clean redaction / blur
        let pixellate = CIFilter.pixellate()
        pixellate.inputImage = ciImage
        pixellate.scale = Float(max(10.0, min(rect.width, rect.height) / 8.0))

        guard let outputCI = pixellate.outputImage else { return }
        
        // Crop pixelated image to the target rect
        let croppedCI = outputCI.cropped(to: rect)
        
        if let blurredCG = ciContext.createCGImage(croppedCI, from: rect) {
            context.saveGState()
            context.draw(blurredCG, in: rect)
            context.restoreGState()
        }
    }

    private func drawAnnotation(_ item: AnnotationItem, context: CGContext, pixelSize: CGSize) {
        let scaleX = pixelSize.width
        let scaleY = pixelSize.height

        let start = CGPoint(x: item.startPoint.x * scaleX, y: item.startPoint.y * scaleY)
        let end = CGPoint(x: item.endPoint.x * scaleX, y: item.endPoint.y * scaleY)
        let color = item.color.nsColor
        let lineWidth = max(2.0, item.lineWidth * (pixelSize.width / 800.0))

        context.saveGState()

        switch item.tool {
        case .circle:
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            color.setStroke()
            let path = NSBezierPath(ovalIn: rect)
            path.lineWidth = lineWidth
            path.stroke()

        case .rectangle:
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            color.setStroke()
            let path = NSBezierPath(roundedRect: rect, xRadius: lineWidth, yRadius: lineWidth)
            path.lineWidth = lineWidth
            path.stroke()

        case .arrow:
            drawArrow(from: start, to: end, color: color, lineWidth: lineWidth)

        case .pen:
            guard item.points.count > 1 else { break }
            color.setStroke()
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            let firstPt = CGPoint(x: item.points[0].x * scaleX, y: item.points[0].y * scaleY)
            path.move(to: firstPt)
            for pt in item.points.dropFirst() {
                let scaledPt = CGPoint(x: pt.x * scaleX, y: pt.y * scaleY)
                path.line(to: scaledPt)
            }
            path.stroke()

        case .highlighter:
            guard item.points.count > 1 else { break }
            let highlightColor = color.withAlphaComponent(0.4)
            highlightColor.setStroke()
            let path = NSBezierPath()
            path.lineWidth = lineWidth * 3.0
            path.lineCapStyle = .square
            path.lineJoinStyle = .miter

            let firstPt = CGPoint(x: item.points[0].x * scaleX, y: item.points[0].y * scaleY)
            path.move(to: firstPt)
            for pt in item.points.dropFirst() {
                let scaledPt = CGPoint(x: pt.x * scaleX, y: pt.y * scaleY)
                path.line(to: scaledPt)
            }
            path.stroke()

        case .text:
            guard !item.text.isEmpty else { break }
            let fontSize = max(14.0, lineWidth * 4.5)
            let font = NSFont.boldSystemFont(ofSize: fontSize)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]
            let attributedString = NSAttributedString(string: item.text, attributes: attributes)
            let textSize = attributedString.size()
            let textRect = CGRect(x: start.x, y: start.y - textSize.height, width: textSize.width + 10, height: textSize.height)

            // Optional background bubble for high contrast readability
            NSColor.black.withAlphaComponent(0.6).setFill()
            let bgPath = NSBezierPath(roundedRect: textRect.insetBy(dx: -4, dy: -2), xRadius: 4, yRadius: 4)
            bgPath.fill()

            attributedString.draw(at: CGPoint(x: start.x, y: start.y - textSize.height))

        case .stepNumber:
            let radius = max(12.0, lineWidth * 3.5)
            let badgeRect = CGRect(x: start.x - radius, y: start.y - radius, width: radius * 2, height: radius * 2)

            color.setFill()
            let circle = NSBezierPath(ovalIn: badgeRect)
            circle.fill()

            NSColor.white.setStroke()
            circle.lineWidth = max(1.5, radius * 0.1)
            circle.stroke()

            let numStr = "\(item.stepNumber)"
            let font = NSFont.boldSystemFont(ofSize: radius * 1.1)
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

        context.restoreGState()
    }

    private func drawArrow(from start: CGPoint, to end: CGPoint, color: NSColor, lineWidth: CGFloat) {
        color.setStroke()
        color.setFill()

        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round

        path.move(to: start)
        path.line(to: end)
        path.stroke()

        // Arrow head
        let headLength = max(12.0, lineWidth * 3.5)
        let headAngle = CGFloat.pi / 6.0 // 30 degrees
        let angle = atan2(end.y - start.y, end.x - start.x)

        let arrowPoint1 = CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )
        let arrowPoint2 = CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )

        let headPath = NSBezierPath()
        headPath.move(to: end)
        headPath.line(to: arrowPoint1)
        headPath.line(to: arrowPoint2)
        headPath.close()
        headPath.fill()
    }
}

extension AnnotationItem {
    func rectInPixelSpace(canvasSize: CGSize) -> CGRect {
        let x1 = startPoint.x * canvasSize.width
        let y1 = startPoint.y * canvasSize.height
        let x2 = endPoint.x * canvasSize.width
        let y2 = endPoint.y * canvasSize.height

        return CGRect(
            x: min(x1, x2),
            y: min(y1, y2),
            width: abs(x2 - x1),
            height: abs(y2 - y1)
        )
    }
}
