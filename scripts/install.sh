#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$PROJECT_DIR/build/Screenie.app"

if [ ! -d "$APP_PATH" ]; then
    echo "📦 Baue Screenie zuerst..."
    "$PROJECT_DIR/scripts/build_app.sh"
fi

echo "🚀 Installiere Screenie nach /Applications/..."
# Beende ggf. laufende Instanz
pkill -x "Screenie" 2>/dev/null || true

rm -rf "/Applications/Screenie.app"
cp -R "$APP_PATH" "/Applications/Screenie.app"

echo "✨ Screenie wurde erfolgreich in /Applications installiert!"
echo "🎉 Starte Screenie..."
open "/Applications/Screenie.app"
