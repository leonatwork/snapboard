import AppKit
import XCTest
@testable import Snapboard

@MainActor
final class OCRTests: XCTestCase {
    private func line(_ text: String, _ x: CGFloat, _ y: CGFloat) -> OCRTextLine {
        OCRTextLine(text: text, bounds: CGRect(x: x, y: y, width: 0.2, height: 0.1))
    }

    func testReadingOrderGroupsAlignedFragmentsAndPreservesNewlines() async {
        let lines = [line("last", 0, 0.7), line("right", 0.4, 0.12),
                     line("left", 0, 0.1), line("middle", 0, 0.4), line("  ", 0, 0)]
        XCTAssertEqual(OCRTextLayout.plainText(lines), "left right\nmiddle\nlast")
        XCTAssertEqual(OCRTextLayout.plainText(lines.reversed()), "left right\nmiddle\nlast")
        XCTAssertEqual(OCRTextLayout.plainText([]), "")
    }

    func testRedactedLinesAreExcludedEvenIfEngineStillRecognizesThem() async {
        XCTAssertEqual(OCRTextLayout.plainText([line("secret", 0, 0.1), line("visible", 0, 0.4)],
            excluding: [CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.1)]), "visible")
    }

    func testEmptyAndFailedOCRPreserveClipboardAndShowNotice() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let image = try makeImage()
        for fails in [false, true] {
            pasteboard.clearContents()
            pasteboard.setString("existing", forType: .string)
            let count = pasteboard.changeCount
            var notices: [String] = []
            let service = OCRService(recognize: { _ in
                if fails { throw NSError(domain: "OCRTests", code: 1) }
                return []
            }, presentNotice: { notices.append($0) })
            let copied = await service.copyText(from: image, pasteboard: pasteboard)
            XCTAssertFalse(copied)
            XCTAssertEqual(pasteboard.changeCount, count)
            XCTAssertEqual(pasteboard.string(forType: .string), "existing")
            XCTAssertEqual(notices.count, 1)
        }
    }

    func testEditorPreventsDuplicateRecognitionUntilPendingRequestFinishes() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        var pending: CheckedContinuation<[OCRTextLine], Error>?
        var requests = 0
        let started = expectation(description: "OCR started")
        let service = OCRService(recognize: { _ in
            requests += 1
            return try await withCheckedThrowingContinuation {
                pending = $0
                started.fulfill()
            }
        }, presentNotice: { _ in XCTFail("No notice expected") })
        let model = EditorViewModel(image: NSImage(cgImage: try makeImage(), size: NSSize(width: 320, height: 180)),
                                    pasteboard: pasteboard, ocrService: service)
        let firstCopy = Task { await model.copyText() }
        await fulfillment(of: [started], timeout: 5)
        guard let pending else {
            firstCopy.cancel()
            XCTFail("OCR did not start")
            return
        }
        XCTAssertTrue(model.isRecognizingText)
        await model.copyText()
        XCTAssertEqual(requests, 1)
        pending.resume(returning: [line("recognized", 0, 0)])
        await firstCopy.value
        XCTAssertFalse(model.isRecognizingText)
        XCTAssertEqual(pasteboard.string(forType: .string), "recognized")
    }

    func testEditorRenderFailureDoesNotStartOCRAndPreservesClipboard() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("existing", forType: .string)
        let count = pasteboard.changeCount
        var errors: [Error] = []
        let service = OCRService(recognize: { _ in XCTFail("Must not recognize an invalid image"); return [] },
                                 presentNotice: { _ in XCTFail("Render error uses existing export notice") })
        let model = EditorViewModel(image: NSImage(size: .zero), pasteboard: pasteboard,
                                    presentExportError: { errors.append($0) }, ocrService: service)
        await model.copyText()
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(pasteboard.changeCount, count)
        XCTAssertEqual(pasteboard.string(forType: .string), "existing")
        XCTAssertFalse(model.isRecognizingText)
    }

    func testEditorOCRReceivesRenderedPixelsAndCopiesOnlyPlainTextWithoutClosing() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setData(Data([1]), forType: .png)
        var received: CGImage?
        var notices: [String] = []
        let service = OCRService(recognize: { image in
            received = image
            return [self.line("annotation", 0, 0.4), self.line("secret", 0, 0.1)]
        }, presentNotice: { notices.append($0) })
        let image = try makeImage()
        let model = EditorViewModel(image: NSImage(cgImage: image, size: NSSize(width: 160, height: 90)),
                                    pasteboard: pasteboard, ocrService: service)
        model.annotations = [AnnotationItem(tool: .rectangle,
            startPoint: CGPoint(x: 0.2, y: 0.2), endPoint: CGPoint(x: 0.8, y: 0.8),
            color: .red, lineWidth: 4), AnnotationItem(tool: .blur,
            startPoint: CGPoint(x: 0, y: 0.1), endPoint: CGPoint(x: 0.2, y: 0.2),
            color: .red, lineWidth: 4)]
        var closed = false
        model.onClose = { closed = true }
        await model.copyText()
        let rendered = try XCTUnwrap(received)
        XCTAssertEqual(rendered.width, 320)
        XCTAssertEqual(rendered.height, 180)
        XCTAssertNotEqual(rendered.dataProvider?.data as Data?, image.dataProvider?.data as Data?)
        XCTAssertEqual(pasteboard.string(forType: .string), "annotation")
        XCTAssertTrue(try XCTUnwrap(pasteboard.types).contains(.string))
        XCTAssertNil(pasteboard.data(forType: .png))
        XCTAssertNil(pasteboard.data(forType: .tiff))
        XCTAssertTrue(notices.isEmpty)
        XCTAssertFalse(closed)
        XCTAssertFalse(model.isRecognizingText)
    }

    private func makeImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 320, height: 180,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
        return try XCTUnwrap(context.makeImage())
    }
}
