#!/bin/bash
# Renders the README screenshots (docs/screenshots/*.png) offscreen.
#
# The harness in this folder is compiled together with the app sources (without the app
# entry point) and run inside a temporary .app bundle with the .lproj localizations.
# It never captures the screen: the editor shows a drawn demo image. It uses its own
# bundle identifier, so the settings of an installed Snapboard are never read or changed.
#
# Usage: scripts/screenshots/render.sh [--debug] [--all-languages | --verify-text]
#   --all-languages  render every localization into build/screenshots/languages (for review)
#   --verify-text    check that the editor preview draws text annotations like the export
# If your default SDK fails to compile SwiftUI, point SDKROOT at another macOS SDK.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_DIR"

BUNDLE_ID="local.snapboard.screenshot-harness"
WORK_DIR="$PROJECT_DIR/build/screenshots"
APP_DIR="$WORK_DIR/SnapboardScreenshots.app"
OUT_DIR="$PROJECT_DIR/docs/screenshots"

rm -rf "$WORK_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

echo "Compiling screenshot harness..."
SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done < <(
  find Sources -name '*.swift' ! -name 'AppDelegate.swift' | sort
)
swiftc -O -swift-version 5 \
  "${SOURCES[@]}" scripts/screenshots/DemoContent.swift scripts/screenshots/main.swift \
  -o "$APP_DIR/Contents/MacOS/SnapboardScreenshots"

cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleIdentifier $BUNDLE_ID" \
  -c "Set :CFBundleExecutable SnapboardScreenshots" \
  -c "Set :CFBundleName SnapboardScreenshots" \
  "$APP_DIR/Contents/Info.plist"
for LPROJ in Resources/*.lproj; do
  cp -R "$LPROJ" "$APP_DIR/Contents/Resources/"
done

DEBUG_ARGS=()
ALL_LANGUAGES=0
VERIFY_TEXT=0
for arg in "$@"; do
  case "$arg" in
    --debug) DEBUG_ARGS=(--debug "$WORK_DIR/debug") ;;
    --all-languages) ALL_LANGUAGES=1 ;;
    --verify-text) VERIFY_TEXT=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

run_harness() {
  local lang="$1"; shift
  "$APP_DIR/Contents/MacOS/SnapboardScreenshots" "$@" ${DEBUG_ARGS[@]+"${DEBUG_ARGS[@]}"} \
    -AppleLanguages "($lang)" -AppleLocale "$lang" -AppleAccentColor 4
}

render() {
  local lang="$1" suffix="$2"
  echo "Rendering ($lang)..."
  run_harness "$lang" --out "$OUT_DIR" --suffix "$suffix"
}

if [[ "$VERIFY_TEXT" == 1 ]]; then
  # Checks that the editor preview draws text annotations like the exported image.
  run_harness en --verify-text "$WORK_DIR/verify-text"
elif [[ "$ALL_LANGUAGES" == 1 ]]; then
  # Renders every localization into build/ for a visual check (not committed).
  for LPROJ in Resources/*.lproj; do
    lang="$(basename "$LPROJ" .lproj)"
    echo "Rendering ($lang)..."
    run_harness "$lang" --out "$WORK_DIR/languages" --suffix ".$lang"
  done
else
  render en ""
  render de ".de"
fi

# The harness does not write preferences; remove its domain anyway in case AppKit did.
defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "Done: $OUT_DIR"
