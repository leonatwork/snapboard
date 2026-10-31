import AppKit
import Vision

enum OCRFailure: LocalizedError {
    case noText, recognitionFailed, clipboardFailed

    var errorDescription: String? {
        switch self {
        case .noText: return L10n.tr("ocr.noText")
        case .recognitionFailed: return L10n.tr("ocr.failed")
        case .clipboardFailed: return L10n.tr("ocr.clipboardFailed")
        }
    }
}

@MainActor
final class OCRService {
    static let shared = OCRService()
    private(set) var isRecognizing = false
    private let pasteboard: NSPasteboard
    private let recognize: (CGImage) async throws -> [OCRLine]
    private let presentError: (Error) -> Void

    init(pasteboard: NSPasteboard = .general,
         recognize: ((CGImage) async throws -> [OCRLine])? = nil,
         presentError: ((Error) -> Void)? = nil) {
        self.pasteboard = pasteboard
        self.recognize = recognize ?? Self.recognizeLocally
        self.presentError = presentError ?? Self.showError
    }

    func copyText(from image: NSImage, excluding redactions: [CGRect] = []) async {
        guard !isRecognizing else { return }
        isRecognizing = true
        defer { isRecognizing = false }
        do {
            guard let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw OCRFailure.recognitionFailed
            }
            let lines = try await recognize(pixels)
            let text = OCRTextProcessing.text(from: lines, excluding: redactions)
            guard !text.isEmpty else { throw OCRFailure.noText }
            let item = NSPasteboardItem()
            guard item.setString(text, forType: .string) else { throw OCRFailure.clipboardFailed }
            // Do not touch the clipboard until recognition has succeeded with text.
            pasteboard.clearContents()
            guard pasteboard.writeObjects([item]) else { throw OCRFailure.clipboardFailed }
            if AppState.shared.playSound { NSSound(named: "Tink")?.play() }
        } catch {
            // Do not include recognized text or screenshots in logs/error details.
            presentError((error as? OCRFailure) ?? OCRFailure.recognitionFailed)
        }
    }

    private nonisolated static func recognizeLocally(_ image: CGImage) async throws -> [OCRLine] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.automaticallyDetectsLanguage = true
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            return (request.results ?? []).compactMap { observation in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                let box = observation.boundingBox
                // Vision uses a normalized bottom-left origin. Convert once here.
                return OCRLine(text: text, bounds: CGRect(
                    x: box.minX * CGFloat(image.width),
                    y: (1 - box.maxY) * CGFloat(image.height),
                    width: box.width * CGFloat(image.width), height: box.height * CGFloat(image.height)))
            }
        }.value
    }

    private static func showError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.tr("ocr.title")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: L10n.tr("common.ok"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
