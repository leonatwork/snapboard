#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

echo "📦 Erstelle Snapboard-macOS.zip..."
./scripts/build_app.sh

cd "$PROJECT_DIR/build"
rm -f Snapboard-macOS.zip
ditto -c -k --sequesterRsrc --keepParent Snapboard.app Snapboard-macOS.zip
mv Snapboard-macOS.zip "$PROJECT_DIR/"

echo "✅ Fertig: $PROJECT_DIR/Snapboard-macOS.zip"
