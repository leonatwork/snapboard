# Issue #6 — macOS permissions handover

## Basis and review boundaries

- Implementation base: clean checkout at `6aac49f51ce9964c1b038f016fddfe9db45e103c`, identical to the locally available `origin/main`.
- Read `CONTRIBUTING.md`, the supplied complete issue description, app sources, localization checker and build workflow. No `AGENTS.md` or `CLAUDE.md` exists in this repository checkout.
- Reading the live issue thread/comments and listing open PRs with `gh` were blocked by tool permissions. Consequently, additional comments, upstream freshness, and possible open-PR dependencies could not be verified. No known dependency is required by the implementation on this checkout.
- No branch checkout/creation, cherry-pick, commit, push, PR creation, deployment, release, signing change or production access was performed.

## Acceptance criteria

The supplied issue's AC-1–AC-8 are the binding implementation scope; no contradiction between these criteria was identified. ScreenCaptureKit remains a separate, nonblocking future question.

| Criterion | Implementation and evidence | Remaining verification |
| --- | --- | --- |
| AC-1 | Both `CaptureService` entry points use the same preflight guard before creating/launching a capture. Missing access shows a localized dialog and always returns. System access is requested at most once per service lifetime (once per app run for the singleton). Tests cover both modes and a grant during the system prompt. | Real TCC and hotkey/menu/settings-button checks on macOS. |
| AC-2 | Dialog confirmation opens exactly `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`; cancellation does not open it. Both actions have regression tests. | Verify the destination on macOS. |
| AC-3 | Granted access preserves direct `-i -c` and editor `-i <temporary PNG>` arguments; no permission dialog is shown. Regression test checks repeated preflight and both argument sets. | Real screenshots, clipboard and editor on macOS. |
| AC-4 | Both process-launch catch paths show a localized error including system details. Termination/non-result handling stays silent, including Esc; editor temporary-file cleanup is tested. | Real Esc cancellation in both modes. |
| AC-5 | Removed notification request from app startup. Defaults remain off. Tests cover defaults and restoring an enabled preference without requesting authorization. | Fresh app launch with reset notification permission. |
| AC-6 | Existing toggle's off-to-on transition queries notification settings, requests only when undetermined, and resets/persists off before a denial notice. Requests are serialized; stale results after toggling off are ignored. Tests cover grant, known denial, authorization error, persistence and toggling off during a request. | Real macOS Allow/Don't Allow flows and rapid toggle changes. |
| AC-7 | Both READMEs explain macOS 15+ Gatekeeper/Open Anyway/„Dennoch öffnen“, screen recording permission, possible restart and opt-in notifications. | Gatekeeper walkthrough on macOS 15+. |
| AC-8 | Seven new localized keys in all ten languages. Full checker is wired into `build-macos`. | Successful checker execution on macOS. |

## Test-first sequence and executed checks

1. Added the XCTest target and initial regression tests **before** changing app code. The original code lacks the injectable initializers, completion methods and notification provider used by the tests, and requests notifications unconditionally at startup. This is the expected pre-fix failure, **not an executed red result**.
2. Implemented the guarded capture and opt-in notification behavior; supplemented edge-case regression coverage during review.
3. `git diff --check`: passed.
4. `bash scripts/check-localizations.sh`: attempted, failed because Linux lacks `plutil` and `/usr/libexec/PlistBuddy`. Its key/duplicate/placeholder/used-key comparisons reported no discrepancies before the unavailable plist step. This does **not** establish AC-8 as passed.
5. Swift tests, Swift builds and macOS application execution were not attempted: this server is Linux without Swift/Xcode/AppKit and the task explicitly prohibits building/running them here.

The `build-macos` CI job now runs `swift test --filter PermissionTests`, `scripts/check-localizations.sh` and the existing app build. No CI run was triggered or observed in this session. A green `build-macos` result, verified red/green Swift test execution and manual macOS evidence remain outstanding; the change is ready for review, not fully acceptance-verified.

## macOS verification to complete

Use a development/test Mac and the app bundle identifier `com.leon.snapboard`:

1. Run `swift test --filter PermissionTests`, `./scripts/check-localizations.sh` and `./scripts/build_app.sh`. Confirm `build-macos` is green when submitted through the normal review process.
2. Quit Snapboard, run `tccutil reset ScreenCapture com.leon.snapboard`, then launch it. Exercise `⌘⇧1` and `⌘⇧2` without granting access: no selection/capture/editor should start; the localized explanation should appear. Also check menu entries and both settings test buttons.
3. Cancel the dialog once, then confirm **Open System Settings**. Verify the Screen & System Audio Recording pane, enable Snapboard, quit/reopen if necessary, and retry both shortcuts. Verify clipboard output and editor output without another permission dialog.
4. With permission granted, abort both modes using Esc: no error dialog; clipboard unchanged and no temporary screenshot left behind.
5. Reset permissions using `tccutil reset All com.leon.snapboard` on the test Mac and ensure the existing notification switch is off (the TCC reset does not reset app preferences). Restart: no notification request. Switch it on and allow: switch stays on and direct capture sends a notification. Repeat with denial: switch is off and a notice appears; another enable attempt must not generate another native permission prompt. Also switch off while authorization is pending.
6. On macOS 15+, follow each README's Gatekeeper instructions using a quarantined release download. Check the dialog in German and English and review the new strings in the other languages.

Tests inject screen permission checks, dialogs, process launch and notification authorization. They do not invoke real capture/TCC/notification requests and use isolated UserDefaults suites.
