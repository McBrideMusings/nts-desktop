#!/usr/bin/env bash
# NTS Radio dev runner.
#   Builds the app, launches it, then watches the keyboard:
#     R  → rebuild & relaunch (a Swift app can't hot-reload, so this is the reload)
#     Q  → quit (Ctrl-C works too)
# The app itself also exits when this runner dies (its parent-death watch), so
# closing the terminal never orphans a stray dev instance.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

BIN=".build/debug/NTSRadio"
app_pid=""

stop_app() {
  [[ -n "$app_pid" ]] || return 0
  kill "$app_pid" 2>/dev/null
  wait "$app_pid" 2>/dev/null
  app_pid=""
}

start_app() {
  "$BIN" &
  app_pid=$!
}

build() {
  echo "▶ building…"
  swift build || return 1
  # Stable-sign the binary so the macOS Keychain grant survives rebuilds
  # (ad-hoc signing re-prompts every build — see codesign-local.sh).
  ./codesign-local.sh "$BIN"
}

banner() { echo "✓ running (pid $app_pid) — press R to reload, Q to quit"; }

reload() {
  echo "↻ reloading…"
  if build; then
    stop_app
    start_app
    banner
  else
    echo "✗ build failed — keeping the current instance running"
  fi
}

quit() { stop_app; echo; exit 0; }
trap quit INT TERM HUP

if ! build; then echo "✗ initial build failed"; exit 1; fi
start_app
banner

# Interactive key loop when attached to a terminal; otherwise just run the app
# (so `admin dev` from a non-TTY context still works as a plain launcher).
if [[ -t 0 ]]; then
  while IFS= read -rsn1 key; do
    case "$key" in
      r|R) reload ;;
      q|Q) quit ;;
    esac
  done
  quit   # stdin closed (e.g. Ctrl-D) — tear the app down too, don't orphan it
else
  wait "$app_pid"
fi
