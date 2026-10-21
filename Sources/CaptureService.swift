import AppKit
import CoreGraphics
import Foundation
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.leon.snapboard", category: "CaptureService")

@MainActor
final class CaptureService {
    static let shared = CaptureService()

    private var activeProcess: Process?
    private var didRequestAccess = false
    private let preflight: () -> Bool
    private let requestAccess: () -> Void
    private let showPermissionDialog: @MainActor () -> Bool
    private let openURL: @MainActor (URL) -> Void
    private let showCaptureError: @MainActor (String) -> Void
    private let runProcess: (Process) throws -> Void

    init(
        preflight: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
        requestAccess: @escaping () -> Void = { _ = CGRequestScreenCaptureAccess() },
        showPermissionDialog: @escaping @MainActor () -> Bool = { PermissionDialogs.screenCapture() },
        openURL: @escaping @MainActor (URL) -> Void = { _ = NSWorkspace.shared.open($0) },
        showCaptureError: @escaping @MainActor (String) -> Void = { PermissionDialogs.captureError($0) },
        runProcess: @escaping (Process) throws -> Void = { try $0.run() }
    ) {
        self.preflight = preflight
        self.requestAccess = requestAccess
        self.showPermissionDialog = showPermissionDialog
        self.openURL = openURL
        self.showCaptureError = showCaptureError
        self.runProcess = runProcess
    }

    private func ensureScreenCaptureAccess() -> Bool {
        guard !preflight() else { return true }
        if !didRequestAccess {
            didRequestAccess = true
            requestAccess()
        }
        if showPermissionDialog(), let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            openURL(url)
        }
        // Never start the pending capture, even if the system prompt granted access.
        return false
    }

    func captureDirect() {
        if let process = activeProcess, process.isRunning {
            logger.info("Capture process is already running.")
            return
        }

        guard ensureScreenCaptureAccess() else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-c"]

        let initialChangeCount = NSPasteboard.general.changeCount

        process.terminationHandler = { [weak self] proc in
            Task { @MainActor [weak self] in
                self?.activeProcess = nil
                self?.finishDirectCapture(status: proc.terminationStatus,
                    clipboardChanged: NSPasteboard.general.changeCount != initialChangeCount)
            }
        }

        do {
            try runProcess(process)
            self.activeProcess = process
        } catch {
            logger.error("Failed to run screencapture: \(error.localizedDescription)")
            showCaptureError(error.localizedDescription)
        }
    }

    func captureForEdit() {
        if let process = activeProcess, process.isRunning {
            logger.info("Capture process is already running.")
            return
        }

        guard ensureScreenCaptureAccess() else { return }

        let tempFileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("snapboard_capture_\(UUID().uuidString).png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i: interactive selection
        // Write to temp file path, which we immediately read into memory and delete
        process.arguments = ["-i", tempFileURL.path]

        process.terminationHandler = { [weak self] proc in
            Task { @MainActor [weak self] in
                self?.activeProcess = nil

                self?.finishEditorCapture(status: proc.terminationStatus, tempFileURL: tempFileURL)
            }
        }

        do {
            try runProcess(process)
            self.activeProcess = process
        } catch {
            logger.error("Failed to start screencapture for edit: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tempFileURL)
            showCaptureError(error.localizedDescription)
        }
    }

    func finishDirectCapture(status: Int32, clipboardChanged: Bool) {
        // Esc can return a nonzero status or leave the clipboard unchanged.
        guard status == 0, clipboardChanged else { return }
        logger.info("Direct capture successful.")
        handleCaptureSuccess()
    }

    func finishEditorCapture(status: Int32, tempFileURL: URL) {
        defer { try? FileManager.default.removeItem(at: tempFileURL) }
        guard status == 0, FileManager.default.fileExists(atPath: tempFileURL.path) else {
            logger.info("Capture cancelled or aborted.")
            return
        }
        if let imageData = try? Data(contentsOf: tempFileURL),
           let image = NSImage(data: imageData) {
            // Remove before opening the editor, which may run a nested event loop.
            try? FileManager.default.removeItem(at: tempFileURL)
            logger.info("Capture loaded into memory. Opening Editor...")
            EditorWindowController.shared.show(image: image)
        } else {
            logger.error("Failed to load captured image from memory.")
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
