import AppKit
import SwiftUI
import XCTest
@testable import Snapboard

/// Uses only APIs already present on origin/main, so these behavioral regressions can
/// also be run against 2306fc6 without introducing the new layout/cache implementation.
@MainActor
final class AnnotationRenderingRegressionTests: XCTestCase {
    func testSmallRetinaRectanglePreviewHasExportStrokeWidth() async throws {
        try assertEditorMatchesExport(tool: .rectangle)
    }

    func testCompletedPixelationPreviewShowsExportPixelsInsteadOfGrayBox() async throws {
        try assertEditorMatchesExport(tool: .blur)
    }

    func testSmallRetinaVectorToolsMatchExportAtEverySelectableWidth() async throws {
        for tool in [AnnotationTool.rectangle, .circle, .arrow, .pen, .highlighter, .stepNumber] {
            for width in [CGFloat(2), 4, 7] {
                try assertEditorMatchesExport(tool: tool, lineWidth: width)
            }
        }
    }

    private func assertEditorMatchesExport(tool: AnnotationTool, lineWidth: CGFloat = 4) throws {
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
        let item = AnnotationItem(tool: tool, startPoint: CGPoint(x: 0.1, y: 0.1),
                                  endPoint: CGPoint(x: 0.4, y: 0.4),
                                  points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.25, y: 0.32),
                                           CGPoint(x: 0.4, y: 0.4)],
                                  color: .red, lineWidth: lineWidth, stepNumber: 12)
        let model = EditorViewModel(image: image)
        model.annotations = [item]
        let hosting = NSHostingController(rootView: EditorView(viewModel: model))
        let window = NSWindow(contentViewController: hosting)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.setContentSize(CGSize(width: 900, height: 700))
        window.appearance = NSAppearance(named: .aqua)
        let view = try XCTUnwrap(window.contentView)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1800, pixelsHigh: 1400,
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
        let exported = try XCTUnwrap(ImageRendererService.shared.render(image: image, annotations: [item]))
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
                if difference(a, original) > 24.0 / 255 || difference(b, original) > 24.0 / 255 {
                    totalDifference += difference(a, b)
                    changedPixels += 1
                }
            }
        }
        XCTAssertGreaterThan(changedPixels, 0, "Fixture must draw \(tool.rawValue)")
        XCTAssertLessThan(totalDifference / CGFloat(max(1, changedPixels)), 4.0 / 255,
                          "The real editor preview must match \(tool.rawValue) at width \(lineWidth)")
    }
}
