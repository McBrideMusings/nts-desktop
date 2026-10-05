# Context

The vocabulary this project uses, the numbers that are load-bearing, and a short list of things that look like bugs and are not.

When a document, a comment or a commit message uses one of these words, it means exactly what is here. A term used differently somewhere else is a bug in that place, not a synonym.

Every number below was measured against the running app rather than read from a comment. Where a number lives in code, the file and line are named so it can be checked.

## The objects

**Source.** The thing currently tuned: one of the two live *channels*, one *mixtape*, or one past *episode*. The fourth state is *idle* — nothing tuned, which is what launch starts in unless *resume playback on launch* is on and the last source was a channel or mixtape. `Selection` in `AppModel.swift`.

**Channel.** NTS 1 or NTS 2. Endless: no duration, no position, so no seek bar. Identified to a script as `channel:1`.

**Mixtape.** One of NTS's Infinite Mixtapes — endless, with its own cover art, ring icon, accent hue and credits. Identified by *alias*; to a script as `mixtape:slow-focus`. Sixteen of them, built from the fetched feed, so the count is not fixed.

**Show.** A recurring programme with a name, location, blurb and a run of *episodes*. Identified by alias. The sitemap that seeds the show index carries only URLs, so a freshly seeded show has an alias and no name until the *backfill crawl* reaches it.

**Episode.** One past broadcast of a show, identified by the **pair** of show alias and episode alias — `episode:anz/anz-25th-june-2026`. The only source kind with a duration, and therefore the only one with a seek bar. Has no stream URL of its own: the audio lives on SoundCloud or Mixcloud and is resolved through NTS on **every** play, because the signature expires.

**Broadcast.** One entry in a channel's grid: a show, a start, an end, a channel number. Called a *slot* when the subject is its place in the timeline rather than its content.

**Slot.** A broadcast as a row in the schedule timeline. *On air* when the clock is inside it.

**Row.** The one tile type the catalog grid draws, whatever it represents. Anything that is a row can be saved and opened into a *detail*.

**Track.** One entry in a tracklist: artist, title, and for an episode an offset into the recording.

## State words

These are where two pieces of code most easily disagree. Define once, use exactly.

**Tuned** and **playing** are different. A source can be tuned and paused.

**Playing** means playback was *asked for*. Set inside `play()`/`pause()` and never revised, so it reports intent — a stalled stream leaves it true while producing silence. The play/pause button reads this, because a button should reflect what you pressed.

**Rendering** means audio is actually reaching the speakers (`PlayerEngine.isRendering`, the real AVPlayer rate). Everything that reports live playback back to the user reads this: the menu-bar waterline, the level meter, the buffering state. **Buffering is precisely the disagreement between the two.**

**Seekable** means the loaded item has a real duration. The app never has to be told which kind of source is playing — endless streams report an indefinite duration, which is the truth rather than a failure to load.

**Held track.** A track NTS has pushed that the app is deliberately not showing yet, because the audio it names has not reached the speakers. See the numbers below.

**Saved.** A show, episode or mixtape the user kept. Local-first, works signed out, and **also synced two ways** with the account's nts.live favourites when signed in.

**Signed in** is not the same as **Supporter**. The app knows the first and cannot see the second. The live tracklist and the mixtape's current-episode line come from a Firestore feed only a paid Supporter's token can read; a refusal produces no update, which is indistinguishable from no tracks.

## Where the window can be

**Pane** — one value with two cases, `.live` and `.catalog`. They are peers. Written only by `AppModel.show(_:)`, so the two-segment switch can never light both. **This invariant also lives in `CLAUDE.md`, deliberately duplicated**: it is load-bearing for anyone editing the window code, and that file is always loaded.

**Drawer** — the tracklist. Not a third pane: it covers whichever pane is up and gives it back. All four pane/drawer combinations are real and reachable. **Every pane switch closes it**, including a switch to the pane already showing — guarding that left the tracklist covering the very pane whose segment had just been pressed.

**Detail** — a row opened into its own view inside the catalog. A stack of one; a show's episodes link out to nts.live rather than deeper in.

**Tab** — the catalog has **three**: explore, schedule, saved. **There is no search tab.** A non-empty query replaces whichever tab's grid is showing while the tab chip keeps naming the tab.

## The numbers

