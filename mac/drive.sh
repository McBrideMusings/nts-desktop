#!/usr/bin/env bash
# Drive the installed app through its scripting dictionary (Resources/NTSRadio.sdef)
# without hand-quoting AppleScript. Every verb prints the state JSON the command
# answers with, pretty-printed; a setter, which answers nothing, prints `get state`.
#
#   drive.sh state                      get state
#   drive.sh tune mixtape:slow-focus    tune to "mixtape:slow-focus"
#   drive.sh skip -1                    skip by -1
#   drive.sh tune channel:1 --wait      tune to "channel:1" with until rendering true
#   drive.sh set volume-curve linear    set its volume curve to "linear"
#
# `quit` and `launch` are the two ends of `admin deploy`: quit asks the app to
# quit (so applicationWillTerminate flushes its caches and logs, which a SIGTERM
# skips) and waits for the process to go; launch opens the bundle in the
# background, unless it is already running, and returns once `get state` answers.
set -euo pipefail

APP="NTS Radio"
BUNDLE="/Applications/$APP.app"

usage() {
  [[ ${1:-2} -eq 0 ]] || exec >&2
  cat <<'EOF'
usage: admin drive <verb> [args]

  state                          the whole state blob
  get <property>                 one property, e.g. get source-name
  set <property> <value>         e.g. set volume 30, set track-lead artist
  tune <source> [--wait]         mixtape:<alias> | channel:<n> | episode:<show>/<episode> | idle
  play | pause
  stop                           untune, back to idle
  skip [n] [--wait]              default 1; negative goes back
                                 --wait answers once audio is coming out (10s cap)
  seek <seconds>
  window open|close
  pane live|catalog|tracks|none
  catalog [schedule|saved] [channel]
  search <term>                  open catalog searching for <term>
  close-catalog
  filter [mood <id>] [genre <id>]... [music-only] [focused]
  more                           explore more
  save <alias | episode:<show>/<episode>>
  genre <name>                   browse genre
  show <alias>                   open show
  settings [general|account]     open settings, without taking focus
  close-settings
  simulate stall|failure|wake|network
                                 break the stream, or deliver a wake or a
                                 network return, to watch recovery mend it
  updates                        check for updates
  window-id radio|<title>        the window number screencapture -l takes
  quit | launch                  graceful quit / open and wait for state
EOF
  exit "${1:-2}"
}

# An AppleScript string literal.
q() {
  local s=${1//\\/\\\\}
  printf '"%s"' "${s//\"/\\\"}"
}

# A setter's value: bare for the sdef's integer, real and boolean properties,
# quoted for its text ones.
value() {
  case $1 in
    volume|volume-steepness|muted|auto-checks-for-updates|resume-last-source) printf '%s' "$2" ;;
    *) q "$2" ;;
  esac
}

