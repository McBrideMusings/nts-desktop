#!/usr/bin/env bash
# The real-world half of docs/verification/unattended.md: put the installed app
# through an actual sleep, an actual Wi-Fi drop, or hours of playing, and read
# `rendering` back through `get state` until it comes back or the bound passes.
#
#   unattended.sh sleep          sleep the Mac now; once something wakes it, time
#                                how long until audio comes out again
#   unattended.sh wifi [secs]    turn Wi-Fi off for secs (default 30), back on, and
#                                time how long until audio comes out again
#   unattended.sh soak [hours]   sample state every 10s for hours (default 4) and
#                                report every stretch of silence while play is down
#
# Each tunes channel:1 first unless a channel or mixtape is already rendering,
# and stops again at the end if it started idle. It prints the recovery record
# and the app.log recovery lines from its own run, and exits 1 when rendering
# did not come back within BOUND seconds (or, for soak, when any silence ran
# longer than BOUND).
#
# None of these belongs in `admin verify`: they sleep the Mac or cut its network,
# so a person starts them on purpose.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
DRIVE="$HERE/../drive.sh"
LOG="$HOME/Library/Logs/NTS Radio/app.log"
BOUND=30

state() { "$DRIVE" state; }
say() { printf '%s  %s\n' "$(date -u +%H:%M:%SZ)" "$*"; }

started_idle=false
# app.log stamps are local time with an offset, so this is too; the two
# compare as strings while the offset holds.
began=$(date +%Y-%m-%dT%H:%M:%S)

setup() {
  local s
  s=$(state)
  if [[ $(jq -r .source <<<"$s") == idle ]]; then started_idle=true; fi
  if ! jq -e '.rendering and .recovery.endless' <<<"$s" >/dev/null; then
    say "tuning channel:1"
    "$DRIVE" tune channel:1 --wait >/dev/null
  fi
  state | jq -e .rendering >/dev/null || { say "FAIL: nothing rendering before the test"; exit 1; }
  say "rendering $(state | jq -r .source)"
}

finish() {
  local verdict=$1
  say "recovery record: $(state | jq -c .recovery)"
  if [[ -f $LOG ]]; then
    say "app.log since $began:"
    awk -v t="$began" '$1 >= t' "$LOG" | grep -E 'recover|wake|network path|item failed|stream ended' || true
  fi
  if $started_idle; then "$DRIVE" stop >/dev/null; fi
  say "$verdict"
  [[ $verdict == PASS* ]]
}

# Poll once a second until rendering, for at most BOUND seconds from $1 (epoch).
until_rendering() {
  local from=$1 now
  while :; do
    now=$(date +%s)
    if state | jq -e .rendering >/dev/null; then
      echo $((now - from))
      return 0
    fi
    if (( now - from >= BOUND )); then echo $((now - from)); return 1; fi
    sleep 1
  done
}

case ${1:-} in
  sleep)
    setup
    say "sleeping the Mac — wake it to continue"
    pmset sleepnow >/dev/null
    # The process freezes through sleep, so a jump in the wall clock between
    # two one-second ticks marks the wake.
    last=$(date +%s)
    while :; do
      sleep 1
      now=$(date +%s)
      if (( now - last > 5 )); then break; fi
      last=$now
    done
    woke=$(date +%s)
    say "woke after $((woke - last))s asleep"
    if took=$(until_rendering "$woke"); then
      finish "PASS: rendering ${took}s after wake (bound ${BOUND}s)"
    else
      finish "FAIL: not rendering ${took}s after wake (bound ${BOUND}s)"
    fi
    ;;
  wifi)
    secs=${2:-30}
    dev=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}')
    [[ -n $dev ]] || { say "no Wi-Fi device"; exit 2; }
    setup
    # Whatever ends the run — Ctrl-C, a failed read — Wi-Fi comes back on.
    trap 'networksetup -setairportpower "$dev" on' EXIT
    say "Wi-Fi ($dev) off for ${secs}s"
    networksetup -setairportpower "$dev" off
    sleep "$secs"
    say "silent while off: $(state | jq -c '{playing, rendering, network: .recovery.network}' || echo unreadable)"
    networksetup -setairportpower "$dev" on
    back=$(date +%s)
    say "Wi-Fi on"
    if took=$(until_rendering "$back"); then
      finish "PASS: rendering ${took}s after Wi-Fi came back (bound ${BOUND}s)"
    else
      finish "FAIL: not rendering ${took}s after Wi-Fi came back (bound ${BOUND}s)"
    fi
    ;;
  soak)
    hours=${2:-4}
    setup
    end=$(( $(date +%s) + $(awk -v h="$hours" 'BEGIN { printf "%d", h * 3600 }') ))
    silent_since=""
    longest=0
    stretches=0
    say "soaking for ${hours}h"
    while (( $(date +%s) < end )); do
      # One unanswered read is not a verdict on four hours.
      if ! s=$(state); then say "state unreadable, retrying"; sleep 10; continue; fi
      now=$(date +%s)
      if ! jq -e .playing <<<"$s" >/dev/null; then
        finish "FAIL: play was released at $(date -u +%H:%M:%SZ) — someone paused, so the soak proves nothing past here"
        exit 1
      fi
      if jq -e .rendering <<<"$s" >/dev/null; then
        if [[ -n $silent_since ]]; then
          gap=$((now - silent_since))
          say "silence ended after ${gap}s"
          (( gap > longest )) && longest=$gap
          silent_since=""
        fi
      elif [[ -z $silent_since ]]; then
        silent_since=$now
        stretches=$((stretches + 1))
        say "silent: $(jq -c '{source, recovery}' <<<"$s")"
      fi
      sleep 10
    done
    if [[ -n $silent_since ]]; then
      gap=$(( $(date +%s) - silent_since ))
      (( gap > longest )) && longest=$gap
    fi
    if (( longest <= BOUND )); then
      finish "PASS: ${stretches} silent stretch(es), longest ${longest}s (bound ${BOUND}s)"
    else
      finish "FAIL: ${stretches} silent stretch(es), longest ${longest}s (bound ${BOUND}s)"
    fi
    ;;
  *)
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
