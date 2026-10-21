import AppKit

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

    static func captureError(_ detail: String) {
        showNotice(title: L10n.tr("capture.error.title"),
                   message: L10n.format("capture.error.message", detail))
    }

    static func notificationDenied() {
        showNotice(title: L10n.tr("permission.notification.title"),
                   message: L10n.tr("permission.notification.message"))
    }

    private static func showNotice(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L10n.tr("common.ok"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
