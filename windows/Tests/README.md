# Windows regression tests — Issue #7

The runner uses only the .NET SDK and the app project; no test packages or other
dependencies are required. Run on Windows 10/11 with .NET 8:

```powershell
dotnet build windows/Snapboard.Windows/Snapboard.Windows.csproj -c Release
dotnet run --project windows/Tests/Snapboard.Windows.Tests.csproj -c Release
```

Each case prints PASS/FAIL; any failure returns exit code 1. The `build-windows`
job runs both commands. Clipboard contention is injected into the same retry
function used by both capture paths. It does not change the real clipboard or
Registry. The editor test opens a temporary form, exercises fit/100% scrolling,
simulates mouse drawing in both views and verifies full-resolution annotation
export in memory. Encoded PNG/JPEG data
also stays in memory.

## Test-first evidence and execution limits

`Program.cs` and the test project were added before production changes. On base
commit `6aac49f51ce9964c1b038f016fddfe9db45e103c`, the regression runner references
missing `ClipboardRetry`, `CaptureGate`, `ImageExport`, and `EditorGeometry`
types, so its expected initial result is compilation failure. This is an
expected result established by source inspection, **not an executed red test**.

The task forbids building or running apps/tests on this Linux host. Neither the
initial failure nor a passing result was executed here. The Windows commands
above and the manual checks below remain required. There is no existing test
framework/style in the checked-out repository.

## Manual checks on a disposable Windows test environment

Use a local build; close any installed Snapboard instance first because of the
single-instance mutex. Use test captures without sensitive contents.

1. **AC-1 — Clipboard:** With a separate test process holding `OpenClipboard`
   until `CloseClipboard`, perform direct capture. Expect no crash and a tray
   balloon after three failed attempts (100 ms between attempts). Repeat in an
   editor containing annotations; expect a message and the same editor/annotations
   still open. Release the clipboard lock and retry: copy succeeds and closes the
   editor. Also release the lock between attempts and verify recovery.
2. **AC-2 — Exceptions:** With a debugger/test-only fault injection, throw from a
   WinForms UI event. Expect a German error message; dismiss it, then verify the
   tray menu and both hotkeys. Inject a capture error escaping its callback and
   verify the gate resets. An unhandled background-thread exception must report
   that a restart is needed; .NET terminates that process (see handover).
3. **AC-3 — Reentry:** While an overlay is open, press each hotkey repeatedly,
   including the other capture hotkey. Expect only one overlay. Test cancellation
   with Escape and successful selections; both hotkeys must work afterward.
4. **AC-4 — Hotkeys:** Reserve Strg+Umschalt+1 with a separate test application
   before launch. Expect a startup message naming only that unavailable shortcut;
   Strg+Umschalt+2 works. Repeat with only 2 blocked, then both blocked; capture
   remains available from the tray menu.
5. **AC-5 — Autostart:** In a disposable Windows user profile, deny write access
   to the Run key while preserving read access. Toggle autostart. Expect an error
   and an unchanged check reflecting the actual entry. Test both enable/disable
   failures and a missing Run key. Restore permissions. If reads are denied too,
   expect an error and an indeterminate, disabled item rather than a false state;
   reopening the menu after permissions recover refreshes it. Do not modify a
   production user's autostart or Registry permissions.
6. **AC-6 — Formats:** Save with each filter (also switching filters and entering
   an extension manually). JPEG-filter output starts `FF D8`; PNG starts
   `89 50 4E 47 0D 0A 1A 0A`. Filter determines encoding; JPEG quality is fixed at
   90. Check automatic extensions when no extension is typed.
7. **AC-7 — Large images:** Capture across two monitors/4K; include a monitor
   with a negative desktop origin, taskbar and non-default DPI. The outer editor
   bounds must lie in the selected screen's WorkingArea on opening. Fit is the
   default; 100% enables both needed scrollbars. Annotate near all four corners
   in both modes (including text, steps and freehand), resize, switch modes and
   scroll to the far edges. Compare copy/PNG/JPEG exports with the original pixel
   dimensions and annotation positions. Letterbox clicks must not add annotations;
   dragging out of the image clamps to its edge. Pixelation preview remains the
   existing placeholder; changing that preview is outside this issue.
