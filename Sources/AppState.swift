import SwiftUI
import ServiceManagement
import os.log

private let logger = Logger(subsystem: "com.leon.snapboard", category: "AppState")

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    private let playSoundKey = "Snapboard_PlaySound"
    private let showNotificationKey = "Snapboard_ShowNotification"

    @Published var playSound: Bool {
        didSet {
            UserDefaults.standard.set(playSound, forKey: playSoundKey)
        }
    }

    @Published var showNotification: Bool {
        didSet {
            UserDefaults.standard.set(showNotification, forKey: showNotificationKey)
        }
    }

    @Published var launchAtLogin: Bool = false {
        didSet {
            updateLaunchAtLogin(launchAtLogin)
        }
    }

    private init() {
        UserDefaults.standard.register(defaults: [
            playSoundKey: true,
            showNotificationKey: false
        ])

        self.playSound = UserDefaults.standard.bool(forKey: playSoundKey)
        self.showNotification = UserDefaults.standard.bool(forKey: showNotificationKey)
        self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
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
