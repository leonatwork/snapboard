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

        // Configure Menu Bar Icon
        let icon = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Screenie")
            ?? NSImage(systemSymbolName: "crop", accessibilityDescription: "Screenie")
        icon?.isTemplate = true
        button.image = icon
        button.toolTip = "Screenie: Bereich aufnehmen mit ⌘⇧1"

        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // Primary Action
        let captureItem = NSMenuItem(
            title: "Bereich aufnehmen",
            action: #selector(captureAreaAction),
            keyEquivalent: "1"
        )
        captureItem.keyEquivalentModifierMask = [.command, .shift]
        captureItem.target = self
        menu.addItem(captureItem)

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

        // Settings
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
    @objc private func captureAreaAction() {
        CaptureService.shared.captureArea()
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
        alert.messageText = "Screenie v1.0"
        alert.informativeText = "Die minimalistische Greenshot-Alternative für macOS.\n\nDrücke ⌘⇧1, markiere den gewünschten Bereich und füge ihn direkt aus der Zwischenablage ein – ohne unnötige Dateien auf der Festplatte."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }
}
