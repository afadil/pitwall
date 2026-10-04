#!/bin/bash
# Regenerates Resources/AppIcon.icns from the SwiftUI artwork in IconArt.swift.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build --product AgentBoard
BIN="$(swift build --show-bin-path)/AgentBoard"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
"$BIN" --render-icon "$WORK"
SET="$WORK/AppIcon.iconset"
mkdir -p "$SET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$WORK/icon_1024.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$WORK/icon_1024.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$ROOT/Resources/AppIcon.icns"
cp "$WORK/icon_1024.png" "$ROOT/design/app-icon.png"
echo "Resources/AppIcon.icns"
