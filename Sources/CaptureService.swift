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

    func captureArea() {
        // If a capture process is already running, bring it to front or ignore
        if let process = activeProcess, process.isRunning {
            logger.info("Screenshot process is already active.")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i: interactive (selection rectangle)
        // -c: copy to clipboard directly (no file saved to disk)
        process.arguments = ["-i", "-c"]

        let initialChangeCount = NSPasteboard.general.changeCount

        process.terminationHandler = { [weak self] proc in
            Task { @MainActor [weak self] in
                self?.activeProcess = nil
                let newChangeCount = NSPasteboard.general.changeCount

                // Check if screenshot was actually copied (proc.terminationStatus == 0 and clipboard changed)
                if proc.terminationStatus == 0 && newChangeCount != initialChangeCount {
                    logger.info("Screenshot copied to clipboard successfully.")
                    self?.handleCaptureSuccess()
                } else {
                    logger.info("Screenshot cancelled or no image copied.")
                }
            }
        }

        do {
            try process.run()
            self.activeProcess = process
        } catch {
            logger.error("Failed to start screencapture process: \(error.localizedDescription)")
        }
    }

    private func handleCaptureSuccess() {
        if AppState.shared.playSound {
            // Play camera shutter sound or default system sound
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
