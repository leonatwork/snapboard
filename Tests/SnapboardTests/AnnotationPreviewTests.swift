import AppKit
import XCTest
@testable import Snapboard

final class AnnotationPreviewTests: XCTestCase {
    @MainActor
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

    @MainActor
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

    @MainActor
    func testOverlappingPixelationsUseExportSourceAndKeepVectorsOutOfCache() async throws {
        let image = try sourceImage(width: 400, height: 300)
        let model = EditorViewModel(image: image)
        let first = AnnotationItem(tool: .blur, startPoint: CGPoint(x: 0.1, y: 0.1),
                                   endPoint: CGPoint(x: 0.7, y: 0.8), color: .red, lineWidth: 4)
        let second = AnnotationItem(tool: .blur, startPoint: CGPoint(x: 0.35, y: 0.3),
                                    endPoint: CGPoint(x: 0.95, y: 0.95), color: .red, lineWidth: 4)
        let vector = AnnotationItem(tool: .highlighter, startPoint: first.startPoint,
                                    endPoint: second.endPoint,
                                    points: [first.startPoint, second.endPoint],
                                    color: .yellow, lineWidth: 7)
        func assertCachedExport(_ blurs: [AnnotationItem]) throws {
            let expected = try XCTUnwrap(ImageRendererService.shared.render(image: image, annotations: blurs))
            XCTAssertEqual(try pixels(XCTUnwrap(model.pixelatedPreview)), try pixels(expected))
        }

        // Export applies every blur to the original source, below vectors, even when
        // the user added a vector before the last blur. Differently sized overlapping
        // regions also exercise distinct block sizes and cache ordering.
        model.annotations = [first, vector, second]
        try assertCachedExport([first, second])
        let cached = try XCTUnwrap(model.pixelatedPreview)
        model.annotations = [vector, first, second]
        XCTAssertTrue(model.pixelatedPreview === cached)
        model.saveForUndo()
        model.annotations = [second, vector, first]
        try assertCachedExport([second, first])
        XCTAssertNotEqual(try pixels(XCTUnwrap(model.pixelatedPreview)), try pixels(cached),
                          "Fixture must expose the different overlapping block sizes")
        model.undo()
        try assertCachedExport([first, second])
        model.redo()
        try assertCachedExport([second, first])
        model.clearAll()
        XCTAssertNil(model.pixelatedPreview)
        model.undo()
        try assertCachedExport([second, first])
    }

    @MainActor
    private func sourceImage(inverted: Bool = false, width: Int = 80, height: Int = 60) throws -> NSImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        for y in 0..<height {
            for x in 0..<width {
                let value = CGFloat((x * 17 + y * 31) % 256) / 255
                context.setFillColor(NSColor(srgbRed: inverted ? 1 - value : value,
                                            green: CGFloat(x) / CGFloat(width), blue: CGFloat(y) / CGFloat(height), alpha: 1).cgColor)
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return NSImage(cgImage: try XCTUnwrap(context.makeImage()),
                       size: CGSize(width: CGFloat(width) / 2, height: CGFloat(height) / 2))
    }

    @MainActor
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
