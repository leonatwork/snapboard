import SwiftUI
import ServiceManagement
import os.log

private let logger = Logger(subsystem: "com.leon.snapboard", category: "AppState")

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    private let playSoundKey = "Snapboard_PlaySound"
    private let showNotificationKey = "Snapboard_ShowNotification"
    private let defaults: UserDefaults
    private let notificationAuthorization: NotificationAuthorizationProviding
    private let showNotificationDenied: @MainActor () -> Void
    private(set) var notificationAuthorizationTask: Task<Void, Never>?
    private var notificationChangeID = 0

    @Published var playSound: Bool {
        didSet {
            defaults.set(playSound, forKey: playSoundKey)
        }
    }

    @Published var showNotification: Bool {
        didSet {
            defaults.set(showNotification, forKey: showNotificationKey)
            guard showNotification != oldValue else { return }
            notificationChangeID += 1
            if showNotification {
                authorizeNotifications(changeID: notificationChangeID)
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
        notificationAuthorization: NotificationAuthorizationProviding? = nil,
        showNotificationDenied: @escaping @MainActor () -> Void = { PermissionDialogs.notificationDenied() }
    ) {
        self.defaults = defaults
        self.notificationAuthorization = notificationAuthorization ?? SystemNotificationAuthorization()
        self.showNotificationDenied = showNotificationDenied
        defaults.register(defaults: [
            playSoundKey: true,
            showNotificationKey: false
        ])

        self.playSound = defaults.bool(forKey: playSoundKey)
        self.showNotification = defaults.bool(forKey: showNotificationKey)
        self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    private func authorizeNotifications(changeID: Int) {
        // Serialize rapid off/on changes so only one system request can be in flight.
        let previousTask = notificationAuthorizationTask
        notificationAuthorizationTask = Task { [weak self] in
            await previousTask?.value
            guard let self, self.showNotification,
                  self.notificationChangeID == changeID else { return }
            let status = await self.notificationAuthorization.authorizationStatus()
            guard self.showNotification, self.notificationChangeID == changeID else { return }
            let granted: Bool
            switch status {
            case .authorized, .provisional:
                granted = true
            case .notDetermined:
                do {
                    granted = try await self.notificationAuthorization.requestAuthorization()
                } catch {
                    logger.error("Notification permission error: \(error.localizedDescription)")
                    granted = false
                }
            default:
                granted = false
            }
            guard self.showNotification, self.notificationChangeID == changeID else { return }
            if !granted {
                self.showNotification = false
                self.showNotificationDenied()
            }
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
