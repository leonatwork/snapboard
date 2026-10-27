import AppKit
import SwiftUI
import XCTest
@testable import Snapboard

/// Compares real editor snapshots and controlled bitmap destinations with export.
final class AnnotationRenderingRegressionTests: XCTestCase {
    @MainActor
    func testUnannotatedRetinaPreviewPreservesSourcePixelsAtOddAndEvenWindowSizes() async throws {
        for size in [CGSize(width: 900, height: 700), CGSize(width: 901, height: 701)] {
            try assertEditorMatchesExport(tool: nil, windowSize: size)
        }
    }

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

    @MainActor
    func testSmallRetinaRectanglePreviewHasExportStrokeWidth() async throws {
        try assertEditorMatchesExport(tool: .rectangle)
    }

    @MainActor
    func testCompletedPixelationPreviewShowsExportPixelsInsteadOfGrayBox() async throws {
        try assertEditorMatchesExport(tool: .blur)
    }

    @MainActor
    func testSmallRetinaVectorToolsMatchExportAtEverySelectableWidth() async throws {
        for tool in [AnnotationTool.rectangle, .circle, .arrow, .pen, .highlighter, .stepNumber] {
            for width in [CGFloat(2), 4, 7] {
                try assertEditorMatchesExport(tool: tool, lineWidth: width)
            }
        }
    }

    @MainActor
    func testRetinaPreviewMatchesExportIndependentlyOfScreenBackingScale() async throws {
        for displayScale in [CGFloat(1), 2] {
            for tool in [AnnotationTool.rectangle, .highlighter, .stepNumber, .blur] {
                try assertEditorMatchesExport(tool: tool, displayScale: displayScale)
            }
        }
    }

    @MainActor
    func testVectorDraftUsesTheSameRenderingAsCompletedAnnotations() async throws {
        for tool in [AnnotationTool.arrow, .pen, .highlighter] {
            try assertEditorMatchesExport(tool: tool, isDraft: true)
        }
    }

    @MainActor
    private func assertEditorMatchesExport(
        tool: AnnotationTool?, lineWidth: CGFloat = 4, displayScale: CGFloat? = nil, isDraft: Bool = false,
        windowSize: CGSize = CGSize(width: 900, height: 700)
    ) throws {
        _ = NSApplication.shared
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        // Texture entirely within the annotation, leaving the canvas center white for locating it.
        context.setFillColor(NSColor.black.cgColor)
        for x in stride(from: 44, to: 156, by: 6) {
            context.fill(CGRect(x: x, y: 184, width: 2, height: 82))
        }
        let image = NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: CGSize(width: 200, height: 150))
        let item = AnnotationItem(tool: tool ?? .rectangle, startPoint: CGPoint(x: 0.1, y: 0.1),
                                  endPoint: CGPoint(x: 0.4, y: 0.4),
                                  points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.25, y: 0.32),
                                           CGPoint(x: 0.4, y: 0.4)],
                                  color: .red, lineWidth: lineWidth, stepNumber: 12)
        let model = EditorViewModel(image: image)
        if tool == nil {
            model.annotations = []
        } else if isDraft {
            model.currentDraft = item
        } else {
            model.annotations = [item]
        }
        let editor = EditorView(viewModel: model)
        let root = displayScale.map { AnyView(editor.environment(\.displayScale, $0)) } ?? AnyView(editor)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.setContentSize(windowSize)
        window.appearance = NSAppearance(named: .aqua)
        let view = try XCTUnwrap(window.contentView)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(windowSize.width * 2), pixelsHigh: Int(windowSize.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        func isDark(x: Int, y: Int) -> Bool {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return true }
            return c.redComponent < 0.16 && c.greenComponent < 0.16 && c.blueComponent < 0.16
        }
        let cx = rep.pixelsWide / 2, cy = rep.pixelsHigh / 2
        XCTAssertFalse(isDark(x: cx, y: cy), "Canvas center must be white")
        var left = cx, top = cy
        while left > 0 && !isDark(x: left - 1, y: cy) { left -= 1 }
        while top > 0 && !isDark(x: cx, y: top - 1) { top -= 1 }
        let crop = try XCTUnwrap(rep.cgImage?.cropping(to: CGRect(x: left, y: top, width: 400, height: 300)))
        let preview = NSBitmapImageRep(cgImage: crop)
        let exported = try XCTUnwrap(ImageRendererService.shared.render(image: image, annotations: tool == nil ? [] : [item]))
        let exportCG = try XCTUnwrap(exported.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let expected = NSBitmapImageRep(cgImage: exportCG)
        let source = NSBitmapImageRep(cgImage: try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        var totalDifference: CGFloat = 0
        var changedPixels = 0
        func difference(_ a: NSColor, _ b: NSColor) -> CGFloat {
            max(abs(a.redComponent - b.redComponent),
                max(abs(a.greenComponent - b.greenComponent), abs(a.blueComponent - b.blueComponent)))
        }
        // Region includes the whole annotation and a margin: thicker preview edges count too.
        for y in 6..<144 {
            for x in 6..<184 {
                let a = try XCTUnwrap(expected.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let b = try XCTUnwrap(preview.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let original = try XCTUnwrap(source.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                // Do not dilute a wrong arrowhead or badge with thousands of unchanged pixels.
                if tool == nil || difference(a, original) > 24.0 / 255 || difference(b, original) > 24.0 / 255 {
                    totalDifference += difference(a, b)
                    changedPixels += 1
                }
            }
        }
        let toolName = tool?.rawValue ?? "source image"
        XCTAssertGreaterThan(changedPixels, 0, "Fixture must draw \(toolName)")
        XCTAssertLessThan(totalDifference / CGFloat(max(1, changedPixels)), 4.0 / 255,
                          "The real editor preview must match \(toolName) at width \(lineWidth)")
    }
}