# Fail with usage unless every argument is a number.
number() {
  local n
  for n in "$@"; do [[ $n =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || usage; done
}

tell() { osascript -e "tell application \"$APP\" to $1"; }

running() { pgrep -f "^$BUNDLE/Contents/MacOS/" >/dev/null; }

pretty() { jq .; }

# Run a command that answers with the state JSON.
act() { tell "$1" | pretty; }

[[ $# -ge 1 ]] || usage 0
verb=$1
shift

# `--wait` on tune and skip: hold the reply until the new source is audible.
wait=""
if [[ $verb == tune || $verb == skip ]] && [[ $# -ge 1 && ${!#} == --wait ]]; then
  wait=" until rendering true"
  set -- "${@:1:$#-1}"
fi

case $verb in
  state)    act "get state" ;;
  get)      [[ $# -eq 1 ]] || usage; tell "get its ${1//-/ }" ;;
  set)      [[ $# -eq 2 ]] || usage; tell "set its ${1//-/ } to $(value "$1" "$2")" >/dev/null; act "get state" ;;
  tune)     [[ $# -eq 1 ]] || usage; act "tune to $(q "$1")$wait" ;;
  play)     [[ $# -eq 0 ]] || usage; act "play" ;;
  pause)    [[ $# -eq 0 ]] || usage; act "pause" ;;
  stop)     [[ $# -eq 0 ]] || usage; act "stop" ;;
  skip)     [[ $# -le 1 ]] || usage; number "${1:-1}"; act "skip by ${1:-1}$wait" ;;
  seek)     [[ $# -eq 1 ]] || usage; number "$1"; act "seek to $1" ;;
  window)
    case ${1:-} in
      open|close) act "$1 window" ;;
      *) usage ;;
    esac ;;
  pane)     [[ $# -eq 1 ]] || usage; act "show pane $(q "$1")" ;;
  catalog)
    [[ $# -le 2 ]] || usage
    [[ -z ${2:-} ]] || number "$2"
    cmd="open catalog"
    [[ -n ${1:-} ]] && cmd+=" showing $(q "$1")"
    [[ -n ${2:-} ]] && cmd+=" channel $2"
    act "$cmd" ;;
  search)   [[ $# -eq 1 ]] || usage; act "open catalog searching for $(q "$1")" ;;
  close-catalog) act "close catalog" ;;
  filter)
    cmd="filter explore"
    genres=()
    while [[ $# -gt 0 ]]; do
      case $1 in
        mood)       [[ $# -ge 2 ]] || usage; cmd+=" mood $(q "$2")"; shift 2 ;;
        genre)      [[ $# -ge 2 ]] || usage; genres+=("$(q "$2")"); shift 2 ;;
        music-only) cmd+=" music only true"; shift ;;
        focused)    cmd+=" focused true"; shift ;;
        *) usage ;;
      esac
    done
    if [[ ${#genres[@]} -gt 0 ]]; then
      joined=$(IFS=,; echo "${genres[*]}")
      cmd+=" genres {$joined}"
    fi
    act "$cmd" ;;
  more)     act "explore more" ;;
  save)     [[ $# -eq 1 ]] || usage; act "save $(q "$1")" ;;
  genre)    [[ $# -eq 1 ]] || usage; act "browse genre $(q "$1")" ;;
  show)     [[ $# -eq 1 ]] || usage; act "open show $(q "$1")" ;;
  settings)
    if [[ $# -eq 1 ]]; then act "open settings $(q "$1")"; else act "open settings"; fi ;;
  close-settings) act "close settings" ;;
  simulate) [[ $# -eq 1 ]] || usage; act "simulate $(q "$1")" ;;
  updates)  act "check for updates" ;;
  window-id)
    # The radio window has no title; the Settings window's title is its pane's name.
    [[ $# -eq 1 ]] || usage
    python3 - "$1" <<'PY'
import sys, Quartz
want = sys.argv[1]
for w in Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionAll, Quartz.kCGNullWindowID):
    if "NTS" not in str(w.get("kCGWindowOwnerName", "")):
        continue
    name = w.get("kCGWindowName") or ""
    if (want == "radio" and not name) or (want and name == want):
        print(w.get("kCGWindowNumber"))
        sys.exit(0)
print(f"no window {want!r}", file=sys.stderr)
sys.exit(1)
PY
    ;;
  quit)
    if ! running; then
      echo "$APP is not running"
      exit 0
    fi
    # Asked only if still running, so a quit that raced us does not relaunch it;
    # an error (the app can drop the connection while it exits) is not the
    # verdict — the poll below is.
    osascript -e "if application \"$APP\" is running then tell application \"$APP\" to quit" || true
    for _ in $(seq 100); do
      running || { echo "$APP quit"; exit 0; }
      sleep 0.1
    done
    echo "$APP did not quit within 10s" >&2
    exit 1 ;;
  launch)
    # Opening a running app sends it a reopen event, and the app answers that
    # the way it answers a Dock click: it shows the window and activates.
    running || open -g "$BUNDLE"
    for _ in $(seq 60); do
      if out=$(osascript -e "with timeout of 5 seconds" -e "tell application \"$APP\" to get state" -e "end timeout" 2>/dev/null) && jq -e . >/dev/null <<<"$out"; then
        echo "$APP is answering"
        exit 0
      fi
      sleep 0.5
    done
    echo "$APP did not answer get state within 30s" >&2
    exit 1 ;;
  *) usage ;;
esac
