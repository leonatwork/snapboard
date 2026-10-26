import AppKit
import XCTest
@testable import Snapboard

@MainActor
final class AnnotationPreviewTests: XCTestCase {
    func testPixelGeometryUsesExistingExportConstantsAtEverySizeAndWidth() async {
        for size in [CGSize(width: 400, height: 300), CGSize(width: 3000, height: 2000)] {
            for width in [CGFloat(2), 4, 7] {
                let item = AnnotationItem(
                    tool: .arrow, startPoint: CGPoint(x: 0.2, y: 0.3),
                    endPoint: CGPoint(x: 0.8, y: 0.7),
                    points: [CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.8, y: 0.7)],
                    color: .red, lineWidth: width
                )
                let layout = AnnotationLayout(item: item, imagePixelSize: size)
                let expectedWidth = max(2, width * size.width / 800)
                XCTAssertEqual(layout.lineWidth, expectedWidth)
                XCTAssertEqual(layout.start, CGPoint(x: size.width * 0.2, y: (1 - 0.3) * size.height))
                XCTAssertEqual(layout.end, CGPoint(x: size.width * 0.8, y: (1 - 0.7) * size.height))
                XCTAssertEqual(layout.points, [layout.start, layout.end])
                XCTAssertEqual(layout.rect, CGRect(
                    x: layout.start.x, y: layout.end.y,
                    width: layout.end.x - layout.start.x, height: layout.start.y - layout.end.y
                ))
                XCTAssertEqual(layout.highlighterWidth, expectedWidth * 3.5)
                XCTAssertEqual(layout.arrowHeadLength, max(14, expectedWidth * 3.5))
                for point in layout.arrowHeadPoints {
                    XCTAssertEqual(hypot(point.x - layout.end.x, point.y - layout.end.y),
                                   layout.arrowHeadLength, accuracy: 0.000001)
                }
                XCTAssertEqual(layout.badgeRadius, max(14, expectedWidth * 3.5))
                XCTAssertEqual(layout.badgeBorderWidth, max(1.5, layout.badgeRadius * 0.1))
                XCTAssertEqual(layout.badgeFontSize, layout.badgeRadius * 1.1)
                XCTAssertEqual(layout.badgeRect.midX, layout.start.x, accuracy: 0.000001)
                XCTAssertEqual(layout.badgeRect.midY, layout.start.y, accuracy: 0.000001)
                XCTAssertEqual(layout.badgeRect.width, layout.badgeRadius * 2)
            }
        }
    }

    func testCompletedPixelationCacheMatchesExportAndTracksUndoRedoAndSource() async throws {
        let image = try sourceImage()
        let model = EditorViewModel(image: image)
        let blur = AnnotationItem(tool: .blur, startPoint: CGPoint(x: 0.1, y: 0.2),
                                  endPoint: CGPoint(x: 0.7, y: 0.8), color: .red, lineWidth: 4)
        model.selectedTool = .blur
        model.startDrawing(at: CGPoint(x: 10, y: 20), in: CGSize(width: 100, height: 100))
        model.updateDrawing(to: CGPoint(x: 70, y: 80), in: CGSize(width: 100, height: 100))
        XCTAssertNil(model.pixelatedPreview)
        model.finishDrawing()
        let cached = try XCTUnwrap(model.pixelatedPreview)
        let exported = try XCTUnwrap(ImageRendererService.shared.render(image: image, annotations: [blur]))
        XCTAssertEqual(try pixels(cached), try pixels(exported))
        XCTAssertNotEqual(try pixels(cached), try pixels(image))

        // Vector edits must not rerun Core Image; undo/redo must not leave stale redactions.
        model.annotations.append(AnnotationItem(tool: .rectangle, startPoint: .zero,
                                               endPoint: CGPoint(x: 1, y: 1), color: .blue, lineWidth: 4))
        XCTAssertTrue(model.pixelatedPreview === cached)
        model.undo()
        XCTAssertNil(model.pixelatedPreview)
        model.redo()
        XCTAssertEqual(try pixels(XCTUnwrap(model.pixelatedPreview)), try pixels(exported))

        // Same ID with changed geometry must invalidate (AnnotationItem equality compares IDs).
        var moved = model.annotations[0]
        moved.endPoint = CGPoint(x: 0.5, y: 0.5)
        model.annotations = [moved]
        let movedExport = try XCTUnwrap(ImageRendererService.shared.render(image: image, annotations: [moved]))
        XCTAssertEqual(try pixels(XCTUnwrap(model.pixelatedPreview)), try pixels(movedExport))
        model.image = try sourceImage(inverted: true)
        let newExport = try XCTUnwrap(ImageRendererService.shared.render(image: model.image, annotations: [moved]))
        XCTAssertEqual(try pixels(XCTUnwrap(model.pixelatedPreview)), try pixels(newExport))
        model.clearAll()
        XCTAssertNil(model.pixelatedPreview)
    }

    private func sourceImage(inverted: Bool = false) throws -> NSImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 80, height: 60, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        for y in 0..<60 {
            for x in 0..<80 {
                let value = CGFloat((x * 17 + y * 31) % 256) / 255
                context.setFillColor(NSColor(srgbRed: inverted ? 1 - value : value,
                                            green: CGFloat(x) / 80, blue: CGFloat(y) / 60, alpha: 1).cgColor)
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: CGSize(width: 40, height: 30))
    }

    private func pixels(_ image: NSImage) throws -> Data {
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8,
            bytesPerRow: cg.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return Data(bytes: try XCTUnwrap(context.data), count: cg.width * cg.height * 4)
    }
}
