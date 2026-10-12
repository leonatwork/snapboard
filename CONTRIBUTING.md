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

## Pull Requests & Issues
- Keep PRs focused and well-scoped.
- Ensure macOS and Windows builds pass cleanly in CI.

## License of contributions

Contributions are accepted under the MIT License, the same license as the project.
Optional premium add-ons are developed separately. Community contributions are only
included there with the contributor's explicit consent.
