import AppKit
import Foundation
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.leon.screenie", category: "CaptureService")

@MainActor
final class CaptureService {
    static let shared = CaptureService()

    private var activeProcess: Process?

    private init() {}

    func captureDirect() {
        if let process = activeProcess, process.isRunning {
            logger.info("Capture process is already active.")
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
                    logger.info("Screenshot copied directly to clipboard.")
                    self?.handleCaptureSuccess()
                }
            }
        }

        do {
            try process.run()
            self.activeProcess = process
        } catch {
            logger.error("Failed to start screencapture: \(error.localizedDescription)")
        }
    }

    func captureForEdit() {
        if let process = activeProcess, process.isRunning {
            logger.info("Capture process is already active.")
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
                    logger.info("Screenshot captured, opening in Editor...")
                    self?.openInEditor()
                }
            }
        }

        do {
            try process.run()
            self.activeProcess = process
        } catch {
            logger.error("Failed to start screencapture: \(error.localizedDescription)")
        }
    }

    private func openInEditor() {
        guard let images = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
              let image = images.first else {
            logger.error("No image found on clipboard to edit.")
            return
        }

        EditorWindowController.shared.show(image: image)
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
        content.title = "Screenie"
        content.body = "Screenshot in die Zwischenablage kopiert."
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
