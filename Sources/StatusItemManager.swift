import AppKit
import SwiftUI

@MainActor
final class StatusItemManager: NSObject, NSMenuDelegate {
    static let shared = StatusItemManager()

    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    private override init() {
        super.init()
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }

        let icon = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Snapboard")
            ?? NSImage(systemSymbolName: "crop", accessibilityDescription: "Snapboard")
        icon?.isTemplate = true
        button.image = icon
        button.toolTip = L10n.tr("statusItem.tooltip")

        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // Action 1: Direct
        let directItem = NSMenuItem(
            title: L10n.tr("menu.captureDirect"),
            action: #selector(captureDirectAction),
            keyEquivalent: "1"
        )
        directItem.keyEquivalentModifierMask = [.command, .shift]
        directItem.target = self
        menu.addItem(directItem)

        // Action 2: Edit
        let editItem = NSMenuItem(
            title: L10n.tr("menu.captureEdit"),
            action: #selector(captureEditAction),
            keyEquivalent: "2"
        )
        editItem.keyEquivalentModifierMask = [.command, .shift]
        editItem.target = self
        menu.addItem(editItem)

        let textItem = NSMenuItem(title: L10n.tr("menu.captureText"),
                                  action: #selector(captureTextAction), keyEquivalent: "6")
        textItem.keyEquivalentModifierMask = [.command, .shift]
        textItem.target = self
        menu.addItem(textItem)

        menu.addItem(NSMenuItem.separator())

        // Toggles
        let soundItem = NSMenuItem(
            title: L10n.tr("menu.playSound"),
            action: #selector(toggleSoundAction),
            keyEquivalent: ""
        )
        soundItem.target = self
        soundItem.state = AppState.shared.playSound ? .on : .off
        menu.addItem(soundItem)

        let autostartItem = NSMenuItem(
            title: L10n.tr("menu.launchAtLogin"),
            action: #selector(toggleAutostartAction),
            keyEquivalent: ""
        )
        autostartItem.target = self
        autostartItem.state = AppState.shared.launchAtLogin ? .on : .off
        menu.addItem(autostartItem)

        menu.addItem(NSMenuItem.separator())

        // Settings & About
        let settingsItem = NSMenuItem(
            title: L10n.tr("menu.settings"),
            action: #selector(openSettingsAction),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(
            title: L10n.tr("menu.about"),
            action: #selector(openAboutAction),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        // More apps from the same package
        let moreAppsItem = NSMenuItem(title: L10n.tr("menu.moreApps"), action: nil, keyEquivalent: "")
        moreAppsItem.submenu = makeMoreAppsMenu()
        menu.addItem(moreAppsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: L10n.tr("menu.quit"),
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    // MARK: - More apps

    /// Other tools of the package "I love macOS, but I miss some Windows features".
    private static let otherApps: [(titleKey: String, url: String)] = [
        ("menu.moreApps.tappi", "https://github.com/leonatwork/Tappi"),
        ("menu.moreApps.klemmi", "https://github.com/leonatwork/Klemmi"),
        ("menu.moreApps.snapline", "https://github.com/leonatwork/snapline")
    ]

    private static let packageURL =
        "https://github.com/search?q=topic%3Ai-love-macos-but-i-miss-windows-features+user%3Aleonatwork&type=repositories"

    private func makeMoreAppsMenu() -> NSMenu {
        let submenu = NSMenu()
        for app in Self.otherApps {
            submenu.addItem(makeLinkItem(title: L10n.tr(app.titleKey), url: app.url))
        }
        submenu.addItem(NSMenuItem.separator())
        submenu.addItem(makeLinkItem(title: L10n.tr("menu.moreApps.package"), url: Self.packageURL))
        return submenu
    }

    private func makeLinkItem(title: String, url: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(openLinkAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = URL(string: url)
        return item
    }

    @objc private func openLinkAction(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - NSMenuDelegate
    func menuWillOpen(_ menu: NSMenu) {
        AppState.shared.checkLaunchAtLoginStatus()
        rebuildMenu()
    }

    // MARK: - Actions
    @objc private func captureDirectAction() {
        CaptureService.shared.captureDirect()
    }

    @objc private func captureEditAction() {
        CaptureService.shared.captureForEdit()
    }

    @objc private func captureTextAction() {
        CaptureService.shared.captureForText()
    }

    @objc private func toggleSoundAction() {
        AppState.shared.playSound.toggle()
        rebuildMenu()
    }

    @objc private func toggleAutostartAction() {
        AppState.shared.launchAtLogin.toggle()
        rebuildMenu()
    }

    @objc func openSettingsAction() {
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = L10n.tr("settings.windowTitle")
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false

        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openAboutAction() {
        let alert = NSAlert()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        alert.messageText = "Snapboard v\(version)"
        alert.informativeText = L10n.tr("about.message")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.tr("common.ok"))
        alert.runModal()
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }
}
