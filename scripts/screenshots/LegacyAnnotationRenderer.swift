// Frozen export oracle from origin/main 2306fc6, before issue #8.
// Keep independent of AnnotationLayout and the new renderer. TextAnnotationLayout is
// deliberately unchanged by this issue; only that existing text implementation is reused.
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

@MainActor
final class LegacyAnnotationRenderer {
    private let ciContext = CIContext()

    func render(image: NSImage, annotations: [AnnotationItem]) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let pixelWidth = cgImage.width, pixelHeight = cgImage.height
        guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight,
                  bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        for item in annotations where item.tool == .blur {
            let pW = CGFloat(pixelWidth), pH = CGFloat(pixelHeight)
            let y1 = (1.0 - item.startPoint.y) * pH, y2 = (1.0 - item.endPoint.y) * pH
            let x1 = item.startPoint.x * pW, x2 = item.endPoint.x * pW
            let rect = CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
            guard rect.width > 2 && rect.height > 2 else { continue }
            let pixellate = CIFilter.pixellate()
            pixellate.inputImage = CIImage(cgImage: cgImage)
            pixellate.scale = Float(max(8.0, min(rect.width, rect.height) / 8.0))
            if let output = pixellate.outputImage,
               let blurred = ciContext.createCGImage(output.cropped(to: rect), from: rect) {
                context.saveGState()
                context.draw(blurred, in: rect)
                context.restoreGState()
            }
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for item in annotations where item.tool != .blur {
            draw(item, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let result = context.makeImage() else { return nil }
        return NSImage(cgImage: result, size: image.size)
    }

    private func draw(_ item: AnnotationItem, pixelWidth: Int, pixelHeight: Int) {
        let pW = CGFloat(pixelWidth), pH = CGFloat(pixelHeight)
        let start = CGPoint(x: item.startPoint.x * pW, y: (1.0 - item.startPoint.y) * pH)
        let end = CGPoint(x: item.endPoint.x * pW, y: (1.0 - item.endPoint.y) * pH)
        let color = item.color.nsColor
        let lineWidth = max(2.0, item.lineWidth * (pW / 800.0))
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))
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
            color.setStroke()
            color.setFill()
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.move(to: start)
            path.line(to: end)
            path.stroke()
            let headLength = max(14.0, lineWidth * 3.5)
            let headAngle = CGFloat.pi / 6.0
            let angle = atan2(end.y - start.y, end.x - start.x)
            let pt1 = CGPoint(x: end.x - headLength * cos(angle - headAngle),
                              y: end.y - headLength * sin(angle - headAngle))
            let pt2 = CGPoint(x: end.x - headLength * cos(angle + headAngle),
                              y: end.y - headLength * sin(angle + headAngle))
            let head = NSBezierPath()
            head.move(to: end)
            head.line(to: pt1)
            head.line(to: pt2)
            head.close()
            head.fill()
        case .pen:
            guard item.points.count > 1 else { break }
            color.setStroke()
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: CGPoint(x: item.points[0].x * pW, y: (1.0 - item.points[0].y) * pH))
            for pt in item.points.dropFirst() {
                path.line(to: CGPoint(x: pt.x * pW, y: (1.0 - pt.y) * pH))
            }
            path.stroke()
        case .highlighter:
            guard item.points.count > 1 else { break }
            color.withAlphaComponent(0.4).setStroke()
            let path = NSBezierPath()
            path.lineWidth = lineWidth * 3.5
            path.lineCapStyle = .square
            path.lineJoinStyle = .miter
            path.move(to: CGPoint(x: item.points[0].x * pW, y: (1.0 - item.points[0].y) * pH))
            for pt in item.points.dropFirst() {
                path.line(to: CGPoint(x: pt.x * pW, y: (1.0 - pt.y) * pH))
            }
            path.stroke()
        case .text:
            TextAnnotationLayout(item: item, imagePixelSize: CGSize(width: pW, height: pH))?.draw(flipped: false)
        case .stepNumber:
            let radius = max(14.0, lineWidth * 3.5)
            let badgeRect = CGRect(x: start.x - radius, y: start.y - radius, width: radius * 2, height: radius * 2)
            color.setFill()
            let circle = NSBezierPath(ovalIn: badgeRect)
            circle.fill()
            NSColor.white.setStroke()
            circle.lineWidth = max(1.5, radius * 0.1)
            circle.stroke()
            let str = NSAttributedString(string: "\(item.stepNumber)", attributes: [
                .font: NSFont.boldSystemFont(ofSize: radius * 1.1), .foregroundColor: NSColor.white
            ])
            let size = str.size()
            str.draw(at: CGPoint(x: badgeRect.midX - size.width / 2.0, y: badgeRect.midY - size.height / 2.0))
        case .blur:
            break
        }
    }
}
