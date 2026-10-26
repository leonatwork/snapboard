import AppKit
import ImageIO
import XCTest
@testable import Snapboard

@MainActor
final class EditorExportTests: XCTestCase {
    private let pixelWidth = 320
    private let pixelHeight = 180

    private var annotation: AnnotationItem {
        AnnotationItem(
            tool: .rectangle,
            startPoint: CGPoint(x: 0.2, y: 0.2),
            endPoint: CGPoint(x: 0.8, y: 0.8),
            color: .red,
            lineWidth: 4
        )
    }

    private func sourceImage(scale: CGFloat) throws -> NSImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: pixelWidth, height: pixelHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        return NSImage(
            cgImage: try XCTUnwrap(context.makeImage()),
            size: NSSize(width: CGFloat(pixelWidth) / scale, height: CGFloat(pixelHeight) / scale)
        )
    }

    private func assertEncodedImage(
        _ data: Data, scale: CGFloat,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil), file: file, line: line)
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
            file: file, line: line
        )
        XCTAssertEqual((properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue, pixelWidth, file: file, line: line)
        XCTAssertEqual((properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue, pixelHeight, file: file, line: line)
        // PNG stores pixels/metre as integers; allow the resulting small DPI rounding error.
        let dpiWidth = try XCTUnwrap(properties[kCGImagePropertyDPIWidth as String] as? NSNumber, file: file, line: line)
        let dpiHeight = try XCTUnwrap(properties[kCGImagePropertyDPIHeight as String] as? NSNumber, file: file, line: line)
        XCTAssertEqual(dpiWidth.doubleValue, Double(72 * scale), accuracy: 0.02, file: file, line: line)
        XCTAssertEqual(dpiHeight.doubleValue, Double(72 * scale), accuracy: 0.02, file: file, line: line)
    }

    func testRenderPreservesSourcePointSizeAndPixelsAtRetinaAnd1x() async throws {
        for scale in [CGFloat(1), CGFloat(2)] {
            let image = try sourceImage(scale: scale)
            for annotations in [[], [annotation]] {
                let rendered = try XCTUnwrap(ImageRendererService.shared.render(image: image, annotations: annotations))
                XCTAssertEqual(rendered.size, image.size)
                let pixels = try XCTUnwrap(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil))
                XCTAssertEqual(pixels.width, pixelWidth)
                XCTAssertEqual(pixels.height, pixelHeight)
            }
        }
    }

    func testCopyPublishesPNGFirstAndTIFFFallbackWithSourceResolution() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        for scale in [CGFloat(1), CGFloat(2)] {
            for annotations in [[], [annotation]] {
                var errors: [Error] = []
                var closed = false
                let model = EditorViewModel(
                    image: try sourceImage(scale: scale), pasteboard: pasteboard,
                    presentExportError: { errors.append($0) }
                )
                model.annotations = annotations
                model.onClose = { closed = true }

                model.copyToClipboardAndClose()

                XCTAssertTrue(closed)
                XCTAssertTrue(errors.isEmpty)
                let types = try XCTUnwrap(pasteboard.types)
                // AppKit may add aliases; only require our two formats and their relative order.
                let pngIndex = try XCTUnwrap(types.firstIndex(of: .png))
                let tiffIndex = try XCTUnwrap(types.firstIndex(of: .tiff))
                XCTAssertLessThan(pngIndex, tiffIndex)
                XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
                try assertEncodedImage(try XCTUnwrap(pasteboard.data(forType: .png)), scale: scale)
                try assertEncodedImage(try XCTUnwrap(pasteboard.data(forType: .tiff)), scale: scale)
            }
        }
    }

    func testSaveWritesPNGWithSourcePixelsAndResolution() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for scale in [CGFloat(1), CGFloat(2)] {
            let url = directory.appendingPathComponent("export.png")
            var errors: [Error] = []
            var closed = false
            let model = EditorViewModel(
                image: try sourceImage(scale: scale),
                presentExportError: { errors.append($0) }, chooseSaveURL: { url }
            )
            model.annotations = [annotation]
            model.onClose = { closed = true }

            model.saveAsFile()

            XCTAssertTrue(errors.isEmpty)
            XCTAssertFalse(closed)
            let data = try Data(contentsOf: url)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.png")
            try assertEncodedImage(data, scale: scale)
        }
    }

    func testCopyRenderFailureReportsErrorAndPreservesEditorAndClipboard() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("existing clipboard", forType: .string)
        var errors: [Error] = []
        var closed = false
        let model = EditorViewModel(
            image: NSImage(size: .zero), pasteboard: pasteboard,
            presentExportError: { errors.append($0) }
        )
        model.annotations = [annotation]
        model.undoStack = [model.annotations]
        model.onClose = { closed = true }

        model.copyToClipboardAndClose()

        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors.first?.localizedDescription, L10n.tr("editor.exportError.rendering"))
        XCTAssertFalse(closed)
        XCTAssertEqual(model.annotations.count, 1)
        XCTAssertEqual(model.undoStack.count, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "existing clipboard")
    }

    func testSaveRenderFailureReportsErrorBeforeOpeningSavePanel() async {
        var errors: [Error] = []
        var choseURL = false
        var closed = false
        let model = EditorViewModel(
            image: NSImage(size: .zero),
            presentExportError: { errors.append($0) },
            chooseSaveURL: { choseURL = true; return nil }
        )
        model.annotations = [annotation]
        model.onClose = { closed = true }

        model.saveAsFile()

        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors.first?.localizedDescription, L10n.tr("editor.exportError.rendering"))
        XCTAssertFalse(choseURL)
        XCTAssertFalse(closed)
        XCTAssertEqual(model.annotations.count, 1)
    }

    func testWriteFailureReportsSystemErrorAndPreservesAnnotationsAndUndo() async throws {
        // A missing parent fails even when the tests run with elevated filesystem permissions.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("export.png")
        var errors: [Error] = []
        var closed = false
        let model = EditorViewModel(
            image: try sourceImage(scale: 2),
            presentExportError: { errors.append($0) }, chooseSaveURL: { url }
        )
        let annotations = [annotation]
        model.annotations = annotations
        model.undoStack = [annotations]
        model.onClose = { closed = true }

        model.saveAsFile()

        XCTAssertEqual(errors.count, 1)
        let error = try XCTUnwrap(errors.first) as NSError
        XCTAssertEqual(error.domain, NSCocoaErrorDomain)
        XCTAssertFalse(error.localizedDescription.isEmpty)
        XCTAssertFalse(closed)
        XCTAssertEqual(model.annotations, annotations)
        XCTAssertEqual(model.undoStack, [annotations])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testCancelSaveDoesNotReportErrorOrClose() async throws {
        var errors: [Error] = []
        var closed = false
        let model = EditorViewModel(
            image: try sourceImage(scale: 2),
            presentExportError: { errors.append($0) }, chooseSaveURL: { nil }
        )
        model.onClose = { closed = true }

        model.saveAsFile()

        XCTAssertTrue(errors.isEmpty)
        XCTAssertFalse(closed)
    }
}
