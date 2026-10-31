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
    private var hasRequestedScreenCapture = false
    private var isPresentingPermissionDialog = false
    private let preflightScreenCapture: () -> Bool
    private let requestScreenCapture: () -> Void
    private let presentScreenCapturePermission: () -> Bool
    private let openScreenCaptureSettings: (URL) -> Void
    private let runProcess: (Process) throws -> Void
    private let presentCaptureStartError: (Error) -> Void

    var hasActiveCapture: Bool { activeProcess != nil }

    init(
        preflightScreenCapture: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
        requestScreenCapture: @escaping () -> Void = { _ = CGRequestScreenCaptureAccess() },
        presentScreenCapturePermission: (() -> Bool)? = nil,
        openScreenCaptureSettings: ((URL) -> Void)? = nil,
        runProcess: @escaping (Process) throws -> Void = { try $0.run() },
        presentCaptureStartError: ((Error) -> Void)? = nil
    ) {
        self.preflightScreenCapture = preflightScreenCapture
        self.requestScreenCapture = requestScreenCapture
        self.presentScreenCapturePermission = presentScreenCapturePermission ?? Self.showScreenCapturePermission
        self.openScreenCaptureSettings = openScreenCaptureSettings ?? { _ = NSWorkspace.shared.open($0) }
        self.runProcess = runProcess
        self.presentCaptureStartError = presentCaptureStartError ?? Self.showCaptureStartError
    }

    // All entry points (shortcuts, menu, settings buttons) pass through this gate.
    private func canStartCapture() -> Bool {
        guard !isPresentingPermissionDialog else { return false }
        if let process = activeProcess, process.isRunning {
            logger.info("Capture process is already running.")
            return false
        }
        guard preflightScreenCapture() else {
            isPresentingPermissionDialog = true
            defer { isPresentingPermissionDialog = false }
            if presentScreenCapturePermission() {
                // Register Snapboard in the privacy list, at most once per app session.
                // Even if granted here, this attempt stops; the user retries after granting access.
                if !hasRequestedScreenCapture {
                    hasRequestedScreenCapture = true
                    requestScreenCapture()
                }
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    openScreenCaptureSettings(url)
                }
            }
            return false
        }
        return true
    }

    func captureDirect() {
        guard canStartCapture() else { return }

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
            try runProcess(process)
            self.activeProcess = process
        } catch {
            logger.error("Failed to run screencapture: \(error.localizedDescription)")
            presentCaptureStartError(error)
        }
    }

    func captureForEdit() {
        guard canStartCapture() else { return }

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
                    logger.info("Capture loaded into memory. Opening Editor...")
                    EditorWindowController.shared.show(image: image)
                } else {
                    try? FileManager.default.removeItem(at: tempFileURL)
                    logger.error("Failed to load captured image from memory.")
                }
            }
        }

        do {
            try runProcess(process)
            self.activeProcess = process
        } catch {
            logger.error("Failed to start screencapture for edit: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tempFileURL)
            presentCaptureStartError(error)
        }
    }

    private static func showScreenCapturePermission() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("capture.permission.title")
        alert.informativeText = L10n.tr("capture.permission.message")
        alert.addButton(withTitle: L10n.tr("capture.permission.openSettings"))
        alert.addButton(withTitle: L10n.tr("common.cancel"))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func showCaptureStartError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("capture.startError.title")
        alert.informativeText = L10n.format("capture.startError.message", error.localizedDescription)
        alert.addButton(withTitle: L10n.tr("common.ok"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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
