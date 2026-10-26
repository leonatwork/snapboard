# Issue #7 — Windows reliability and large-image editor

## Basis and review boundaries

- Source: supplied issue description, including its structured decisions/AC-1–8.
- Starting HEAD equals local `origin/main`:
  `6aac49f51ce9964c1b038f016fddfe9db45e103c`; working tree was clean.
- `CONTRIBUTING.md`, Windows sources and `.github/workflows/build.yml` reviewed.
  No `CLAUDE.md` or `AGENTS.md` exists inside this checkout. Ancestor-rule lookup
  was blocked by the workspace access restriction.
- Reading the live issue thread/comments and listing open PRs with `gh` was
  denied by the environment. Their contents and any PR dependency could not be
  verified. Review that information before accepting this handover.
- No other PR source was used. No branch checkout/creation, cherry-pick, commit,
  push, PR creation, merge, deployment or production-data access was performed.

## Binding acceptance criteria and implementation

| AC | Implementation | Evidence / remaining verification |
| --- | --- | --- |
| 1 | Shared clipboard helper: **three total attempts**, 100 ms between attempts; direct capture balloon; editor message and return before closing. | Injected retry/lock/recovery tests written; real Windows contention and retained annotations require manual check. |
| 2 | `Application.ThreadException` and `AppDomain.UnhandledException` registered before UI initialization, German error message with recursion guard. UI exceptions use CatchException mode. | UI continuation requires Windows fault injection. Universal continuation after a fatal unhandled CLR exception is impossible; see below. |
| 3 | Both hotkey/tray entry points use one UI-thread gate before creating an overlay; reset in `finally`. | Nested entry and exception-reset regression test written; actual WM_HOTKEY/manual overlay checks pending. |
| 4 | Each RegisterHotKey result checked independently; startup dialog names failed shortcuts after tray initialization. | Windows conflict checks pending. |
| 5 | Registry write errors reported, missing key created explicitly; menu refreshed from a fresh read after every change and on opening. | Windows permissions checks pending. Unreadable status is indeterminate and disabled, with error feedback. |
| 6 | Selected filter drives PNG or JPEG encoder; JPEG quality parameter 90, filename without fixed PNG suffix. | In-memory signature/dimension tests written; dialog extension check pending. |
| 7 | Outer window clamped/centered in WorkingArea after initial DPI scaling. Default fit, toolbar 100% toggle, real AutoScrollMinSize. Drawing and hit conversion share bounds/scale/scroll; annotations stay in image pixels. Export draws source using explicit pixel rectangles. | Geometry and large-editor/scroll/full-size annotation export tests written; multi-monitor and DPI checks pending. |
| 8 | Existing build-windows job extended to run the dependency-free Windows regression runner after app build. | CI was not triggered or queried; **green build-windows is not yet demonstrated**. |

The structured AC-1 specifies “after 3 attempts”; that governs the ambiguous
“3 × 100 ms repetition” wording: one initial attempt and two retries, separated
by two 100 ms waits. No delay is needed after the final failure.
The clipboard helper uses an image DataObject with `SetDataObject`'s built-in
retries disabled, avoiding the additional retries hidden inside WinForms'
`Clipboard.SetImage`. Its own policy is therefore the only retry loop.

## Non-fulfillable or unverified requirements

1. **AC-2's universal survival guarantee conflicts with .NET behavior.**
   `AppDomain.UnhandledException` is a notification, not a recovery mechanism.
   When `IsTerminating` is true, the runtime terminates the process after the
   handler returns. The message explains the required restart. UI event exceptions
   are caught by WinForms and can leave the tray/message loop running. Stack
   overflow, corrupted-state failures and similar fatal errors cannot be given a
   reliable continuation guarantee either.
2. **Unknown Registry status cannot show the actual boolean value.** If the
   reread itself fails, the menu shows indeterminate/disabled and reports the
   read failure; it does not claim autostart is off. A writable-state failure with
   readable Registry state follows AC-5 exactly.
3. **Executed TDD and CI proof blocked by task/host constraints.** Tests were
   written first; expected base compilation failure inspected, but no build or
   test was executed because the task explicitly forbids it here. Do not treat
   source inspection as a passing test run. Windows validation is still required.
4. **Full live thread/PR review blocked by tool permissions.** No dependency on
   an open PR is known from the supplied description; live comments may contain
   additional decisions. No implementation from another PR was imported.

## Verification and next review steps

`git diff --check` passed locally. All changed/new Windows sources, project files,
tests and the workflow were reviewed statically. No packages were added.

On Windows 10/11 with .NET 8, run:

```powershell
dotnet build windows/Snapboard.Windows/Snapboard.Windows.csproj -c Release
dotnet run --project windows/Tests/Snapboard.Windows.Tests.csproj -c Release
```

Follow the AC-specific manual procedure in `windows/Tests/README.md`, review the
live issue/comments and open PRs, then obtain a green `build-windows` run. This
handover deliberately records those results as pending rather than inventing
test/CI evidence.
