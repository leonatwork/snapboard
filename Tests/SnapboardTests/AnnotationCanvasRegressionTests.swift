import AppKit
import XCTest
@testable import Snapboard

// Keep new canvas APIs out of AnnotationRenderingRegressionTests.swift so that
// that file alone can run against the pre-issue implementation for the red proof.
extension AnnotationRenderingRegressionTests {
    @MainActor
    func testFractionalCanvasOriginDoesNotResampleNativeRetinaPixels() async throws {
        _ = NSApplication.shared
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let source = try XCTUnwrap(CGContext(
            data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        source.setFillColor(NSColor.white.cgColor)
        source.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        source.setFillColor(NSColor.black.cgColor)
        for x in stride(from: 0, to: 400, by: 6) {
            source.fill(CGRect(x: x, y: 0, width: 2, height: 300))
        }
        let image = NSImage(cgImage: try XCTUnwrap(source.makeImage()), size: CGSize(width: 200, height: 150))
        let model = EditorViewModel(image: image)
        let canvas = AnnotationCanvasView(frame: CGRect(origin: .zero, size: image.size))
        let destinationSpaces = [space, try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))]
        for destinationSpace in destinationSpaces {
            for tool in [AnnotationTool.rectangle, .highlighter, .stepNumber, .blur] {
                model.annotations = [AnnotationItem(
                    tool: tool, startPoint: CGPoint(x: 0.1, y: 0.1), endPoint: CGPoint(x: 0.4, y: 0.4),
                    points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.4, y: 0.4)],
                    color: .red, lineWidth: 4, stepNumber: 12
                )]
                // Mirrors updateNSView, including invalidation when the same model changes.
                canvas.viewModel = model
                let destination = try XCTUnwrap(CGContext(
                    data: nil, width: 408, height: 308, bitsPerComponent: 8, bytesPerRow: 0,
                    space: destinationSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                // Simulate a 2x snapshot with a SwiftUI layout origin an eighth device pixel
                // off the grid. The source and annotation must share the snapped pixel grid.
                destination.translateBy(x: 0, y: 308)
                destination.scaleBy(x: 1, y: -1)
                destination.translateBy(x: 2.125, y: 2.125)
                destination.scaleBy(x: 2, y: 2)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: destination, flipped: true)
                canvas.draw(canvas.bounds)
                NSGraphicsContext.restoreGraphicsState()

                // Translation precedes the 2x scale, so the snapped bitmap offset is (2, 2).
                let previewCG = try XCTUnwrap(destination.makeImage()?.cropping(to: CGRect(x: 2, y: 2, width: 400, height: 300)))
                let preview = NSBitmapImageRep(cgImage: previewCG)
                let exported = try XCTUnwrap(ImageRendererService.shared.render(image: image, annotations: model.annotations))
                let exportCG = try XCTUnwrap(exported.cgImage(forProposedRect: nil, context: nil, hints: nil))
                // Color-manage the independent export into the same destination. Rendering
                // translucent vectors directly there would blend in a different color space.
                let reference = try XCTUnwrap(CGContext(
                    data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                    space: destinationSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                reference.draw(exportCG, in: CGRect(x: 0, y: 0, width: 400, height: 300))
                let expected = NSBitmapImageRep(cgImage: try XCTUnwrap(reference.makeImage()))
                var maximumDifference: CGFloat = 0
                for y in 0..<300 {
                    for x in 0..<400 {
                        let a = try XCTUnwrap(expected.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                        let b = try XCTUnwrap(preview.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                        maximumDifference = max(maximumDifference, max(abs(a.redComponent - b.redComponent),
                            max(abs(a.greenComponent - b.greenComponent), abs(a.blueComponent - b.blueComponent))))
                    }
                }
                XCTAssertLessThan(maximumDifference, 4.0 / 255, "Fractional origin must preserve every \(tool.rawValue) pixel")
            }
        }
    }
}
