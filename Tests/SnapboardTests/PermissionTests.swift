import AppKit
import UserNotifications
import XCTest
@testable import Snapboard

final class PermissionTests: XCTestCase {
    @MainActor
    func testMissingScreenPermissionBlocksBothModesAndRequestsOnlyOnce() {
        var requests = 0
        var dialogs = 0
        var launches = 0
        let service = CaptureService(
            preflight: { false },
            requestAccess: { requests += 1 },
            showPermissionDialog: { dialogs += 1; return false },
            runProcess: { _ in launches += 1 }
        )

        service.captureDirect()
        service.captureForEdit()

        XCTAssertEqual(launches, 0)
        XCTAssertEqual(dialogs, 2)
        XCTAssertEqual(requests, 1)
    }

    @MainActor
    func testSettingsButtonOpensScreenCapturePrivacyPaneWithoutCapturing() {
        var openedURL: URL?
        var launches = 0
        let service = CaptureService(
            preflight: { false },
            requestAccess: {},
            showPermissionDialog: { true },
            openURL: { openedURL = $0 },
            runProcess: { _ in launches += 1 }
        )

        service.captureForEdit()

        XCTAssertEqual(openedURL?.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        XCTAssertEqual(launches, 0)
    }

    @MainActor
    func testCancellingPermissionDialogDoesNotOpenSettingsOrCapture() {
        let service = CaptureService(
            preflight: { false },
            requestAccess: {},
            showPermissionDialog: { false },
            openURL: { _ in XCTFail("Dialog was cancelled") },
            runProcess: { _ in XCTFail("Permission is missing") }
        )
        service.captureDirect()
    }

    @MainActor
    func testGrantDuringSystemPromptRequiresAnotherCaptureAttempt() {
        var granted = false
        var launches = 0
        let service = CaptureService(
            preflight: { granted },
            requestAccess: { granted = true },
            showPermissionDialog: { false },
            runProcess: { _ in launches += 1 }
        )
        service.captureDirect()
        XCTAssertEqual(launches, 0)
        service.captureDirect()
        XCTAssertEqual(launches, 1)
    }

    @MainActor
    func testGrantedPermissionPreflightsEveryCaptureAndPreservesArguments() {
        var checks = 0
        var arguments: [[String]] = []
        let service = CaptureService(
            preflight: { checks += 1; return true },
            requestAccess: { XCTFail("Permission already granted") },
            showPermissionDialog: { XCTFail("Unexpected dialog"); return false },
            runProcess: { arguments.append($0.arguments ?? []) }
        )

        service.captureDirect()
        service.captureForEdit()

        XCTAssertEqual(checks, 2)
        XCTAssertEqual(arguments.first, ["-i", "-c"])
        XCTAssertEqual(arguments.last?.first, "-i")
        XCTAssertTrue(arguments.last?.last?.hasSuffix(".png") == true)
    }

    @MainActor
    func testLaunchErrorsArePresentedForBothModes() {
        var errors: [String] = []
        let service = CaptureService(
            preflight: { true },
            showCaptureError: { errors.append($0) },
            runProcess: { _ in throw NSError(domain: "CaptureTest", code: 1) }
        )

        service.captureDirect()
        service.captureForEdit()

        XCTAssertEqual(errors.count, 2)
        XCTAssertTrue(errors.allSatisfy { !$0.isEmpty })
    }

    @MainActor
    func testCancelledCapturesDoNotPresentErrors() {
        let service = CaptureService(
            showCaptureError: { _ in XCTFail("Esc must remain silent") }
        )
        service.finishDirectCapture(status: 1, clipboardChanged: false)
        service.finishDirectCapture(status: 0, clipboardChanged: false)
        let missingFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapboard-test-\(UUID().uuidString).png")
        service.finishEditorCapture(status: 1, tempFileURL: missingFile)
        service.finishEditorCapture(status: 0, tempFileURL: missingFile)
    }

    @MainActor
    func testCancelledEditorCaptureRemovesTemporaryFile() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapboard-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("cancelled capture".utf8).write(to: file)
        let service = CaptureService(
            showCaptureError: { _ in XCTFail("Esc must remain silent") }
        )
        service.finishEditorCapture(status: 1, tempFileURL: file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    @MainActor
    func testDefaultStartupDoesNotAskForNotifications() {
        withState { state, provider, _ in
            XCTAssertFalse(state.showNotification)
            XCTAssertEqual(provider.statusChecks, 0)
            XCTAssertEqual(provider.requests, 0)
            XCTAssertNil(state.notificationAuthorizationTask)
        }
    }

    @MainActor
    func testRestoringEnabledPreferenceDoesNotRequestAuthorizationAtStartup() {
        let suite = "SnapboardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "Snapboard_ShowNotification")
        let provider = NotificationStub()
        let state = AppState(defaults: defaults, notificationAuthorization: provider,
                             showNotificationDenied: {})
        XCTAssertTrue(state.showNotification)
        XCTAssertNil(state.notificationAuthorizationTask)
        XCTAssertEqual(provider.requests, 0)
        XCTAssertEqual(provider.statusChecks, 0)
    }

    @MainActor
    func testEnablingNotificationsRequestsOnceAndPersistsGrant() async {
        await withAsyncState { state, provider, defaults in
            provider.granted = true
            state.showNotification = true
            await state.notificationAuthorizationTask?.value

            XCTAssertTrue(state.showNotification)
            XCTAssertTrue(defaults.bool(forKey: "Snapboard_ShowNotification"))
            XCTAssertEqual(provider.requests, 1)

            provider.status = .authorized
            state.showNotification = false
            state.showNotification = true
            await state.notificationAuthorizationTask?.value
            XCTAssertEqual(provider.requests, 1)
        }
    }

    @MainActor
    func testDenialResetsAndPersistsToggleBeforeShowingNotice() async {
        var notices = 0
        await withAsyncState(notice: { notices += 1 }) { state, provider, defaults in
            state.showNotification = true
            await state.notificationAuthorizationTask?.value

            XCTAssertFalse(state.showNotification)
            XCTAssertFalse(defaults.bool(forKey: "Snapboard_ShowNotification"))
            XCTAssertEqual(provider.requests, 1)
            XCTAssertEqual(notices, 1)

            provider.status = .denied
            state.showNotification = true
            await state.notificationAuthorizationTask?.value
            XCTAssertEqual(provider.requests, 1)
            XCTAssertFalse(state.showNotification)
            XCTAssertEqual(notices, 2)
        }
    }

    @MainActor
    func testSwitchingOffDuringAuthorizationDoesNotShowDenial() async {
        let provider = NotificationStub()
        let suite = "SnapboardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let started = expectation(description: "Authorization started")
        provider.onRequest = { started.fulfill() }
        provider.suspendRequest = true
        let state = AppState(defaults: defaults, notificationAuthorization: provider,
                             showNotificationDenied: { XCTFail("Toggle was switched off") })
        state.showNotification = true
        await fulfillment(of: [started], timeout: 1)
        state.showNotification = false
        provider.continuation?.resume(returning: false)
        await state.notificationAuthorizationTask?.value
        XCTAssertFalse(state.showNotification)
    }

    @MainActor
    func testAuthorizationErrorDisablesNotifications() async {
        var notices = 0
        await withAsyncState(notice: { notices += 1 }) { state, provider, defaults in
            provider.requestError = NSError(domain: "NotificationTest", code: 1)
            state.showNotification = true
            await state.notificationAuthorizationTask?.value
            XCTAssertFalse(state.showNotification)
            XCTAssertFalse(defaults.bool(forKey: "Snapboard_ShowNotification"))
            XCTAssertEqual(notices, 1)
        }
    }

    @MainActor
    private func withState(_ body: (AppState, NotificationStub, UserDefaults) -> Void) {
        let suite = "SnapboardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let provider = NotificationStub()
        body(AppState(defaults: defaults, notificationAuthorization: provider,
                      showNotificationDenied: {}), provider, defaults)
    }

    @MainActor
    private func withAsyncState(
        notice: @escaping () -> Void = {},
        _ body: (AppState, NotificationStub, UserDefaults) async -> Void
    ) async {
        let suite = "SnapboardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let provider = NotificationStub()
        await body(AppState(defaults: defaults, notificationAuthorization: provider,
                            showNotificationDenied: notice), provider, defaults)
    }
}

@MainActor
private final class NotificationStub: NotificationAuthorizationProviding {
    var status: UNAuthorizationStatus = .notDetermined
    var granted = false
    var statusChecks = 0
    var requests = 0
    var suspendRequest = false
    var requestError: Error?
    var onRequest: (() -> Void)?
    var continuation: CheckedContinuation<Bool, Never>?

    func authorizationStatus() async -> UNAuthorizationStatus {
        statusChecks += 1
        return status
    }

    func requestAuthorization() async throws -> Bool {
        requests += 1
        if let requestError { throw requestError }
        if suspendRequest {
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                onRequest?()
            }
        }
        return granted
    }
}
