import XCTest
import UserNotifications
@testable import Snapboard

@MainActor
final class NotificationPermissionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "SnapboardTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testStartupDoesNotAskEvenWithPreviouslyEnabledNotifications() async {
        for enabled in [false, true] {
            defaults.set(enabled, forKey: "Snapboard_ShowNotification")
            let state = AppState(defaults: defaults, notificationAuthorization: .init(
                status: { XCTFail("Startup must not query permission"); return .notDetermined },
                request: { XCTFail("Startup must not prompt"); return false }
            ))
            XCTAssertEqual(state.showNotification, enabled)
            XCTAssertNil(state.notificationAuthorizationTask)
        }
    }

    func testEnablingRequestsOnceAndPersistsGrantedSetting() async {
        var requests = 0
        let state = AppState(defaults: defaults, notificationAuthorization: .init(
            status: { .notDetermined }, request: { requests += 1; return true }
        ))
        state.showNotification = true
        state.showNotification = true
        await state.notificationAuthorizationTask?.value
        XCTAssertEqual(requests, 1)
        XCTAssertTrue(state.showNotification)
        XCTAssertTrue(defaults.bool(forKey: "Snapboard_ShowNotification"))
    }

    func testDeniedAndFailedRequestsDisableSettingAndExplain() async {
        for status in [UNAuthorizationStatus.notDetermined, .denied] {
            var notices = 0
            let state = AppState(defaults: defaults, notificationAuthorization: .init(
                status: { status }, request: { false }
            ), notificationDeniedDialog: { notices += 1 })
            state.showNotification = true
            await state.notificationAuthorizationTask?.value
            XCTAssertFalse(state.showNotification)
            XCTAssertFalse(defaults.bool(forKey: "Snapboard_ShowNotification"))
            XCTAssertEqual(notices, 1)
        }
        let state = AppState(defaults: defaults, notificationAuthorization: .init(
            status: { .notDetermined }, request: { throw CocoaError(.featureUnsupported) }
        ), notificationDeniedDialog: {})
        state.showNotification = true
        await state.notificationAuthorizationTask?.value
        XCTAssertFalse(state.showNotification)
    }

    func testAlreadyAuthorizedDoesNotRequestAgain() async {
        let state = AppState(defaults: defaults, notificationAuthorization: .init(
            status: { .authorized }, request: { XCTFail("Must not request again"); return false }
        ))
        state.showNotification = true
        await state.notificationAuthorizationTask?.value
        XCTAssertTrue(state.showNotification)
    }

    func testTurningOffDuringRequestDoesNotReenableOrShowDenialNotice() async throws {
        var reply: CheckedContinuation<Bool, Never>?
        let started = expectation(description: "Authorization request started")
        let state = AppState(defaults: defaults, notificationAuthorization: .init(
            status: { .notDetermined },
            request: { await withCheckedContinuation { reply = $0; started.fulfill() } }
        ), notificationDeniedDialog: { XCTFail("An off setting needs no notice") })
        state.showNotification = true
        await fulfillment(of: [started], timeout: 5)
        let continuation = try XCTUnwrap(reply)
        state.showNotification = false
        continuation.resume(returning: false)
        await state.notificationAuthorizationTask?.value
        XCTAssertFalse(state.showNotification)
    }

    func testTurningOffDuringStatusQueryDoesNotPrompt() async throws {
        var reply: CheckedContinuation<UNAuthorizationStatus, Never>?
        let started = expectation(description: "Notification status query started")
        let state = AppState(defaults: defaults, notificationAuthorization: .init(
            status: { await withCheckedContinuation { reply = $0; started.fulfill() } },
            request: { XCTFail("Do not prompt when the switch is already off"); return false }
        ), notificationDeniedDialog: { XCTFail("No notice needed when off") })
        state.showNotification = true
        await fulfillment(of: [started], timeout: 5)
        let continuation = try XCTUnwrap(reply)
        state.showNotification = false
        continuation.resume(returning: .notDetermined)
        await state.notificationAuthorizationTask?.value
        XCTAssertFalse(state.showNotification)
    }
}