| Value | What it governs | Where |
| --- | --- | --- |
| **4.9–5.3s** | Buffered ahead on the NTS 1 live stream | measured |
| **27.4s** | Buffered ahead on a mixtape HLS stream | measured |
| **821.7s** | Buffered ahead on a past episode — a finite file, not a live tail | measured |
| **60s** | Ceiling on the held-track delay; the buffer has never measured near it | `AppModel.swift:539` |
| **120s** | Per-source tracklist cache, so returning to a channel restores it instantly | `AppModel.swift:275` |
| **900s** | Schedule age before a re-fetch; matches NTS's own cache | `AppModel.swift:1122` |
| **60s** | Schedule poll interval — the safety net behind the slot timer | `AppModel.swift:1211` |
| **+1s** | Slot advance fires this far past the boundary, so the slot has genuinely ended | `AppModel.swift:1189` |
| **24h** | Show index and episode index freshness | `ShowIndex.swift:33`, `EpisodeIndex.swift:55` |
| **4 / 250ms** | Backfill crawl concurrency and stagger | `ShowDetailBackfill.swift:24-27` |
| **~36.9KB** | Per show for the detail endpoint — ~68MB for the catalog, which is why the crawl runs once per machine | `ShowDetailBackfill.swift:4-6` |
| **4** | Slot artwork fetch concurrency | `SlotArtLoader.swift:38` |
| **12** | Page size for Explore and for a show's episodes | `ExploreLoader.swift`, `AppModel.swift:1034` |
| **25fps** | Menu-bar waterline redraw, 10ms tolerance | `NTSRadioApp.swift` |
| **0.5s** | Playback position tick | `PlayerEngine.swift:72` |
| **22.5°** | One dial detent — 360 ÷ 16 | measured |
| **495pt** | Now-playing bar drops the meter and volume slider below this width | `NowPlayingBar.swift:22` |
| **520 / 230 / 340pt** | Window minimum: width ≥ 520 with height ≥ 230, **or** height ≥ 520 with width ≥ 340 | `RadioWindowController.swift:14-33` |
| **0–100** | Volume scale, applied to the player as a fraction of 100 | `PlayerEngine.swift:170` |
| **11 days** | What the schedule actually covers, at 11–17 slots a day | measured |
| **1,835 / 1,834** | Shows known / shows named on a warm machine | measured |

## The scripting surface

**The dictionary.** Seventeen commands and eleven properties in one suite, registered by `NSAppleScriptEnabled` and `OSAScriptingDefinition` (`Info.plist:29-32`). `mac/Resources/NTSRadio.sdef` is canonical for terminology; `Scripting.swift` implements it. **A command exists only if both are present.** See [automation.md](automation.md).

**The state blob.** One JSON object describing the whole app, returned by `state` and by every command, so one call acts and reports.

**Object identifier.** `channel:1`, `mixtape:<alias>`, `episode:<show>/<episode>`. The same strings come back in the blob.

Three properties are writable — `volume`, `muted`, `auto checks for updates`. The other eight are read-only.

## Things that look like bugs and are not

Recorded so they stop being re-raised. Each was investigated and is correct.

**The first window open peaks near 285MB.** Drawing any SwiftUI first starts SwiftUI's GPU renderer, which takes ~200MB of GPU-driver memory for about a second, once per process. The radio window is built on its first show, so a session that never opens it never pays this.

**An episode's audio is resolved on every play.** The signed playlist's signature expires; caching it would produce dead links. `AppModel.swift:614-618`.

**A pane switch always closes the drawer**, including a switch to the pane already showing. The guarded version was tried and reverted — it left the tracklist covering the very pane whose segment had just been pressed, so the button looked broken. `AppModel.swift:705-709`.

**A locally installed copy never checks for updates automatically.** `Info.plist` ships `CFBundleVersion: 1`, which `NTSRadioApp.swift:168` correctly treats as a development build. CI rewrites it at `.github/workflows/ci-cd.yml:45`, so releases do check. The consequence worth knowing: a developer's own machine is the one machine that cannot exercise the update path.

**`seek to "half"` raises `-1700`, not a silent seek to zero.** The `.sdef` declares the parameter as a real, so AppleScript refuses the coercion before the command runs. The `?? 0` fallback at `Scripting.swift:416` is unreachable through AppleScript.

**Only one surface in the whole app has a drag.** `grep -rn "DragGesture" mac/Sources/NTSRadio/Views/` returns exactly one hit, `SeekBar.swift:62`. The dial previews on hover and commits on a tap — it is not draggable, despite being drawn as a rotary knob. Whether that is right is [#92](https://github.com/McBrideMusings/nts-desktop/issues/92); that it is deliberate is here.

## Conventions

**Alias** — the lowercase hyphenated identifier NTS uses in URLs. Never "slug", never "ID".

**Times on screen** are the user's local time. NTS's schedule endpoint answers in UTC.

**Durations** are seconds. The seek bar prints `m:ss` under an hour and `h:mm:ss` at or over one, because archive shows run to two and three hours.
