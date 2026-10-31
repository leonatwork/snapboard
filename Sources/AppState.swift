import SwiftUI
import ServiceManagement
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.leon.snapboard", category: "AppState")

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    private let playSoundKey = "Snapboard_PlaySound"
    private let showNotificationKey = "Snapboard_ShowNotification"
    private let defaults: UserDefaults
    private let authorizeNotifications: () async -> Bool
    private let presentNotificationDenied: () -> Void
    private(set) var isRequestingNotificationAuthorization = false

    @Published var playSound: Bool {
        didSet {
            defaults.set(playSound, forKey: playSoundKey)
        }
    }

    @Published var showNotification: Bool {
        didSet {
            defaults.set(showNotification, forKey: showNotificationKey)
            if showNotification && !oldValue {
                requestNotificationAuthorization()
            }
        }
    }

    @Published var launchAtLogin: Bool = false {
        didSet {
            updateLaunchAtLogin(launchAtLogin)
        }
    }

    init(
        defaults: UserDefaults = .standard,
        authorizeNotifications: (() async -> Bool)? = nil,
        presentNotificationDenied: (() -> Void)? = nil
    ) {
        self.defaults = defaults
        self.authorizeNotifications = authorizeNotifications ?? Self.notificationAuthorization
        self.presentNotificationDenied = presentNotificationDenied ?? Self.showNotificationDenied
        defaults.register(defaults: [
            playSoundKey: true,
            showNotificationKey: false
        ])

        self.playSound = defaults.bool(forKey: playSoundKey)
        self.showNotification = defaults.bool(forKey: showNotificationKey)
        self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    private func requestNotificationAuthorization() {
        // Rapid off/on toggles share the in-flight OS request.
        guard !isRequestingNotificationAuthorization else { return }
        isRequestingNotificationAuthorization = true
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let granted = await self.authorizeNotifications()
            self.isRequestingNotificationAuthorization = false
            guard self.showNotification, !granted else { return }
            self.showNotification = false
            self.presentNotificationDenied()
        }
    }

    private static func notificationAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert])
            } catch {
                logger.error("Notification permission error: \(error.localizedDescription)")
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private static func showNotificationDenied() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.tr("notification.permissionDenied.title")
        alert.informativeText = L10n.tr("notification.permissionDenied.message")
        alert.addButton(withTitle: L10n.tr("common.ok"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func checkLaunchAtLoginStatus() {
        self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                    logger.info("Successfully registered for launch at login")
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                    logger.info("Successfully unregistered launch at login")
                }
            }
        } catch {
            logger.error("Failed to change launch at login status: \(error.localizedDescription)")
        }
    }
}
