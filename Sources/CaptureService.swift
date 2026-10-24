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
    private let preflight: () -> Bool
    private let requestAccess: () -> Void
    private let permissionDialog: @MainActor () -> Bool
    private let openSettings: @MainActor (URL) -> Void
    private let startProcess: (Process) throws -> Void
    private let launchErrorDialog: @MainActor () -> Void
    private var didRequestAccess = false
    private var isShowingPermissionDialog = false

    init(
        preflight: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
        requestAccess: @escaping () -> Void = { _ = CGRequestScreenCaptureAccess() },
        permissionDialog: @escaping @MainActor () -> Bool = { PermissionDialogs.screenCapture() },
        openSettings: @escaping @MainActor (URL) -> Void = { _ = NSWorkspace.shared.open($0) },
        startProcess: @escaping (Process) throws -> Void = { try $0.run() },
        launchErrorDialog: @escaping @MainActor () -> Void = { PermissionDialogs.captureLaunchFailed() }
    ) {
        self.preflight = preflight
        self.requestAccess = requestAccess
        self.permissionDialog = permissionDialog
        self.openSettings = openSettings
        self.startProcess = startProcess
        self.launchErrorDialog = launchErrorDialog
    }

    private func canCapture() -> Bool {
        // runModal runs a nested event loop: ignore further capture shortcuts meanwhile.
        guard !isShowingPermissionDialog else { return false }
        guard preflight() else {
            isShowingPermissionDialog = true
            defer { isShowingPermissionDialog = false }
            if permissionDialog() {
                // Register the app in TCC at most once per app session, on user action.
                if !didRequestAccess {
                    didRequestAccess = true
                    requestAccess()
                }
                openSettings(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }
            // Never resume this attempt, even if the system request grants access.
            return false
        }
        return true
    }

    func captureDirect() {
        if let process = activeProcess, process.isRunning {
            logger.info("Capture process is already running.")
            return
        }

        guard canCapture() else { return }

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
            try startProcess(process)
            self.activeProcess = process
        } catch {
            logger.error("Failed to run screencapture: \(error.localizedDescription)")
            launchErrorDialog()
        }
    }

    func captureForEdit() {
        if let process = activeProcess, process.isRunning {
            logger.info("Capture process is already running.")
            return
        }

        guard canCapture() else { return }

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
            try startProcess(process)
            self.activeProcess = process
        } catch {
            logger.error("Failed to start screencapture for edit: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tempFileURL)
            launchErrorDialog()
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
