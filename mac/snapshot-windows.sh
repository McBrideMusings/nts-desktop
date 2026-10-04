#!/usr/bin/env bash
# Photograph the real windows, chrome and all.
#
# `admin snapshot` renders views off screen with ImageRenderer, which is fast and
# needs no running app — but it can only photograph what is inside a SwiftUI
# view. The Settings window's title bar, its toolbar tabs, and the way it resizes
# between panes are AppKit's, and those are exactly the parts that took several
# attempts to get right. Nothing off screen can show them.
#
# So this drives the installed app through drive.sh (`admin drive`) and captures
# each real window by id. It needs `admin deploy` first (only the .app carries the
# dictionary). Every command it sends shows windows without activating the app,
# so nothing takes focus. On exit it puts back the source (an episode restarts
# from its beginning), whether it was playing, the pane, and whether each window
# was showing; it leaves the app running.
set -euo pipefail

APP="NTS Radio"
MAC="$(cd "$(dirname "$0")" && pwd)"
OUT="$(dirname "$MAC")/tmp/claude/design/window-shots"
mkdir -p "$OUT"

if [[ ! -d "/Applications/$APP.app" ]]; then
  echo "No /Applications/$APP.app — run 'admin deploy' first." >&2
  exit 1
fi

drive() { "$MAC/drive.sh" "$@" >/dev/null; }

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

"$MAC/drive.sh" launch
before="$("$MAC/drive.sh" state)"

# Put back what the run changed, on success or failure, so a capture that fails
# halfway does not leave channel 1 playing and both windows up. Each step runs
# even if the one before it fails.
restore() {
  set +e
  drive pane "$(jq -r .pane <<<"$before")"
  local source
  source="$(jq -r .source <<<"$before")"
  if [[ $source == idle ]]; then
    drive stop
  else
    drive tune "$source"
    [[ $(jq -r .playing <<<"$before") == true ]] || drive pause
  fi
  [[ $(jq -r .settingsVisible <<<"$before") == true ]] || drive close-settings
  [[ $(jq -r .windowVisible <<<"$before") == true ]] || drive window close
}
trap restore EXIT

drive window open

drive pane live
RADIO="$(window_id radio)"
capture "$RADIO" "radio-live"

# The drawer refuses to open over silence — there is no tracklist for nothing —
# so tune a channel first. `tune to` starts playback; restore undoes it.
drive tune channel:1
drive pane tracks
capture "$RADIO" "radio-tracklist-drawer"

drive pane catalog
capture "$RADIO" "radio-explore"

for pane in general account; do
  drive settings "$pane"
  capture "$(window_id "$(python3 -c "print('$pane'.capitalize())")")" "settings-$pane"
done

echo "window shots in $OUT"
