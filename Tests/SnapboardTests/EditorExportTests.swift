import AppKit
import ImageIO
import XCTest
@testable import Snapboard

final class EditorExportTests: XCTestCase {
    func testExportGeometryRetainsIndependentPointAndPixelDimensions() throws {
        let geometry = try XCTUnwrap(ImageExportGeometry(
            pointSize: CGSize(width: 80.5, height: 50.5), pixelWidth: 161, pixelHeight: 101
        ))
        XCTAssertEqual(geometry.pointSize, CGSize(width: 80.5, height: 50.5))
        XCTAssertEqual(geometry.pixelWidth, 161)
        XCTAssertEqual(geometry.pixelHeight, 101)
        XCTAssertNil(ImageExportGeometry(pointSize: .zero, pixelWidth: 160, pixelHeight: 100))
        XCTAssertNil(ImageExportGeometry(pointSize: CGSize(width: CGFloat.infinity, height: 50),
                                        pixelWidth: 160, pixelHeight: 100))
    }

    func testRendererPreservesSourcePointSizeAndPixelsAt1xAnd2x() async throws {
        try await MainActor.run {
            for scale in [1.0, 2.0] {
                let source = try makeImage(scale: scale)
                let annotation = makeAnnotation()
                for annotations in [[], [annotation]] {
                    let rendered = try XCTUnwrap(ImageRendererService.shared.render(
                        image: source, annotations: annotations
                    ))
                    XCTAssertEqual(rendered.size, source.size)
                    let cgImage = try XCTUnwrap(rendered.cgImage(
                        forProposedRect: nil, context: nil, hints: nil
                    ))
                    XCTAssertEqual(cgImage.width, 160)
                    XCTAssertEqual(cgImage.height, 100)
                }
            }
        }
    }

    func testCopyPublishesPNGFirstAndTIFFFallbackWithSourceResolution() async throws {
        try await MainActor.run {
            for scale in [1.0, 2.0] {
                for annotations in [[], [makeAnnotation()]] {
                    let pasteboard = NSPasteboard.withUniqueName()
                    defer { pasteboard.releaseGlobally() }
                    let model = EditorViewModel(image: try makeImage(scale: scale))
                    model.pasteboard = pasteboard
                    model.annotations = annotations
                    var closed = false
                    model.onClose = { closed = true }
                    model.presentExportError = { _, error in
                        XCTFail("Unexpected export error: \(error)")
                    }

                    model.copyToClipboardAndClose()

                    XCTAssertTrue(closed)
                    // AppKit also advertises legacy aliases; check the canonical formats and their order.
                    let exportTypes = try XCTUnwrap(pasteboard.types).filter { $0 == .png || $0 == .tiff }
                    XCTAssertEqual(exportTypes, [.png, .tiff])
                    for type in [NSPasteboard.PasteboardType.png, .tiff] {
                        try assertResolution(try XCTUnwrap(pasteboard.data(forType: type)), scale: scale)
                    }
                }
            }
        }
    }

    func testSavePreservesPixelsAndDPIWithoutClosingEditor() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: directory) }
            for scale in [1.0, 2.0] {
                let url = directory.appendingPathComponent("export-\(scale).png")
                let model = EditorViewModel(image: try makeImage(scale: scale))
                model.annotations = [makeAnnotation()]
                model.selectSaveURL = { url }
                model.onClose = { XCTFail("Saving must keep the editor open") }
                model.presentExportError = { _, error in
                    XCTFail("Unexpected export error: \(error)")
                }

                model.saveAsFile()

                try assertResolution(Data(contentsOf: url), scale: scale)
                XCTAssertEqual(model.annotations.count, 1)
            }
        }
    }

    func testRenderFailureReportsErrorForCopyAndSaveAndPreservesState() async throws {
        try await MainActor.run {
            let pasteboard = NSPasteboard.withUniqueName()
            defer { pasteboard.releaseGlobally() }
            pasteboard.setString("previous clipboard", forType: .string)
            let model = EditorViewModel(image: NSImage(size: NSSize(width: 80, height: 50)))
            model.pasteboard = pasteboard
            let annotation = makeAnnotation()
            model.annotations = [annotation]
            model.undoStack = [[annotation]]
            model.onClose = { XCTFail("Render failure must keep the editor open") }
            model.selectSaveURL = { XCTFail("Render failure must not open a save panel"); return nil }
            var errors: [Error] = []
            model.presentExportError = { _, error in errors.append(error) }

            model.copyToClipboardAndClose()
            model.saveAsFile()

            XCTAssertEqual(errors.count, 2)
            XCTAssertTrue(errors.allSatisfy { ($0 as? EditorExportError) == .renderFailed })
            XCTAssertEqual(model.annotations, [annotation])
            XCTAssertEqual(model.undoStack, [[annotation]])
            XCTAssertEqual(pasteboard.string(forType: .string), "previous clipboard")
        }
    }

    func testWriteFailureReportsSystemErrorAndPreservesAnnotations() async throws {
        try await MainActor.run {
            let model = EditorViewModel(image: try makeImage(scale: 2))
            let annotation = makeAnnotation()
            model.annotations = [annotation]
            model.undoStack = [[annotation]]
            // A nonexistent parent fails deterministically, even when tests run as root.
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathComponent("export.png")
            model.selectSaveURL = { url }
            model.onClose = { XCTFail("Write failure must keep the editor open") }
            var reportedError: NSError?
            model.presentExportError = { title, error in
                XCTAssertEqual(title, L10n.tr("editor.export.saveFailed"))
                reportedError = error as NSError
            }

            model.saveAsFile()

            let error = try XCTUnwrap(reportedError)
            XCTAssertEqual(error.domain, NSCocoaErrorDomain)
            XCTAssertFalse(error.localizedDescription.isEmpty)
            XCTAssertEqual(model.annotations, [annotation])
            XCTAssertEqual(model.undoStack, [[annotation]])
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testCancelSaveLeavesEditorAndAnnotationsOpen() async throws {
        try await MainActor.run {
            let model = EditorViewModel(image: try makeImage(scale: 2))
            let annotation = makeAnnotation()
            model.annotations = [annotation]
            model.selectSaveURL = { nil }
            model.onClose = { XCTFail("Cancelling save must keep the editor open") }
            model.presentExportError = { _, _ in XCTFail("Cancellation is not an error") }
            model.saveAsFile()
            XCTAssertEqual(model.annotations, [annotation])
        }
    }

    @MainActor
    private func makeImage(scale: Double) throws -> NSImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 160, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 160, height: 100))
        return NSImage(cgImage: try XCTUnwrap(context.makeImage()),
                       size: NSSize(width: 160 / scale, height: 100 / scale))
    }

    private func makeAnnotation() -> AnnotationItem {
        AnnotationItem(tool: .rectangle, startPoint: CGPoint(x: 0.2, y: 0.2),
                       endPoint: CGPoint(x: 0.8, y: 0.8), color: .red, lineWidth: 4)
    }

    private func assertResolution(_ data: Data, scale: Double,
                                  file: StaticString = #filePath, line: UInt = #line) throws {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil), file: file, line: line)
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [CFString: Any], file: file, line: line)
        XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, 160, file: file, line: line)
        XCTAssertEqual((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, 100, file: file, line: line)
        // PNG pHYs stores integral pixels/metre, so DPI has a small rounding tolerance.
        for key in [kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] {
            let dpi = try XCTUnwrap(properties[key] as? NSNumber, file: file, line: line)
            XCTAssertEqual(dpi.doubleValue, 72 * scale, accuracy: 0.02, file: file, line: line)
        }
    }
}
