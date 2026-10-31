import AppKit
import XCTest
@testable import Snapboard

@MainActor
final class OCRTests: XCTestCase {
    func testReadingOrderWhitespaceAndRedactionArePure() async {
        let lines = [
            OCRLine(text: " Zweite Zeile ", bounds: CGRect(x: 0, y: 30, width: 80, height: 10)),
            OCRLine(text: "rechts", bounds: CGRect(x: 100, y: 1, width: 80, height: 10)),
            OCRLine(text: " links ", bounds: CGRect(x: 0, y: 2, width: 80, height: 10)),
            OCRLine(text: "geheim", bounds: CGRect(x: 0, y: 50, width: 80, height: 10)),
            OCRLine(text: " \n ", bounds: .zero)
        ]
        let redactions = [CGRect(x: 40, y: 50, width: 10, height: 10)]
        XCTAssertEqual(OCRTextProcessing.text(from: lines, excluding: redactions), "links\nrechts\nZweite Zeile")
        XCTAssertEqual(OCRTextProcessing.text(from: Array(lines.reversed()), excluding: redactions), "links\nrechts\nZweite Zeile")
        XCTAssertEqual(OCRTextProcessing.text(from: []), "")
    }

    private func image() throws -> NSImage {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120,
            pixelsHigh: 60, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<60 {
            for x in 0..<120 { bitmap.setColor(x.isMultiple(of: 2) ? .white : .black, atX: x, y: y) }
        }
        return NSImage(cgImage: try XCTUnwrap(bitmap.cgImage), size: CGSize(width: 60, height: 30))
    }

    func testCopyReplacesImageWithPlainTextAndEmptyOrFailurePreservesClipboard() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var lines = [OCRLine(text: "Grüße\nHello", bounds: CGRect(x: 0, y: 0, width: 80, height: 10))]
        var notices: [Error] = []
        let service = OCRService(pasteboard: board, recognize: { _ in lines }, presentError: { notices.append($0) })
        board.writeObjects([try image()])
        await service.copyText(from: try image())
        XCTAssertEqual(board.string(forType: .string), "Grüße\nHello")
        XCTAssertTrue(board.types?.contains(.string) == true)
        XCTAssertNil(board.data(forType: .png))
        XCTAssertNil(board.data(forType: .tiff))
        XCTAssertTrue(notices.isEmpty)
        let count = board.changeCount
        lines = []
        await service.copyText(from: try image())
        XCTAssertEqual(board.changeCount, count)
        XCTAssertEqual(notices.count, 1)
        let failure = OCRService(pasteboard: board,
            recognize: { _ in throw OCRFailure.recognitionFailed }, presentError: { notices.append($0) })
        await failure.copyText(from: try image())
        XCTAssertEqual(board.changeCount, count)
        XCTAssertEqual(notices.count, 2)
    }

    func testEditorPassesRenderedPixelsAndExcludesRedactedLinesWithoutClosing() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let source = try image()
        var received: CGImage?
        let service = OCRService(pasteboard: board, recognize: { pixels in
            received = pixels
            return [OCRLine(text: "secret", bounds: CGRect(x: 10, y: 10, width: 20, height: 10)),
                    OCRLine(text: "visible", bounds: CGRect(x: 80, y: 10, width: 20, height: 10))]
        }, presentError: { _ in XCTFail("Visible text should be copied") })
        let model = EditorViewModel(image: source, ocrService: service)
        model.annotations = [AnnotationItem(tool: .blur,
            startPoint: .zero, endPoint: CGPoint(x: 0.5, y: 1), color: .red, lineWidth: 4)]
        model.onClose = { XCTFail("Text copy keeps the editor open") }
        await model.copyText()
        let actual = try XCTUnwrap(received)
        let rendered = try XCTUnwrap(ImageRendererService.shared.render(image: source, annotations: model.annotations))
        let expected = try XCTUnwrap(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(actual.width, 120)
        XCTAssertEqual(actual.height, 60)
        let actualBitmap = NSBitmapImageRep(cgImage: actual)
        let expectedBitmap = NSBitmapImageRep(cgImage: expected)
        for y in 0..<60 {
            for x in 0..<120 { XCTAssertEqual(actualBitmap.colorAt(x: x, y: y), expectedBitmap.colorAt(x: x, y: y)) }
        }
        XCTAssertEqual(board.string(forType: .string), "visible")
        XCTAssertEqual(model.annotations.count, 1)
    }

    func testThirdHotkeyDoesNotChangeExistingDispatch() async {
        var triggers: [Int] = []
        let manager = HotKeyManager.shared
        manager.onTriggerDirect = { triggers.append(1) }
        manager.onTriggerEdit = { triggers.append(2) }
        manager.onTriggerText = { triggers.append(3) }
        defer {
            manager.onTriggerDirect = nil
            manager.onTriggerEdit = nil
            manager.onTriggerText = nil
        }
        for id in [UInt32(1), 2, 3, 999] { manager.handleHotKeyTriggered(id: id) }
        XCTAssertEqual(triggers, [1, 2, 3])
    }

    func testPendingOCRRejectsReentryWithoutChangingClipboard() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var continuation: CheckedContinuation<[OCRLine], Never>?
        var requests = 0
        let service = OCRService(pasteboard: board, recognize: { _ in
            requests += 1
            return await withCheckedContinuation { continuation = $0 }
        }, presentError: { _ in XCTFail("Recognition should succeed") })
        board.setString("unchanged", forType: .string)
        let source = try image()
        let first = Task { await service.copyText(from: source) }
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        guard let pending = continuation else {
            first.cancel()
            XCTFail("OCR did not start")
            return
        }
        await service.copyText(from: source)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(board.string(forType: .string), "unchanged")
        pending.resume(returning: [OCRLine(text: "recognized", bounds: CGRect(x: 0, y: 0, width: 80, height: 10))])
        await first.value
        XCTAssertFalse(service.isRecognizing)
        XCTAssertEqual(board.string(forType: .string), "recognized")
    }
}
