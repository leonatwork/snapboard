#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$PROJECT_DIR/build/Snapboard.app"

if [ ! -d "$APP_PATH" ]; then
    echo "📦 Baue Snapboard zuerst..."
    "$PROJECT_DIR/scripts/build_app.sh"
fi

echo "🚀 Installiere Snapboard nach /Applications/..."
# Beende ggf. alte Instanzen (Screenie / Snapboard)
pkill -x "Screenie" 2>/dev/null || true
pkill -x "Snapboard" 2>/dev/null || true
rm -rf "/Applications/Screenie.app"

rm -rf "/Applications/Snapboard.app"
cp -R "$APP_PATH" "/Applications/Snapboard.app"

echo "✨ Snapboard wurde erfolgreich in /Applications installiert!"
echo "🎉 Starte Snapboard..."
open "/Applications/Snapboard.app"
