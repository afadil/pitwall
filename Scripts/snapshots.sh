#!/bin/bash
# Launches the built app in snapshot mode and captures each of its windows.
#   Scripts/snapshots.sh <output-dir> [--demo] [--appearance dark|light] [--prefix name] [--select <PR number>] [--group lane|tag|repository] [--tag <name>]
# Only the app's own windows are captured (by window id, or by the window's exact
# frame while the app is frontmost), over a synthetic backdrop the app draws itself. Needs Screen Recording permission for
# the terminal running this script; without it the app renders views in-process.
set -euo pipefail

OUT="$1"; shift
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/Agent Board.app/Contents/MacOS/AgentBoard"
[ -x "$BIN" ] || { echo "Build first: Scripts/build-app.sh" >&2; exit 1; }

ARGS=(); PREFIX="agentboard"
while [ $# -gt 0 ]; do
  case "$1" in
    --demo) ARGS+=(--demo) ;;
    --appearance) ARGS+=(--appearance "$2"); shift ;;
    --prefix) PREFIX="$2"; shift ;;
    --select) ARGS+=(--snapshot-select "$2"); shift ;;
    --group) ARGS+=(--snapshot-group "$2"); shift ;;
    --tag) ARGS+=(--snapshot-tag "$2"); shift ;;
  esac
  shift
done

mkdir -p "$OUT"
"$BIN" "${ARGS[@]}" --snapshot-dir "$OUT" --snapshot-prefix "$PREFIX" &
PID=$!
DEADLINE=$((SECONDS + 120))
while kill -0 "$PID" 2>/dev/null; do
  for request in "$OUT"/*.request; do
    [ -e "$request" ] || continue
    name="$(basename "$request" .request)"
    read -r id x y w h < "$request" || true  # no trailing newline
    # Window capture first; if the system refuses it, capture exactly the window's
    # frame (the app is frontmost, over its own backdrop).
    screencapture -x -o -l "$id" "$OUT/$name.png" 2>/dev/null \
      || screencapture -x -R "$x,$y,$w,$h" "$OUT/$name.png" \
      || echo "capture failed: $name" >&2
    rm -f "$request"
  done
  if [ $SECONDS -gt $DEADLINE ]; then kill "$PID"; echo "timed out" >&2; exit 1; fi
  sleep 0.1
done
wait "$PID" || true
ls "$OUT"/"$PREFIX"-*.png
