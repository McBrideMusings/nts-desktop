# Automating NTS Radio

NTS Radio can be driven entirely without a mouse. It ships an AppleScript dictionary — eighteen commands and eleven properties — and **every command answers with the same JSON description of the whole app**, so one call both acts and reports.

This is a supported surface, not a debug hatch. Build a Keyboard Maestro macro, a Stream Deck button, a login script that tunes NTS 1 in the morning.

```
osascript -e 'tell application "NTS Radio" to tune to "mixtape:slow-focus"'
```

## Reading the dictionary

**Script Editor → File → Open Dictionary → NTS Radio.** Every command and property is listed with a description written to be read.

Two things to know before you start:

- **Shortcuts cannot see this app.** It ships no App Intents, and macOS 15's Shortcuts does not read `.sdef` terminology. From Shortcuts, use the generic **Run AppleScript** action. Tracked as [#93](https://github.com/McBrideMusings/nts-desktop/issues/93).
- **Addressing the app launches it.** There is no way to query it without starting it.

## Naming a source

Four forms. The same strings come back in the state blob, so you can read one and pass it straight to `tune to`.

```
channel:1
channel:2
mixtape:slow-focus
episode:anz/anz-25th-june-2026
idle
```

Nothing tuned reports as `idle`, and `tune to "idle"` is the same as `stop`.

## The state blob

`state` returns about 2.7KB of JSON describing everything the app knows about itself. So does every command.

```bash
osascript -e 'tell application "NTS Radio" to get state' | jq .
```

Grouped by what they answer:

- **Playback** — `source`, `sourceName`, `playing`, `rendering`, `position`, `duration`, `seekable`, `bufferSeconds`, `volume`, `volumeSlider`, `volumeCurve`, `volumeSteepness`, `muted`, `episodeStream`, `episodeLoading`, `episodeError`, `episodeURL`
- **Tracklist** — `trackLead` (`"title"` or `"artist"`: which line leads a row; `currentTrack` and `pendingTrack` stay "artist — title" either way), `currentTrack`, `trackCount`, `pendingTrack`, `pendingSeconds`
- **Window** — `pane`, `tracksOpen`, `windowVisible`, `windowContentAttached`, `catalogOpen`, `catalogTab`, `catalogQuery`, `catalogDetail`, `detailTags`, `detailError`, `settingsVisible`, `settingsPane`, `knobAngle`
- **Catalog** — `catalogRows`, `catalogFirstRows`, `savedCount`, `savedKeys` (every saved item's id in the Saved tab's order — `show:<alias>`, `mixtape:<alias>`, `episode:<show>/<episode>`; a `save` puts its item first), `mixtapeCount`, `genreCount`, `moodCount`, `channels`, `onAir`, `nextUp`, `scheduleChannel`, `scheduleDays`, `scheduleEnded` (slots in the timeline whose end has passed — 0 outside the second after a changeover), `showIndex`
- **Explore** — `exploreMood`, `exploreGenres`, `exploreMusicOnly`, `exploreFocused`, `exploreLoaded`, `exploreTotal`
- **App** — `signedIn`, `syncedWithAccount`, `outage`, `running`, `autoChecksForUpdates`, `canCheckForUpdates`, `resumeLastSource`, `lastSource` (the `mixtape:<alias>` or `channel:<n>` launch would tune; `""` once `stop` or an episode leaves nothing to resume)
- **Logs** — `logDirectory`, `recordedSources`
- **Recovery** — `recovery`: `endless` (a channel or mixtape is loaded, the only kind that is ever reloaded), `attempts` (reloads since audio last came out and held for 60 seconds; 0 when nothing is being recovered), `reason` and `lastAttempt` (what set off the latest reload, and when), `recoveries` and `lastRecovered` (streaks since launch that ended with audio back for 60 seconds), `network` (`satisfied`, `unsatisfied` or `unknown`). Times are ISO 8601 in UTC, `""` when it has not happened yet.

**`playing` and `rendering` are different.** The first means playback was asked for; the second means audio is actually coming out. Wait on `rendering` if you want sound, not intent.

**`pendingTrack` and `pendingSeconds`** expose a track NTS has announced that the app is holding back until the audio it names reaches the speakers. Without these two fields that delay would be unobservable from outside — its whole effect is that nothing happens for a few seconds.

## The logs

`logDirectory` in the state blob is the folder the app writes its two log files to, `~/Library/Logs/NTS Radio`. `recordedSources` lists what the recorder is subscribed to: both live channels and every mixtape while signed in, empty while signed out.

