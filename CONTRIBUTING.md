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

## Pull Requests & Issues
- Keep PRs focused and well-scoped.
- Ensure macOS and Windows builds pass cleanly in CI.

## License of contributions

Contributions are accepted under the MIT License, the same license as the project.
Optional premium add-ons are developed separately. Community contributions are only
included there with the contributor's explicit consent.
