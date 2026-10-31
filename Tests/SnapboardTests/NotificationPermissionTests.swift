import XCTest
@testable import Snapboard

@MainActor
final class NotificationPermissionTests: XCTestCase {
    private func isolatedDefaults() -> UserDefaults {
        // An ephemeral suite keeps tests away from an installed app's preferences.
        UserDefaults(suiteName: "SnapboardTests.\(UUID().uuidString)")!
    }

    func testFreshStartDoesNotRequestNotifications() async {
        var requests = 0
        let state = AppState(
            defaults: isolatedDefaults(),
            authorizeNotifications: { requests += 1; return true },
            presentNotificationDenied: { XCTFail("No denial at startup") }
        )

        await Task.yield()

        XCTAssertFalse(state.showNotification)
        XCTAssertEqual(requests, 0)
    }

    func testPersistedEnabledSettingDoesNotRequestAtStartup() async {
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: "Snapboard_ShowNotification")
        var requests = 0
        let state = AppState(
            defaults: defaults, authorizeNotifications: { requests += 1; return true },
            presentNotificationDenied: { XCTFail("No denial at startup") }
        )

        await Task.yield()

        XCTAssertTrue(state.showNotification)
        XCTAssertEqual(requests, 0)
        defaults.removeObject(forKey: "Snapboard_ShowNotification")
    }

    func testEnablingRequestsPermissionAndPersistsGrantedSetting() async {
        let defaults = isolatedDefaults()
        var requests = 0
        let finished = expectation(description: "Authorization completed")
        let state = AppState(
            defaults: defaults,
            authorizeNotifications: {
                requests += 1
                finished.fulfill()
                return true
            },
            presentNotificationDenied: { XCTFail("Permission granted") }
        )

        state.showNotification = true
        state.showNotification = true
        await fulfillment(of: [finished], timeout: 2)

        XCTAssertEqual(requests, 1)
        XCTAssertTrue(state.showNotification)
        XCTAssertTrue(defaults.bool(forKey: "Snapboard_ShowNotification"))
        state.showNotification = false
        defaults.removeObject(forKey: "Snapboard_ShowNotification")
    }

    func testDeniedPermissionTurnsSwitchOffAndShowsHint() async {
        let defaults = isolatedDefaults()
        var requests = 0
        let hint = expectation(description: "Denial hint")
        let state = AppState(
            defaults: defaults,
            authorizeNotifications: { requests += 1; return false },
            presentNotificationDenied: { hint.fulfill() }
        )

        state.showNotification = true
        await fulfillment(of: [hint], timeout: 2)

        XCTAssertEqual(requests, 1)
        XCTAssertFalse(state.showNotification)
        XCTAssertFalse(defaults.bool(forKey: "Snapboard_ShowNotification"))
        defaults.removeObject(forKey: "Snapboard_ShowNotification")
    }

    func testTurningOffWhileRequestIsPendingDoesNotReenableOrShowHint() async {
        let defaults = isolatedDefaults()
        var continuation: CheckedContinuation<Bool, Never>?
        let started = expectation(description: "Request started")
        let state = AppState(
            defaults: defaults,
            authorizeNotifications: {
                await withCheckedContinuation {
                    continuation = $0
                    started.fulfill()
                }
            },
            presentNotificationDenied: { XCTFail("Switch already off") }
        )
        state.showNotification = true
        await fulfillment(of: [started], timeout: 2)
        state.showNotification = false
        continuation?.resume(returning: false)
        for _ in 0..<100 where state.isRequestingNotificationAuthorization {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertFalse(state.isRequestingNotificationAuthorization)
        XCTAssertFalse(state.showNotification)
        defaults.removeObject(forKey: "Snapboard_ShowNotification")
    }

    func testRapidOffOnSharesPendingRequestAndKeepsGrantedSetting() async {
        let defaults = isolatedDefaults()
        var requests = 0
        var continuation: CheckedContinuation<Bool, Never>?
        let started = expectation(description: "Request started")
        let state = AppState(
            defaults: defaults,
            authorizeNotifications: {
                requests += 1
                return await withCheckedContinuation {
                    continuation = $0
                    started.fulfill()
                }
            },
            presentNotificationDenied: { XCTFail("Permission granted") }
        )
        state.showNotification = true
        await fulfillment(of: [started], timeout: 2)
        state.showNotification = false
        state.showNotification = true
        continuation?.resume(returning: true)
        for _ in 0..<100 where state.isRequestingNotificationAuthorization {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(requests, 1)
        XCTAssertFalse(state.isRequestingNotificationAuthorization)
        XCTAssertTrue(state.showNotification)
        defaults.removeObject(forKey: "Snapboard_ShowNotification")
    }
}