```bash
dir=$(osascript -e 'tell application "NTS Radio" to get state' | jq -r .logDirectory)
tail -f "$dir/tracks.log"
```

- **`tracks.log`** has one tab-separated line per change to a document in NTS's `live_tracks` collection, for every source at once, whichever one is playing: receive time (local, with UTC offset), source (`channel-1`, `channel-2`, `mixtape:<alias>`), kind (`added`, `modified`, `removed` for a document that left the newest 12, `deleted`; `/snapshot` marks the opening 12 Firestore sends when the stream connects), document id, `start`, `title` and `artists` (JSON, so the `artist_names` array shows exactly as NTS stored it), Firestore's `created` and `updated` times, and the names of any other fields. Lines with `stream` in the source column record the connection opening, reconnecting or failing. The token is never written.
- **`app.log`** has everything the app sends to the unified log (categories `api`, `auth`, `player`, `app`, `tracks`), written as each line is logged, as time, category, level and message. Values the code does not mark public read `<private>`, the same as in `log show`.

Each file moves to `<name>.1` at 5MB, so at most about 10MB of each is kept.

## The commands

### Playback

```bash
osascript -e 'tell application "NTS Radio" to tune to "channel:1"'
osascript -e 'tell application "NTS Radio" to play'
osascript -e 'tell application "NTS Radio" to pause'
osascript -e 'tell application "NTS Radio" to stop'
osascript -e 'tell application "NTS Radio" to skip by 1'
osascript -e 'tell application "NTS Radio" to seek to 1800'
```

`tune to` is the same code path a click takes; `skip by` is the one the media keys take, so a script and a hand cannot produce different results.

**`stop` puts the app back where it launched.** Nothing tuned (`source` is `idle`), no stream open, `playing` and `rendering` false, the tracklist empty and its drawer down, `knobAngle` 0. `pause` keeps the source loaded; use `stop` to leave things as you found them.

**`skip by` moves to the neighbouring *source*, not the next track.** Mixtapes walk the dial and the two channels toggle; counts past either end wrap around, so with 16 mixtapes `skip by 17` is the same as `skip by 1`, and on a channel any even count lands where it started. An episode and idle have no neighbours, so `skip` fails there instead of answering with an unchanged state:

```
skip by 1   on an episode → -1708  An episode is not part of a group, so there is
                                   no neighbour to skip to. Tune a mixtape or a
                                   channel first.
skip by 1   when idle     → -1708  Nothing is tuned, so there is nothing to skip
                                   from. Tune a mixtape or a channel first.
```

**`until rendering true` makes `tune to` and `skip` answer with the settled state.** Without it the reply comes back the moment the command is taken, before the new stream has started — `rendering` false, `bufferSeconds` 0, no current track yet. With it the reply waits until audio is coming out, an episode's fetch has failed (`episodeError` set), or 10 seconds have passed, whichever is first. A skip while paused stays paused and answers at once. Check `rendering` in the reply: after the 10 seconds it is still false.

```bash
osascript -e 'tell application "NTS Radio" to tune to "channel:1" until rendering true' | jq .rendering
# true
```

**`seek to` works only on an episode** — channels and mixtapes are continuous and have no position. It fails loudly rather than doing nothing:

```
seek to 1800   on a channel → -1708  What's tuned has no position to seek to — the
                                     channels and the mixtapes are continuous
                                     streams. Tune an episode first.
```

Values are clamped: `seek to -50` lands on `0`, `seek to 99999` on the last second.

**A channel or mixtape that falls silent while play is down comes back on its own.** The app reloads it at the live head when the Mac wakes, when the network comes back, when the stream fails or ends, and after 15 seconds of silence with none of those. A reload that does not start is tried again after 5, 10, 20, then every 30 seconds. One that starts and drops within 60 seconds is reloaded after 20, 25, 35, then every 45 seconds of silence. `simulate` provokes each of those events, so a script can watch the `recovery` record and `rendering` without sleeping the Mac or turning Wi-Fi off:

```bash
osascript -e 'tell application "NTS Radio" to simulate "stall"'    # audio stops, play stays down
osascript -e 'tell application "NTS Radio" to simulate "failure"'  # the stream is swapped for one that cannot connect
osascript -e 'tell application "NTS Radio" to simulate "wake"'     # what the Mac waking delivers
osascript -e 'tell application "NTS Radio" to simulate "network"'  # what the network coming back delivers
```

