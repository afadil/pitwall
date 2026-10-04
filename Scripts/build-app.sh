#!/bin/bash
# Builds "build/Agent Board.app" from the Swift package. No Xcode project needed.
#   Scripts/build-app.sh [release|debug]
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c "$CONFIG" --product AgentBoard
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="$ROOT/build/Agent Board.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/AgentBoard" "$APP/Contents/MacOS/AgentBoard"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature so macOS treats the bundle as one app (no developer account needed).
codesign --force --sign - --timestamp=none "$APP" >/dev/null

echo "$APP"
