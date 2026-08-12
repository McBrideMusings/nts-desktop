#!/usr/bin/env bash
# Photograph the real windows, chrome and all.
#
# `admin snapshot` renders views off screen with ImageRenderer, which is fast and
# needs no running app — but it can only photograph what is inside a SwiftUI
# view. The Settings window's title bar, its toolbar tabs, and the way it resizes
# between panes are AppKit's, and those are exactly the parts that took several
# attempts to get right. Nothing off screen can show them.
#
# So this drives the installed app through its scripting dictionary and captures
# each real window by id. It needs `admin deploy` first (only the .app carries the
# dictionary), it brings the app to the front, and it leaves it running.
set -euo pipefail

APP="NTS Radio"
OUT="$(cd "$(dirname "$0")/.." && pwd)/tmp/claude/design/window-shots"
mkdir -p "$OUT"

if [[ ! -d "/Applications/$APP.app" ]]; then
  echo "No /Applications/$APP.app — run 'admin deploy' first." >&2
  exit 1
fi

tell() { osascript -e "tell application \"$APP\" to $1" >/dev/null; }

# The radio window has no title; the Settings window's title is its pane's name.
# Ask for a window by title, or for the untitled one.
window_id() {
  python3 - "$1" <<'PY'
import sys, Quartz
want = sys.argv[1]
for w in Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionAll, Quartz.kCGNullWindowID):
    if "NTS" not in str(w.get("kCGWindowOwnerName", "")):
        continue
    name = w.get("kCGWindowName") or ""
    if (want == "radio" and not name) or (want and name == want):
        print(w.get("kCGWindowNumber"))
        break
PY
}

# -T 1 lets a pane switch or an overlay finish before the shutter; -o drops the
# window shadow so the PNG is the window itself.
capture() {
  local id="$1" name="$2"
  [[ -n "$id" ]] || { echo "no window for $name" >&2; return; }
  screencapture -x -o -T 1 -l "$id" "$OUT/$name.png"
  echo "wrote $name.png"
}

open -a "/Applications/$APP.app"
sleep 2
tell "open window"

tell 'show pane "live"'
RADIO="$(window_id radio)"
capture "$RADIO" "radio-live"

# The drawer refuses to open over silence — there is no tracklist for nothing —
# so tune a channel first. `tune to` does not start playback on its own.
tell 'tune to "channel:1"'
tell 'show pane "tracks"'
capture "$RADIO" "radio-tracklist-drawer"

tell 'show pane "catalog"'
capture "$RADIO" "radio-explore"

tell 'show pane "live"'

for pane in general account; do
  tell "open settings \"$pane\""
  capture "$(window_id "$(python3 -c "print('$pane'.capitalize())")")" "settings-$pane"
done

echo "window shots in $OUT"
