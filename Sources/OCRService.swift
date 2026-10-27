import AppKit
import Vision

@MainActor
final class OCRService {
    static let shared = OCRService()

    private let recognize: (CGImage) async throws -> [OCRTextLine]
    private let presentNotice: (String) -> Void

    init(recognize: ((CGImage) async throws -> [OCRTextLine])? = nil,
         presentNotice: ((String) -> Void)? = nil) {
        self.recognize = recognize ?? Self.recognizeLocally
        self.presentNotice = presentNotice ?? Self.showNotice
    }

    @discardableResult
    func copyText(from image: CGImage, excluding redactions: [CGRect] = [],
                  pasteboard: NSPasteboard = .general) async -> Bool {
        do {
            let lines = try await recognize(image)
            let text = OCRTextLayout.plainText(lines, excluding: redactions)
            guard !text.isEmpty else {
                presentNotice(L10n.tr("ocr.noText"))
                return false
            }
            // Do not touch the clipboard before recognition succeeds with nonempty text.
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            pasteboard.clearContents()
            guard pasteboard.writeObjects([item]) else {
                presentNotice(L10n.tr("ocr.clipboardFailed"))
                return false
            }
            return true
        } catch {
            presentNotice(L10n.tr("ocr.failed"))
            return false
        }
    }

    nonisolated private static func recognizeLocally(_ image: CGImage) async throws -> [OCRTextLine] {
        try await Task.detached(priority: .userInitiated) { () throws -> [OCRTextLine] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.automaticallyDetectsLanguage = true
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            return (request.results ?? []).compactMap { observation in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                let box = observation.boundingBox
                // Vision uses bottom-left coordinates; the pure layout uses top-left.
                return OCRTextLine(text: text, bounds: CGRect(
                    x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height))
            }
        }.value
    }

    static func showNotice(_ message: String) {
        let alert = NSAlert()
        alert.messageText = L10n.tr("ocr.title")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.tr("common.ok"))
        alert.runModal()
    }
}
