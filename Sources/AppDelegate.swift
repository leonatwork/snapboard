import AppKit
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.leon.snapboard", category: "AppDelegate")

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Snapboard application started")

        // Accessory policy (menu bar only)
        NSApp.setActivationPolicy(.accessory)

        // Setup status item
        StatusItemManager.shared.setupStatusItem()

        // Setup HotKey trigger handlers
        HotKeyManager.shared.onTriggerDirect = {
            CaptureService.shared.captureDirect()
        }

        HotKeyManager.shared.onTriggerEdit = {
            CaptureService.shared.captureForEdit()
        }

        HotKeyManager.shared.onTriggerText = {
            CaptureService.shared.captureForText()
        }

        // Register global shortcuts
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
