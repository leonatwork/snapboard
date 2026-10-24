import AppKit
import XCTest
@testable import Snapboard

@MainActor
final class CapturePermissionTests: XCTestCase {
    func testBothModesStopBeforeLaunchingWhenPermissionIsMissing() async {
        var checks = 0
        var dialogs = 0
        var launches = 0
        let service = CaptureService(
            preflight: { checks += 1; return false },
            requestAccess: { XCTFail("Cancel must not request access") },
            permissionDialog: { dialogs += 1; return false },
            openSettings: { _ in XCTFail("Cancel must not open Settings") },
            startProcess: { _ in launches += 1 }
        )

        service.captureDirect()
        service.captureForEdit()

        XCTAssertEqual(checks, 2)
        XCTAssertEqual(dialogs, 2)
        XCTAssertEqual(launches, 0)
    }

    func testSettingsLinkAndOneAccessRequestWithoutStartingCapture() async {
        var requests = 0
        var urls: [URL] = []
        let service = CaptureService(
            preflight: { false },
            requestAccess: { requests += 1 },
            permissionDialog: { true },
            openSettings: { urls.append($0) },
            startProcess: { _ in XCTFail("Denied capture must not start") }
        )

        service.captureDirect()
        service.captureForEdit()

        XCTAssertEqual(requests, 1)
        XCTAssertEqual(urls.map(\.absoluteString), Array(repeating:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture", count: 2))
    }

    func testGrantedPermissionPreservesBothCaptureCommands() async {
        var arguments: [[String]] = []
        let service = CaptureService(
            preflight: { true },
            permissionDialog: { XCTFail("Granted access must not show a dialog"); return false },
            startProcess: { arguments.append($0.arguments ?? []) }
        )

        service.captureDirect()
        service.captureForEdit()

        XCTAssertEqual(arguments.first, ["-i", "-c"])
        XCTAssertEqual(arguments.last?.first, "-i")
        XCTAssertTrue(arguments.last?.last?.hasSuffix(".png") == true)
    }

    func testLaunchErrorsShowAnAlertForBothModes() async {
        var errors = 0
        let service = CaptureService(
            preflight: { true },
            startProcess: { _ in throw CocoaError(.executableNotLoadable) },
            launchErrorDialog: { errors += 1 }
        )

        service.captureDirect()
        service.captureForEdit()

        XCTAssertEqual(errors, 2)
    }

    func testCancelledProcessesDoNotShowErrors() async throws {
        // A nonzero termination without output models Esc, not a launch failure.
        for edit in [false, true] {
            let terminated = expectation(description: "Capture termination handled")
            let service = CaptureService(
                preflight: { true },
                startProcess: { process in
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/false")
                    process.arguments = []
                    let handler = process.terminationHandler
                    process.terminationHandler = { process in
                        handler?(process)
                        Task { @MainActor in terminated.fulfill() }
                    }
                    try process.run()
                },
                launchErrorDialog: { XCTFail("Cancellation must stay silent") }
            )
            if edit { service.captureForEdit() } else { service.captureDirect() }
            await fulfillment(of: [terminated], timeout: 5)
            // Let the main-actor termination handler finish before releasing the service.
            await Task.yield()
        }
    }
}
