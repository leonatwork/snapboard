import AppKit
import Foundation
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.leon.snapboard", category: "CaptureService")

@MainActor
final class CaptureService {
    static let shared = CaptureService()

    private var activeProcess: Process?
    private var isRecognizingText = false

    private init() {}

    func captureDirect() {
        guard !isRecognizingText else { return }
        if let process = activeProcess, process.isRunning {
            logger.info("Capture process is already running.")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-c"]

        let initialChangeCount = NSPasteboard.general.changeCount

        process.terminationHandler = { [weak self] proc in
            Task { @MainActor [weak self] in
                self?.activeProcess = nil
                let newChangeCount = NSPasteboard.general.changeCount

                if proc.terminationStatus == 0 && newChangeCount != initialChangeCount {
                    logger.info("Direct capture successful.")
                    self?.handleCaptureSuccess()
                }
            }
        }

        do {
            try process.run()
            self.activeProcess = process
        } catch {
            logger.error("Failed to run screencapture: \(error.localizedDescription)")
        }
    }

    func captureForEdit() {
        captureImage { EditorWindowController.shared.show(image: $0) }
    }

    func captureForText() {
        captureImage { image in
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                OCRService.showNotice(L10n.tr("ocr.failed"))
                return
            }
            self.isRecognizingText = true
            Task {
                defer { self.isRecognizingText = false }
                await OCRService.shared.copyText(from: cgImage)
            }
        }
    }

    private func captureImage(onCapture: @escaping @MainActor (NSImage) -> Void) {
        guard !isRecognizingText else { return }
        if let process = activeProcess, process.isRunning {
            logger.info("Capture process is already running.")
            return
        }

        let tempFileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("snapboard_capture_\(UUID().uuidString).png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i: interactive selection
        // Write to temp file path, which we immediately read into memory and delete
        process.arguments = ["-i", tempFileURL.path]

        process.terminationHandler = { [weak self] proc in
            Task { @MainActor [weak self] in
                self?.activeProcess = nil

                guard proc.terminationStatus == 0, FileManager.default.fileExists(atPath: tempFileURL.path) else {
                    try? FileManager.default.removeItem(at: tempFileURL)
                    logger.info("Capture cancelled or aborted.")
                    return
                }

                // Load image into RAM
                if let imageData = try? Data(contentsOf: tempFileURL),
                   let image = NSImage(data: imageData) {
                    // Clean up temp file immediately (0 files on disk)
                    try? FileManager.default.removeItem(at: tempFileURL)
                    logger.info("Capture loaded into memory.")
                    onCapture(image)
                } else {
                    try? FileManager.default.removeItem(at: tempFileURL)
                    logger.error("Failed to load captured image from memory.")
                }
            }
        }

        do {
            try process.run()
            self.activeProcess = process
        } catch {
            logger.error("Failed to start screencapture for edit: \(error.localizedDescription)")
        }
    }

    private func handleCaptureSuccess() {
        if AppState.shared.playSound {
            if let sound = NSSound(named: "Tink") ?? NSSound(named: "Hero") {
                sound.play()
            } else {
                NSSound.beep()
            }
        }

        if AppState.shared.showNotification {
            sendNotification()
        }
    }

    private func sendNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Snapboard"
        content.body = L10n.tr("notification.copied")
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                logger.error("Failed to post notification: \(error.localizedDescription)")
            }
        }
    }
}