An episode is never reloaded, since that would start it again from 0:00. [`docs/verification/unattended.md`](verification/unattended.md) has the checks built on this, and the real sleep, Wi-Fi and soak runs.

### The window

```bash
osascript -e 'tell application "NTS Radio" to open window'
osascript -e 'tell application "NTS Radio" to close window'
osascript -e 'tell application "NTS Radio" to show pane "live"'
osascript -e 'tell application "NTS Radio" to show pane "catalog"'
osascript -e 'tell application "NTS Radio" to show pane "tracks"'
osascript -e 'tell application "NTS Radio" to show pane "none"'
```

**Nothing here takes keyboard focus.** `open window` puts the window on screen without activating the app, so a script can drive the whole thing while you keep typing in another application. There is deliberately no `activate` equivalent.

`show pane "tracks"` raises the tracklist drawer over whichever pane is up; `"none"` drops it. With nothing tuned it fails: `-1728`, "Nothing is playing, so there is no tracklist to show."

### The catalog

```bash
osascript -e 'tell application "NTS Radio" to open catalog showing "schedule"'
osascript -e 'tell application "NTS Radio" to open catalog showing "schedule" channel 2'
osascript -e 'tell application "NTS Radio" to open catalog searching for "veronica"'
osascript -e 'tell application "NTS Radio" to open show "veronica-vasicka"'
osascript -e 'tell application "NTS Radio" to browse genre "Kosmische"'
osascript -e 'tell application "NTS Radio" to filter explore mood "sedative" genres {"ambientnewage"}'
osascript -e 'tell application "NTS Radio" to explore more'
osascript -e 'tell application "NTS Radio" to save "veronica-vasicka"'
osascript -e 'tell application "NTS Radio" to close catalog'
```

**`open show` answers before the show's page has loaded.** The reply sets `catalogDetail` straight away; `detailTags` fills in once the page arrives. If the fetch fails, `detailError` carries the reason, for example "nts.live answered HTTP 404." for an alias that does not exist, and opening the show again retries. Wait for one or the other: `detailTags` non-empty or `detailError` non-empty.

**`browse genre` takes a display name; `filter explore` takes an id.** `Kosmische` versus `ambientnewage-kosmiche`. The error message for an unknown genre explains the difference.

