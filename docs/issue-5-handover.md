# Issue #5: macOS editor export handover

## Basis and review limits

- Starting tree: clean, `HEAD` and local `origin/main` both at
  `6aac49f51ce9964c1b038f016fddfe9db45e103c`. No checkout, branch creation,
  cherry-pick, commit or push was performed.
- Read `CONTRIBUTING.md`, the package, build workflow, localization checker,
  screenshot harness and capture/editor/export code. No `AGENTS.md` or
  `CLAUDE.md` exists in this repository checkout.
- The supplied structured issue description is the acceptance baseline.
  Fetching the live issue/comments and open PR list with `gh` was blocked by
  tool permissions. Additional comments, contradictions with them, remote-main
  freshness and open-PR dependencies could therefore not be verified.
- This solution uses only the checked-out main code; it introduces no known
  dependency on an open PR and no external packages.

## Acceptance criteria

The structured AC-6 applies to **both copying and saving**, including rendering
failure before the save dialog. Source point size is authoritative, PNG is the
first clipboard type, TIFF is the fallback, and error alerts have only OK.
No contradictions were found within this supplied baseline.

| Criterion | Implementation and automated coverage | Remaining evidence |
| --- | --- | --- |
| AC-1: same Notes size as direct capture | Renderer retains source point size; copy test covers unannotated 2x images | Compare ⌘⇧2 with ⌘⇧1 in Notes on Retina Mac |
| AC-2: exact source pixels with annotations | Existing pixel-space rendering unchanged; renderer, clipboard and saved-file tests assert both pixel dimensions | Run macOS tests |
| AC-3: PNG and TIFF on clipboard | One pasteboard item, PNG inserted before TIFF; tests assert types/order and metadata | Run tests; inspect `NSPasteboard.general` manually |
| AC-4: original width and 144 dpi | PNG directly from `NSBitmapImageRep(cgImage:)` with source point size; ImageIO assertions check width/height and both DPI axes | Run tests and `sips -g pixelWidth -g dpiWidth <saved.png>` on Retina Mac |
| AC-5: localized write error, editor stays open | Catch reports original system error's `localizedDescription`; deterministic file-error test preserves annotations and undo history | Run tests; attempt save to unwritable folder as ordinary macOS user |
| AC-6: render error visible for copy/save | Both actions report localized error, never invoke close on failure; test also retains previous clipboard/state and avoids opening save panel | Run tests; inspect localized alert UI |
| AC-7: unchanged 1x size/pixels | Renderer, clipboard and saved-file tests cover 1x and 72 dpi | Run tests and repeat manual comparison on 1x display |
| AC-8: localization and text checks pass | Five new messages in all ten localizations; both checks added to `build-macos` | Successful macOS execution required |

## Test-first work and verification status

`Tests/SnapboardTests/EditorExportTests.swift` and the test target were added
before production code was changed. The renderer regression is directly
applicable to the old renderer: a 160×100-pixel image with 80×50-point size
would incorrectly return 160×100 points. The action tests use small new seams
for an isolated pasteboard, save destination selection and error presentation.
They additionally cover cancellation and annotation/undo preservation.

**No executed red/green test result is claimed.** This Linux host has no
Swift/Xcode/AppKit and the task expressly prohibits building/running the app
here. Tests therefore could not compile or execute before or after the fix.
The pre-fix failure is a source-level expectation, not an observed failure.

Checks performed locally:

- `git diff --check`: passed.
- `bash scripts/check-localizations.sh`: attempted, unsuccessful because
  `plutil` and `/usr/libexec/PlistBuddy` are absent. Its key/duplicate/placeholder
  comparisons reported no differences before the missing PlistBuddy stopped it.
- Screenshot rendering and macOS tests/build: not run on Linux.
- CI: not triggered or observed; a green `build-macos` remains required.

On macOS, run:

```bash
swift test --filter EditorExportTests
scripts/check-localizations.sh
scripts/screenshots/render.sh --verify-text
```

The `build-macos` CI job now runs these checks and the existing app build.
For an observed red proof, a reviewer can run the renderer regression with
the old return size (`NSSize(width: pixelWidth, height: pixelHeight)`) restored
temporarily, then restore the fix and run the full export test class.

PNG DPI uses integral pixels/metre; automated DPI assertions allow 0.02 dpi
rounding tolerance. Tests use unique pasteboards and temporary files instead of
the general clipboard and avoid interactive dialogs.

## Scope

Capture/direct mode, annotation drawing and preview geometry, Windows and
additional formats were not changed. No production deployment or production
data access occurred. No PR was created or merged, per the delivery instructions.
