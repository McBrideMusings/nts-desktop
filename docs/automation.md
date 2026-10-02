# Automating NTS Radio

NTS Radio can be driven entirely without a mouse. It ships an AppleScript dictionary — seventeen commands and eleven properties — and **every command answers with the same JSON description of the whole app**, so one call both acts and reports.

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

Three forms. The same strings come back in the state blob, so you can read one and pass it straight to `tune to`.

```
channel:1
channel:2
mixtape:slow-focus
episode:anz/anz-25th-june-2026
```

Nothing tuned reports as `idle`.

## The state blob

`state` returns about 2.7KB of JSON describing everything the app knows about itself. So does every command.

```bash
osascript -e 'tell application "NTS Radio" to get state' | jq .
```

Grouped by what they answer:

- **Playback** — `source`, `sourceName`, `playing`, `rendering`, `position`, `duration`, `seekable`, `bufferSeconds`, `volume`, `muted`, `episodeStream`, `episodeLoading`, `episodeError`, `episodeURL`
- **Tracklist** — `trackLead` (`"title"` or `"artist"`: which line leads a row; `currentTrack` and `pendingTrack` stay "artist — title" either way), `currentTrack`, `trackCount`, `pendingTrack`, `pendingSeconds`
- **Window** — `pane`, `tracksOpen`, `windowVisible`, `catalogOpen`, `catalogTab`, `catalogQuery`, `catalogDetail`, `detailTags`, `settingsVisible`, `settingsPane`, `knobAngle`
- **Catalog** — `catalogRows`, `catalogFirstRows`, `savedCount`, `mixtapeCount`, `genreCount`, `moodCount`, `channels`, `onAir`, `nextUp`, `scheduleChannel`, `scheduleDays`, `showIndex`
- **Explore** — `exploreMood`, `exploreGenres`, `exploreMusicOnly`, `exploreFocused`, `exploreLoaded`, `exploreTotal`
- **App** — `signedIn`, `syncedWithAccount`, `outage`, `running`, `autoChecksForUpdates`, `canCheckForUpdates`

**`playing` and `rendering` are different.** The first means playback was asked for; the second means audio is actually coming out. Wait on `rendering` if you want sound, not intent.

**`pendingTrack` and `pendingSeconds`** expose a track NTS has announced that the app is holding back until the audio it names reaches the speakers. Without these two fields that delay would be unobservable from outside — its whole effect is that nothing happens for a few seconds.

## The commands

### Playback

```bash
osascript -e 'tell application "NTS Radio" to tune to "channel:1"'
osascript -e 'tell application "NTS Radio" to play'
osascript -e 'tell application "NTS Radio" to pause'
osascript -e 'tell application "NTS Radio" to skip by 1'
osascript -e 'tell application "NTS Radio" to seek to 1800'
```

`tune to` is the same code path a click takes; `skip by` is the one the media keys take, so a script and a hand cannot produce different results.

**`skip by` moves to the neighbouring *source*, not the next track.** Channels toggle between themselves; mixtapes walk the dial and wrap; an episode does not move; idle does nothing.

**`seek to` works only on an episode** — channels and mixtapes are continuous and have no position. It fails loudly rather than doing nothing:

```
seek to 1800   on a channel → -1708  What's tuned has no position to seek to — the
                                     channels and the mixtapes are continuous
                                     streams. Tune an episode first.
```

Values are clamped: `seek to -50` lands on `0`, `seek to 99999` on the last second.

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
osascript -e 'tell application "NTS Radio" to star "veronica-vasicka"'
osascript -e 'tell application "NTS Radio" to close catalog'
```

**`browse genre` takes a display name; `filter explore` takes an id.** `Kosmische` versus `ambientnewage-kosmiche`. The error message for an unknown genre explains the difference.

**`star` is a toggle.** Running the same script twice saves then unsaves. There is no `unstar`. Tracked as [#95](https://github.com/McBrideMusings/nts-desktop/issues/95).

**`open catalog` with no `searching for` clears the current query.** Pass `searching for ""` if you mean to clear it; omitting it clears it too, which is [#97](https://github.com/McBrideMusings/nts-desktop/issues/97).

### Settings and updates

```bash
osascript -e 'tell application "NTS Radio" to open settings'
osascript -e 'tell application "NTS Radio" to open settings "account"'
osascript -e 'tell application "NTS Radio" to check for updates'
```

## Properties

Eight are read-only: `state`, `playing`, `rendering`, `source`, `source name`, `current track`, `window visible`, `knob angle`.

Four are writable:

```bash
osascript -e 'tell application "NTS Radio" to set its volume to 30'
osascript -e 'tell application "NTS Radio" to set muted to true'
osascript -e 'tell application "NTS Radio" to set auto checks for updates to true'
osascript -e 'tell application "NTS Radio" to set track lead to "artist"'
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

## Errors

Errors name the valid values rather than reporting a failure:

```
open catalog showing "search"       → -1703  "search" is not a catalog list.
                                             Use explore, schedule, saved.

filter explore genres {"nonsense"}  → -1703  "nonsense" is not a genre id.
                                             `browse genre` takes the name as the
                                             card prints it, e.g. browse genre
                                             "Kosmische".

seek to 1800   (on a channel)       → -1708  …tune an episode first.
show pane "tracks"   (idle)         → -1728  Nothing is playing…
seek to "half"                      → -1700  Can't make "half" into type real.
```

The last is AppleScript's, not the app's — parameter types are declared in the dictionary, so a wrongly typed argument never reaches the app.

## Worked example: wait for audio, then report

```bash
#!/bin/bash
osascript -e 'tell application "NTS Radio" to tune to "episode:anz/anz-25th-june-2026"' >/dev/null

for _ in $(seq 30); do
  state=$(osascript -e 'tell application "NTS Radio" to get state')
  loading=$(printf '%s' "$state" | jq -r .episodeLoading)
  err=$(printf '%s' "$state" | jq -r .episodeError)
  [ -n "$err" ] && { echo "failed: $err"; exit 1; }
  [ "$loading" = "false" ] && break
  sleep 1
done

printf '%s' "$state" | jq -r '"\(.sourceName) — \(.duration)s, rendering=\(.rendering)"'
```

An episode resolves through two network hops — its page, then a signed playlist — either of which can fail, so poll `episodeLoading` and check `episodeError` rather than assuming success.

## What a script cannot do

- **Read a list.** `catalogFirstRows` gives three display strings with no aliases, and opening a show does not report its episodes — so a script cannot get from "find me a show" to "play an episode of it" without querying NTS's API itself. This is [#89](https://github.com/McBrideMusings/nts-desktop/issues/89), the largest gap.
- **Gesture.** No drag, hover or scroll.
- **See the menu-bar icon.** It owns no window and answers no property.
- **Set Show in Dock or Open at Login** — [#99](https://github.com/McBrideMusings/nts-desktop/issues/99).
- **Learn what a `check for updates` found** — same issue.
- **Reach the account.** Reported, never changed. This one is deliberate.

## Adding a command

Both halves or nothing: the terminology in `mac/Resources/NTSRadio.sdef`, the implementation in `mac/Sources/NTSRadio/Model/Scripting.swift`. Add the field to `StateSnapshot.swift` if the command should be observable — the struct fails the build if a field is added without being populated.

Only the installed `.app` carries the dictionary. `admin dev`'s bare binary answers nothing.