**`save` is a toggle.** Running the same script twice saves then unsaves. There is no `unsave`; read `savedKeys` to see which way it went. Tracked as [#95](https://github.com/McBrideMusings/nts-desktop/issues/95).

**`open catalog` with no `searching for` clears the current query.** Pass `searching for ""` if you mean to clear it; omitting it clears it too, which is [#97](https://github.com/McBrideMusings/nts-desktop/issues/97).

### Settings and updates

```bash
osascript -e 'tell application "NTS Radio" to open settings'
osascript -e 'tell application "NTS Radio" to open settings "account"'
osascript -e 'tell application "NTS Radio" to close settings'
osascript -e 'tell application "NTS Radio" to check for updates'
```

**`open settings` puts the window up without activating the app**, the same as `open window`, so the window comes up in front but whatever you were typing into keeps the keyboard. `check for updates` is the one command that can take focus: Sparkle's own dialog activates the app.

## Properties

Eight are read-only: `state`, `playing`, `rendering`, `source`, `source name`, `current track`, `window visible`, `knob angle`.

Seven are writable:

```bash
osascript -e 'tell application "NTS Radio" to set its volume to 30'
osascript -e 'tell application "NTS Radio" to set its volume curve to "perceptual"'
osascript -e 'tell application "NTS Radio" to set its volume steepness to 3'
osascript -e 'tell application "NTS Radio" to set muted to true'
osascript -e 'tell application "NTS Radio" to set auto checks for updates to true'
osascript -e 'tell application "NTS Radio" to set track lead to "artist"'
osascript -e 'tell application "NTS Radio" to set resume last source to true'
```

### ⚠️ `set volume to 30` does not work

```
tell application "NTS Radio" to set volume to 30
→ -2741  Expected "given", "in", "of", expression, "with", "without",
         other parameter name, etc. but found "to".
```

AppleScript's StandardAdditions defines its own `set volume` **command** for the system output volume, and it shadows any property of that name at parse time. Two forms reach the property:

```bash
osascript -e 'tell application "NTS Radio" to set its volume to 30'
osascript -e 'tell application "NTS Radio" to set (volume) to 30'
```

`get volume` reads fine in every form, and `muted` has no such problem. Tracked as [#90](https://github.com/McBrideMusings/nts-desktop/issues/90).

### `volume` is the output level, not the knob

`volume` (0–100) is the gain the player applies. The knob in the now-playing bar sits at a *position* that the volume curve maps to that gain, `gain = position^steepness`, and `state` reports it separately as `volumeSlider`. Changing `volume curve` or `volume steepness` keeps `volume` fixed and moves `volumeSlider`:

```bash
osascript -e 'tell application "NTS Radio" to set its volume curve to "linear"'
osascript -e 'tell application "NTS Radio" to set its volume to 12'
osascript -e 'tell application "NTS Radio" to set its volume curve to "perceptual"'
osascript -e 'tell application "NTS Radio" to set its volume steepness to 3'
osascript -e 'tell application "NTS Radio" to get state' | jq '{volume, volumeSlider, volumeCurve, volumeSteepness}'
# {"volume":12,"volumeSlider":49,"volumeCurve":"perceptual","volumeSteepness":3}
```

`volume curve` takes `linear` or `perceptual` and nothing else. `volume steepness` is clamped to 2…5 and does nothing while the curve is linear.

## Errors

Errors name the valid values rather than reporting a failure:

```
open catalog showing "search"       → -1703  "search" is not a catalog list.
                                             Use explore, schedule, saved.

filter explore genres {"nonsense"}  → -1703  "nonsense" is not a genre id.
                                             `browse genre` takes the name as the
                                             card prints it, e.g. browse genre
                                             "Kosmische".

set its volume curve to "log"       → -1703  "log" is not a volume curve.
                                             Use "linear" or "perceptual".

seek to 1800   (on a channel)       → -1708  …tune an episode first.
skip by 1      (on an episode)      → -1708  …no neighbour to skip to.
show pane "tracks"   (idle)         → -1728  Nothing is playing…
seek to "half"                      → -1700  Can't make "half" into type real.
```

The last is AppleScript's, not the app's — parameter types are declared in the dictionary, so a wrongly typed argument never reaches the app.

## Worked example: wait for audio, then report

```bash
#!/bin/bash
state=$(osascript -e 'tell application "NTS Radio" to tune to "episode:anz/anz-25th-june-2026" until rendering true')

err=$(printf '%s' "$state" | jq -r .episodeError)
[ -n "$err" ] && { echo "failed: $err"; exit 1; }
[ "$(printf '%s' "$state" | jq -r .rendering)" = "true" ] || { echo "no audio after 10s"; exit 1; }

printf '%s' "$state" | jq -r '"\(.sourceName), rendering=\(.rendering)"'
```

An episode resolves through two network hops — its page, then a signed playlist — either of which can fail, so check `episodeError` and `rendering` in the reply rather than assuming success.

## What a script cannot do

- **Read a list.** `catalogFirstRows` gives three display strings with no aliases, and opening a show does not report its episodes — so a script cannot get from "find me a show" to "play an episode of it" without querying NTS's API itself. This is [#89](https://github.com/McBrideMusings/nts-desktop/issues/89), the largest gap.
- **Gesture.** No drag, hover or scroll.
- **See the menu-bar icon.** It owns no window and answers no property.
- **Set Show in Dock or Open at Login** — [#99](https://github.com/McBrideMusings/nts-desktop/issues/99).
- **Learn what a `check for updates` found** — same issue.
- **Reach the account.** Reported, never changed. This one is deliberate.

## From a checkout: `mac/drive.sh`

A clone of this repository carries `mac/drive.sh`, which maps short verbs onto the commands above, does the AppleScript quoting, and pretty-prints the state each one answers with. Run with no arguments, it lists the verbs.

```bash
mac/drive.sh state
mac/drive.sh tune mixtape:slow-focus
mac/drive.sh tune channel:1 --wait
mac/drive.sh skip -1
mac/drive.sh stop
mac/drive.sh filter mood sedative genre ambientnewage music-only
mac/drive.sh set volume-curve linear
```

`--wait` on `tune` and `skip` adds `until rendering true`. A setter answers nothing, so `set` prints `get state` after it. An error from the app prints its message verbatim and exits non-zero.

## Adding a command

Three places: the terminology in `mac/Resources/NTSRadio.sdef`, the implementation in `mac/Sources/NTSRadio/Model/Scripting.swift`, and a verb in `mac/drive.sh`. Add the field to `StateSnapshot.swift` if the command should be observable — the struct fails the build if a field is added without being populated.

Only the installed `.app` carries the dictionary. `admin dev`'s bare binary answers nothing.
