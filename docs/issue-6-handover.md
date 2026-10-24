# Issue #6: macOS permissions — review handover

## Basis and limits

- Base: `6aac49f51ce9964c1b038f016fddfe9db45e103c`, identical to local
  `origin/main`; the worktree was clean before changes. No branch checkout,
  cherry-pick, commit, push, PR creation, merge or deployment was performed.
- Scope and acceptance criteria below come from the issue text provided in the
  task. GitHub access through `gh` was denied by the harness, so **the full comment
  thread, current open PRs, remote freshness and CI results could not be checked**.
  A reviewer must check these before treating the issue as complete. No dependency
  on an open PR is known, but this could not be verified.
- `CONTRIBUTING.md`, `Package.swift`, the macOS build workflow, localization checker
  and relevant sources were inspected. No `AGENTS.md` or `CLAUDE.md` exists in this
  checkout; access outside the workspace is denied.
- Linux has no Swift/Xcode/AppKit. The task explicitly forbids local app builds
  and test execution. A successful macOS build, executable red/green TDD proof and
  manual TCC/Gatekeeper checks therefore **remain outstanding**.

## Binding acceptance criteria

| AC | Implementation / evidence | Remaining verification |
| --- | --- | --- |
| 1 | Both `CaptureService` entry points call the same preflight guard before creating a capture process. Missing access shows a localized explanation and stops that attempt. Tests cover both modes. | Actual hotkeys, menu and Settings test buttons on macOS. |
| 2 | The affirmative dialog button opens `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`. The URL is asserted in tests. | Confirm the destination pane on macOS. |
| 3 | Granted access preserves `-i -c` for direct capture and `-i <temporary PNG>` for editing, without a permission dialog. Tests assert both commands. | Actual clipboard capture and editor opening. |
| 4 | A thrown process launch error shows a localized alert in both modes. Termination without successful output stays silent; a controlled nonzero subprocess tests cancellation. | Real Esc cancellation in both modes and visible launch-error alert. |
| 5 | AppDelegate no longer requests notification permission. Initializing AppState does not query or request it, including with a previously enabled setting. | Fresh installed app starts without the system prompt. |
| 6 | An off-to-on transition queries notification status and requests only if undetermined. Denial or API error persists the switch as off and shows a hint. Tests also cover existing permission, duplicate assignment and turning off during async work. | System prompt, Allow/Deny and already-denied behavior on macOS. |
| 7 | Both READMEs document macOS 15+ Gatekeeper / Open Anyway / „Dennoch öffnen“, screen recording permission and possible restart. | Follow the Gatekeeper flow on macOS 15+. |
| 8 | All seven new keys are translated in all ten `.lproj` files. The macOS CI job now runs the localization checker. | Full successful checker run on macOS. |

No contradictory product criteria were found in the supplied text. The demand
for executed failing tests before the fix cannot be met in the supplied Linux
environment under the explicit no-build/no-test-execution rule. Also, a green
`build-macos` cannot be produced here without the prohibited push/PR creation and
unavailable GitHub access. These are verification limits, not waived criteria.

`CGRequestScreenCaptureAccess` runs at most once **per app session**, only after
the user chooses to open System Settings. Even if it grants access, the original
capture attempt remains stopped. Subsequent attempts always preflight again.
The permission dialog suppresses reentrant capture shortcuts while it is open.

## Regression tests and checks

1. First added `Tests/SnapboardTests/CapturePermissionTests.swift`,
   `NotificationPermissionTests.swift` and the dependency-free SwiftPM test target.
2. Before changing production code, inspected the baseline: both services had
   only private initializers; no injectable permission boundary or notification
   authorization task existed. The tests would not compile against that baseline.
   **This is static evidence only, not an executed failing regression test.**
3. Implemented the boundaries and fixes. Added a further regression before its
   guard: switching off while awaiting notification status must not prompt.
4. `git diff --check`: passed. `bash -n scripts/check-localizations.sh`: passed.
5. `bash scripts/check-localizations.sh`: failed because `plutil` and
   `/usr/libexec/PlistBuddy` are absent. The script's key, duplicate, placeholder
   and source-key comparisons emitted no errors before the PlistBuddy failure.
   This does **not** establish successful native `.strings`/plist linting.
6. Swift tests and app builds were not executed. CI steps were added to
   `build-macos`; no CI result is claimed.

On macOS, run:

```bash
swift test --filter CapturePermissionTests
swift test --filter NotificationPermissionTests
./scripts/check-localizations.sh
./scripts/build_app.sh
```

The workflow runs `swift test` (both test classes), the localization checker and
the existing app build. Permission APIs, dialogs and process starts are injectable;
automated tests do not request real permissions or invoke `screencapture`.
The cancellation test runs `/usr/bin/false` only. Test preferences use disposable,
unique UserDefaults suites rather than installed Snapboard preferences.

## Manual macOS verification still required

Use an isolated test installation/account; the reset commands below are instructions,
not commands executed by this agent.

1. Reset screen capture permission with
   `tccutil reset ScreenCapture com.leon.snapboard`. Try `⌘⇧1` and `⌘⇧2`, plus the
   menu actions and Settings test buttons. No capture should start. Check localized
   explanation, Cancel and the possible-restart hint.
2. Choose Open System Settings. Confirm the Screen & System Audio Recording pane
   and that Snapboard is available in its list. The first affirmative action may
   also show Apple's permission request. Repeated attempts in this session must
   not call that request again. Enable access and restart if needed.
3. Retry both modes: direct capture updates the clipboard; edit capture opens
   the editor. There should be no additional permission dialog. Cancel both with
   Esc and confirm no error alert.
4. In a debugger/test harness, inject a failing process starter to check the
   visible localized launch-error alert; do not modify the system screenshot tool.
5. Reset test-app permissions with `tccutil reset All com.leon.snapboard` and start
   with default preferences. No notification prompt should appear. Enable the
   notification switch and test Allow. Reset again and test Deny: switch off,
   persisted off after restart, explanatory hint. With permission already denied,
   enabling must show the hint without another system prompt. Also test rapidly
   turning the switch off while permission work is pending.
6. Follow each README's first-launch instructions using a downloaded release on
   macOS 15+; confirm the Open Anyway / „Dennoch öffnen“ Gatekeeper flow.

Before closing the issue, inspect its full thread and open PRs, review the diff,
and obtain a green `build-macos` plus the manual results above.
