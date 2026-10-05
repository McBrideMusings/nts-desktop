# Verification: unattended playback

The root job in [`docs/jobs.md`](../jobs.md) is radio playing through a long stretch at the desk without being managed, and every release after 0.1.0 is gated on nothing being known-broken in that path. These rows are the check on it: a channel or mixtape that falls silent while play is down must come back on its own.

**What recovery does.** `PlayerEngine.recoverIfStalled` reloads the current stream at the live head when play is down, nothing is rendering, and the source is a channel or a mixtape. Four things set it off: the Mac waking, the network path coming back after a loss, the item failing (or an endless stream reaching an end), and 15 seconds of silence with none of those. A reload that does not render is retried after 5, 10, 20, then every 30 seconds until it does, or until the listener pauses or tunes something else. Every attempt writes `recover attempt=<n> reason=<why>` to `app.log`; a streak that ends writes `recovered after <n> attempt(s)`. `admin state`'s `recovery` object carries the same record. An episode is never reloaded, because a reload would restart it from 0:00.

**The bound is 30 seconds** from the event (a wake, Wi-Fi coming back) to `rendering: true`.

**Two halves.** UNA-01 to UNA-07 provoke each event with `admin drive simulate`. They run under `admin verify` like any other scripted row and never touch the machine itself. UNA-10 to UNA-12 are the real thing, run by `admin unattended`. They sleep the Mac, turn Wi-Fi off or hold the app for hours, so a person starts them on purpose and they are never part of `admin verify`. Each one prints the recovery record and its own `app.log` recovery lines, and exits 1 past the bound. **A failure becomes a ticket under the root job.**

## Recovery, provoked

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| UNA-01 | P1 | script | A stream whose item fails is reloaded at once and renders again. | Idle. | 1. `tune to "channel:1"` until rendering.<br>2. `simulate "failure"`.<br>3. Poll `rendering` for 20s. | `rendering` false after step 2, true within 20s. `recovery.reason` starts `item failed`, `recoveries` is one higher, `attempts` back to 0. | pass (scripted 2026-10-04) |
| UNA-02 | P1 | script | A wake reloads a stalled stream without waiting out the stall grace. | Idle. | 1. Tune a mixtape until rendering.<br>2. `simulate "stall"`.<br>3. `simulate "wake"`.<br>4. Poll `rendering` for 10s. | Step 3 answers `attempts: 1, reason: "wake"`; rendering inside 10s, which is before the 15s grace could have fired. | pass (scripted 2026-10-04; 10s is inside the 15s stall grace, so the wake did it) |
| UNA-03 | P1 | script | The network coming back reloads a stalled stream. | Idle. | 1. Tune NTS 2 until rendering.<br>2. `simulate "stall"`.<br>3. `simulate "network"`.<br>4. Poll `rendering` for 10s. | `reason: "network"`; rendering inside 10s. | pass (scripted 2026-10-04; 10s is inside the 15s stall grace, so the network return did it) |
| UNA-04 | P1 | script | Silence with no event behind it is reloaded after the 15s grace. | Idle. | 1. Tune NTS 1 until rendering.<br>2. `simulate "stall"`.<br>3. Poll `rendering` for 30s. | Rendering again after at least 14s; `reason: "stalled"`. | pass (scripted 2026-10-04) |
| UNA-05 | P2 | script | An episode is never reloaded. | Idle. | 1. Tune an episode until rendering; wait 2s.<br>2. `simulate "stall"`.<br>3. `simulate "wake"`. | `recovery.endless` false, `attempts` 0, still silent, `position` past 1s — not reset to 0. | pass (scripted 2026-10-04) |
| UNA-06 | P2 | script | A paused stream is left alone. | Idle. | 1. Tune NTS 1 until rendering.<br>2. `pause`.<br>3. `simulate "wake"`, then `simulate "failure"`; wait 2s. | `attempts` stays 0 and nothing renders. | pass (scripted 2026-10-04) |
| UNA-07 | P3 | script | `simulate` refuses an event it does not know. | — | 1. `simulate "nonsense"`. | Error `-1703`. | pass (scripted 2026-10-04) |

## Recovery, for real

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| UNA-10 | P1 | sleep, script | A channel playing when the Mac sleeps is playing again within 30s of it waking. | Nothing you mind the Mac sleeping through. | 1. `admin unattended sleep`.<br>2. Wake the Mac after a minute or more. | `PASS: rendering <n>s after wake`; the log shows `wake`, then `recover attempt=1 reason=wake` (and `reason=network` if Wi-Fi rejoined later), then `recovered after`. | — |
| UNA-11 | P1 | offline, script | A Wi-Fi drop longer than the buffer recovers within 30s of Wi-Fi coming back. | On Wi-Fi, not Ethernet. | 1. `admin unattended wifi` (30s off). | Silent while off; `PASS: rendering <n>s after Wi-Fi came back`; the log shows `network path unsatisfied`, retries backing off 5, 10, 20s, then `reason=network` and `recovered after`. | — |
| UNA-12 | P2 | script | Four hours of a channel playing hold no silence longer than 30s. | Nothing else touching playback for four hours. | 1. `admin unattended soak 4`. | `PASS: <n> silent stretch(es), longest <n>s`. A pause by hand ends the soak as a fail, since it proves nothing past that point. | — |
