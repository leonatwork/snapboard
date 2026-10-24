import AppKit
import UserNotifications

// Replaceable API boundary: tests never ask for real TCC or notification permissions.
struct NotificationAuthorization {
    var status: () async -> UNAuthorizationStatus
    var request: () async throws -> Bool

    static let live = NotificationAuthorization(
        status: { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus },
        request: { try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    )
}

@MainActor
enum PermissionDialogs {
    static func screenCapture() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("permission.screenCapture.title")
        alert.informativeText = L10n.tr("permission.screenCapture.message")
        alert.addButton(withTitle: L10n.tr("permission.openSettings"))
        alert.addButton(withTitle: L10n.tr("common.cancel"))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func captureLaunchFailed() {
        show(title: L10n.tr("capture.launchFailed.title"), message: L10n.tr("capture.launchFailed.message"))
    }

    static func notificationsDenied() {
        show(title: L10n.tr("permission.notifications.title"), message: L10n.tr("permission.notifications.message"))
    }

    private static func show(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L10n.tr("common.ok"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
