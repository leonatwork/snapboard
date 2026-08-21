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

        let icon = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Screenie")
            ?? NSImage(systemSymbolName: "crop", accessibilityDescription: "Screenie")
        icon?.isTemplate = true
        button.image = icon
        button.toolTip = "Screenie: ⌘⇧1 (Kopieren) / ⌘⇧2 (Bearbeiten)"

        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // Action 1: Direct Capture
        let directItem = NSMenuItem(
            title: "Bereich aufnehmen (Direkt)",
            action: #selector(captureDirectAction),
            keyEquivalent: "1"
        )
        directItem.keyEquivalentModifierMask = [.command, .shift]
        directItem.target = self
        menu.addItem(directItem)

        // Action 2: Capture & Edit
        let editItem = NSMenuItem(
            title: "Bereich aufnehmen & bearbeiten",
            action: #selector(captureEditAction),
            keyEquivalent: "2"
        )
        editItem.keyEquivalentModifierMask = [.command, .shift]
        editItem.target = self
        menu.addItem(editItem)

        menu.addItem(NSMenuItem.separator())

        // Quick Toggles
        let soundItem = NSMenuItem(
            title: "Ton bei Aufnahme",
            action: #selector(toggleSoundAction),
            keyEquivalent: ""
        )
        soundItem.target = self
        soundItem.state = AppState.shared.playSound ? .on : .off
        menu.addItem(soundItem)

        let autostartItem = NSMenuItem(
            title: "Beim Anmelden starten",
            action: #selector(toggleAutostartAction),
            keyEquivalent: ""
        )
        autostartItem.target = self
        autostartItem.state = AppState.shared.launchAtLogin ? .on : .off
        menu.addItem(autostartItem)

        menu.addItem(NSMenuItem.separator())

        // Settings & About
        let settingsItem = NSMenuItem(
            title: "Einstellungen...",
            action: #selector(openSettingsAction),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(
            title: "Über Screenie",
            action: #selector(openAboutAction),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Screenie beenden",
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
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
        window.title = "Screenie Einstellungen"
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false

        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openAboutAction() {
        let alert = NSAlert()
        alert.messageText = "Screenie v1.1"
        alert.informativeText = "Die ultimative Greenshot-Alternative für macOS.\n\n• ⌘⇧1: Bereich markieren → Direkt in Zwischenablage (0 Klicks)\n• ⌘⇧2: Bereich markieren → Im Editor öffnen (Einkreisen, Pfeile, Text, Blur)\n\nKeine Dateien auf der Festplatte."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }
}
