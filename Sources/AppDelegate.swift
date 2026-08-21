import AppKit
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.leon.screenie", category: "AppDelegate")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Screenie application started")

        // Ensure the app runs as an accessory (Status Bar item only, no Dock icon)
        NSApp.setActivationPolicy(.accessory)

        // Setup status item in Menu Bar
        StatusItemManager.shared.setupStatusItem()

        // Setup HotKey trigger handlers
        HotKeyManager.shared.onTriggerDirect = {
            CaptureService.shared.captureDirect()
        }

        HotKeyManager.shared.onTriggerEdit = {
            CaptureService.shared.captureForEdit()
        }

        // Register global shortcuts (⌘⇧1 and ⌘⇧2)
        HotKeyManager.shared.registerHotKeys()

        // Request notification authorization
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                logger.error("Notification permission error: \(error.localizedDescription)")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregisterHotKeys()
    }
}
