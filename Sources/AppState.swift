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
    private let notificationAuthorization: NotificationAuthorization
    private let notificationDeniedDialog: @MainActor () -> Void
    private(set) var notificationAuthorizationTask: Task<Void, Never>?

    @Published var playSound: Bool {
        didSet {
            defaults.set(playSound, forKey: playSoundKey)
        }
    }

    @Published var showNotification: Bool {
        didSet {
            defaults.set(showNotification, forKey: showNotificationKey)
            if showNotification && !oldValue {
                authorizeNotifications()
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
        notificationAuthorization: NotificationAuthorization = .live,
        notificationDeniedDialog: @escaping @MainActor () -> Void = { PermissionDialogs.notificationsDenied() }
    ) {
        self.defaults = defaults
        self.notificationAuthorization = notificationAuthorization
        self.notificationDeniedDialog = notificationDeniedDialog
        defaults.register(defaults: [
            playSoundKey: true,
            showNotificationKey: false
        ])

        self.playSound = defaults.bool(forKey: playSoundKey)
        self.showNotification = defaults.bool(forKey: showNotificationKey)
        self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    private func authorizeNotifications() {
        guard notificationAuthorizationTask == nil else { return }
        notificationAuthorizationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.notificationAuthorizationTask = nil }
            guard self.showNotification else { return }
            let granted: Bool
            do {
                let status = await self.notificationAuthorization.status()
                guard self.showNotification else { return }
                switch status {
                case .notDetermined:
                    granted = try await self.notificationAuthorization.request()
                case .authorized, .provisional:
                    granted = true
                case .denied:
                    granted = false
                @unknown default:
                    granted = false
                }
            } catch {
                logger.error("Notification permission error: \(error.localizedDescription)")
                granted = false
            }
            // An in-flight request must not undo a later user decision to turn it off.
            guard self.showNotification, !granted else { return }
            self.showNotification = false
            self.notificationDeniedDialog()
        }
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
