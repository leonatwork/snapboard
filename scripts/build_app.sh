#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

echo "🔨 Erstelle Snapboard..."

# 1. Icons generieren
echo "🎨 Generiere App-Icon..."
mkdir -p Resources
swift scripts/generate_icon.swift
iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns
rm -rf AppIcon.iconset

# 2. Release-Build kompilieren
echo "⚙️ Kompiliere Release-Binärdatei..."
swift build -c release

# 3. .app Bundle-Struktur erstellen
APP_NAME="Snapboard.app"
APP_DIR="$PROJECT_DIR/build/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$PROJECT_DIR/build"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "📦 Erstelle $APP_NAME..."
cp ".build/release/Snapboard" "$MACOS_DIR/Snapboard"
cp "Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

# 4. Ad-hoc Codesigning
echo "✍️ Signiere Anwendung ad-hoc..."
codesign --force --deep --sign - "$APP_DIR"

echo "✅ Erfolgreich erstellt: $APP_DIR"
echo ""
echo "Um Snapboard in deine Programme zu installieren, führe aus:"
echo "  cp -R \"$APP_DIR\" /Applications/"
