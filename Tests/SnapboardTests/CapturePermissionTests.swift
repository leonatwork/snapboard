import AppKit
import XCTest
@testable import Snapboard

@MainActor
final class CapturePermissionTests: XCTestCase {
    func testBothCaptureModesStopWhenPermissionIsMissingAndOpenPrivacyPane() async {
        var preflights = 0
        var requests = 0
        var dialogs = 0
        var launches = 0
        var openedURLs: [URL] = []
        let service = CaptureService(
            preflightScreenCapture: { preflights += 1; return false },
            requestScreenCapture: { requests += 1 },
            presentScreenCapturePermission: { dialogs += 1; return true },
            openScreenCaptureSettings: { openedURLs.append($0) },
            runProcess: { _ in launches += 1 },
            presentCaptureStartError: { _ in XCTFail("No process should start") }
        )

        service.captureDirect()
        service.captureForEdit()

        XCTAssertEqual(preflights, 2)
        XCTAssertEqual(dialogs, 2)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(launches, 0)
        XCTAssertEqual(openedURLs.map(\.absoluteString), Array(repeating:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture", count: 2))
    }

    func testDismissPermissionDialogDoesNotRequestOrOpenSettings() async {
        var requests = 0
        var launches = 0
        var opened = false
        let service = CaptureService(
            preflightScreenCapture: { false },
            requestScreenCapture: { requests += 1 },
            presentScreenCapturePermission: { false },
            openScreenCaptureSettings: { _ in opened = true },
            runProcess: { _ in launches += 1 },
            presentCaptureStartError: { _ in XCTFail("No process should start") }
        )

        service.captureDirect()

        XCTAssertEqual(requests, 0)
        XCTAssertEqual(launches, 0)
        XCTAssertFalse(opened)
    }

    func testBothCaptureModesRecheckPermissionAndKeepExistingArguments() async {
        var permitted = true
        var preflights = 0
        var dialogs = 0
        var arguments: [[String]] = []
        let service = CaptureService(
            preflightScreenCapture: { preflights += 1; return permitted },
            requestScreenCapture: { XCTFail("Already authorized") },
            presentScreenCapturePermission: { dialogs += 1; return false },
            runProcess: { process in
                XCTAssertEqual(process.executableURL?.path, "/usr/sbin/screencapture")
                arguments.append(process.arguments ?? [])
            },
            presentCaptureStartError: { _ in XCTFail("Launch should succeed") }
        )

        service.captureDirect()
        service.captureForEdit()
        permitted = false
        service.captureDirect()

        XCTAssertEqual(preflights, 3)
        XCTAssertEqual(dialogs, 1)
        XCTAssertEqual(arguments.count, 2)
        XCTAssertEqual(arguments.first, ["-i", "-c"])
        XCTAssertEqual(arguments.last?.first, "-i")
        XCTAssertTrue(arguments.last?.last?.hasSuffix(".png") == true)
    }

    func testStartFailureShowsErrorForBothModes() async {
        let failure = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        var errors: [NSError] = []
        let service = CaptureService(
            preflightScreenCapture: { true },
            requestScreenCapture: { XCTFail("Already authorized") },
            presentScreenCapturePermission: { XCTFail("Already authorized"); return false },
            runProcess: { _ in throw failure },
            presentCaptureStartError: { errors.append($0 as NSError) }
        )

        service.captureDirect()
        service.captureForEdit()

        XCTAssertEqual(errors.count, 2)
        XCTAssertTrue(errors.allSatisfy { $0.domain == failure.domain && $0.code == failure.code })
    }

    func testCancelledCaptureShowsNoErrorForBothModes() async throws {
        // A short-lived child models Esc: nonzero exit, no clipboard change or output file.
        // Never invoke screencapture or touch real privacy permissions from a unit test.
        for edit in [false, true] {
            var process: Process?
            var errors: [Error] = []
            let service = CaptureService(
                preflightScreenCapture: { true },
                requestScreenCapture: { XCTFail("Already authorized") },
                presentScreenCapturePermission: { XCTFail("Already authorized"); return false },
                runProcess: {
                    process = $0
                    $0.executableURL = URL(fileURLWithPath: "/usr/bin/false")
                    $0.arguments = []
                    try $0.run()
                },
                presentCaptureStartError: { errors.append($0) }
            )
            if edit { service.captureForEdit() } else { service.captureDirect() }
            let child = try XCTUnwrap(process)
            child.waitUntilExit()
            // Wait for the actual production termination handler's main-actor task.
            for _ in 0..<100 where service.hasActiveCapture {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTAssertFalse(service.hasActiveCapture)
            XCTAssertTrue(errors.isEmpty)
        }
    }
}
