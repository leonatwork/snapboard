# Contributing to Snapboard

Thank you for your interest in contributing to Snapboard!

## Development & Building

### macOS
Requirements: macOS 14+, Xcode 15+ or Swift 6+.
```bash
# Build & Run Locally
swift build
swift run

# Build .app Bundle
./scripts/build_app.sh

# Install into /Applications
./scripts/install.sh
```

### Windows
Requirements: Windows 10/11, .NET 8 SDK.
```bash
cd windows
dotnet build Snapboard.Windows\Snapboard.Windows.csproj -c Release
```

### README screenshots
The images in `docs/screenshots/` (`<name>.png` in English, `<name>.de.png` in German) are rendered
offscreen by a small harness, never captured from the screen:
```bash
./scripts/screenshots/render.sh
```
The harness in `scripts/screenshots/` compiles the app sources without the app entry point, runs them
inside a temporary `.app` bundle (so the `.lproj` localizations work) with its own bundle identifier,
and draws a demo image instead of a real screenshot. It does not read or change the settings of an
installed Snapboard. If your default SDK cannot compile SwiftUI, set `SDKROOT` to another macOS SDK.
`--all-languages` renders every localization into `build/screenshots/languages/` for review, and
`--verify-text` checks that the editor preview draws text annotations exactly like the exported image.
`--verify-annotations` separately checks all eight tools at widths 2/4/7 on 400×300 and
3000×2000 pixel images, both native and fitted, and compares exports pixel-for-pixel with
the frozen pre-issue-#8 renderer. Before/export/preview PNGs are written to
`build/screenshots/verify-annotations/`. `--verify-text` retains its existing check.

Editor regression checks (run on the corresponding platform):
```bash
# macOS
swift test --filter 'AnnotationPreviewTests|AnnotationRenderingRegressionTests|EditorExportTests'
./scripts/screenshots/render.sh --verify-text
./scripts/screenshots/render.sh --verify-annotations

# Windows: dependency-free regression runner, or annotation-only checks with PNG artifacts
dotnet run --project windows/Tests/Snapboard.Windows.Tests.csproj -c Release
dotnet run --project windows/Tests/Snapboard.Windows.Tests.csproj -c Release -- --verify-annotations build/annotations-windows
```
The frozen renderers in `scripts/screenshots/` and `windows/Tests/` are test oracles from
`2306fc6`; do not update their geometry or styles when changing the production renderer.

## Pull Requests & Issues
- Keep PRs focused and well-scoped.
- Ensure macOS and Windows builds pass cleanly in CI.

## License of contributions

Contributions are accepted under the MIT License, the same license as the project.
Optional premium add-ons are developed separately. Community contributions are only
included there with the contributor's explicit consent.
