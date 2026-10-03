# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

NTS Radio (git@github.com:McBrideMusings/nts-desktop.git) is a native macOS menu-bar app (SwiftUI, Swift 6) for streaming NTS Radio (nts.live) — the two live channels and all of NTS's Infinite Mixtapes, picked from a radial cover-art dial. It plays streams via AVPlayer, fetches the mixtape catalog live from `https://www.nts.live/api/v2/mixtapes` (disk-cached for offline/instant launch), and — for signed-in NTS Supporters accounts — subscribes to Google Firestore's Listen API for real-time live tracklists. Active development; the last commit merged a "now-playing source links" feature and the changelog is still at `0.1.0`.

## Commands

Prefer `admin <task>` (this repo has `admin.toml`); the underlying `make` targets in the root `Makefile` just delegate to `mac/`.

```
admin build      # compile the release binary (swift build -c release)
admin dev        # run from source; press R to rebuild & relaunch, Q to quit — do not run a second instance
admin deploy     # quit the running app, install a fresh "NTS Radio.app" to /Applications, relaunch it, and return once it answers
admin distribute # build a distributable NTS Radio.dmg

admin state      # the installed app's state JSON, pretty-printed (pipes into jq)
admin drive <verb> [args]  # run one scripting command and print the state it returns; bare `admin drive` lists the verbs

admin setup      # swift package resolve (one-time, after a fresh clone)
admin snapshot   # render each popover state to PNG for visual verification
admin snapshot-windows  # photograph the real windows — title bar, toolbar, chrome (drives the installed app)
admin clean      # remove mac/.build and mac/build
```

Requires macOS 15+ and Xcode 16+ / Swift 6 to build.

## Architecture

The whole app lives in the `mac/` Swift package (root `Makefile`/`admin.toml` just delegate into it):

- `mac/Sources/NTSRadio/Model/` — `Catalog.swift` (mixtape catalog fetch/cache), `PlayerEngine.swift` (AVPlayer), `NTSAPI.swift` / `NTSAuth.swift` (NTS REST API + sign-in), `AppModel.swift` (app state), `SlotArtLoader.swift` (the schedule-artwork fetch queue — concurrency-limited, debounced, trimmed to the live grid), `ExploreLoader.swift` (the Explore paging queue), `StateSnapshot.swift` (the `Codable` type behind the AppleScript `state` blob), `NowPlayingCenter.swift` (system media keys + the Control Center tile), `TracklistAdapter.swift`, `Cache.swift`, `ShowIndex.swift` (local searchable show index), `ShowDetailBackfill.swift`
  (the once-per-machine crawl that fills in each show's real name, location and
  host blurb from `/api/v2/shows/<alias>`), `Saved.swift` (local bookmarks), `CatalogRow.swift` (one tile type for the catalog grid), `Scripting.swift` (the AppleScript control surface)
- `mac/Sources/NTSRadio/Views/` — `DialView.swift` (radial mixtape dial), `ChannelRail.swift`, `NowPlayingBar.swift`, `TracklistOverlay.swift`, `CatalogOverlay.swift` (saved / search + detail), `ExploreView.swift` (the default tab: browse the archive by mood and genre), `ScheduleTimeline.swift` (the schedule tab: a fortnight of one channel's grid, day by day), `TitleBarControls.swift` (the title bar's settings button only — the band and the centred NTS mark are `PopoverView`'s, because AppKit insets the accessory past the traffic lights), `SettingsView.swift` (the panes of the Settings window — General and Account — as plain system `Form`s in the `.columns` style, deliberately carrying no `Theme` values), `MenuBarIcon.swift`, `PopoverView.swift`

### Where the window can be

`AppModel.pane` is one value with two cases — `.live` (channel cards + dial) and
`.catalog` — written only by `show(_:)`, so the two-segment switch in the
now-playing bar can never light both. The tracklist is **not** a third case: it is
a drawer (`AppModel.tracksOpen`) that covers whichever pane is up and gives it
back, with its own button outside the switch. All four combinations of the two
are real, visible states. This replaced two independent `Bool`s whose fourth
combination drew the catalog over the tracklist while leaving both buttons lit.

Nothing is drawn over the radio window. Settings and the account are the two
panes of one real window (`SettingsWindowController` + `SettingsView`), so the
title bar carries only a gear — whose green dot is the signed-in state.

Four rules for that window:

- **Don't use SwiftUI's `Settings` scene** — see `docs/adr/0003-hand-built-settings-window.md`.
- **The tabs are an `NSToolbar` with `toolbarStyle = .preference`**, not a
  SwiftUI `TabView`, whose `.tabItem`s draw a small segmented picker rather than
  the icon-and-label toolbar every Mac preferences window has.
- **Use one hosted view whose pane changes** (`SettingsSelection`), never a
  swapped `contentViewController`, which makes AppKit size the window to the
  incoming view first.
- **Never resize that window by hand** — set `NSHostingController.sizingOptions
  = [.preferredContentSize]` and let AppKit do it, because `setContentSize`
  keeps the bottom-left corner (AppKit's origin) and walks the window up the
  screen on every switch to a taller pane.

There is a main menu (`AppDelegate.installMainMenu`) even though an agent app
never draws one: it is the only place a key equivalent can live, and without it
⌘, opened nothing, ⌘W closed nothing, and the sign-in fields had no ⌘V.

- **Vocabulary, the load-bearing numbers, and things that look like bugs and
  are not: `docs/CONTEXT.md`** — read it before naming anything, and before
  reporting a defect, so a settled question is not re-raised.
- **NTS API limits and endpoint quirks: `docs/nts-api.md`** — read it before
  touching the catalog, the API client, or the show index.
- `mac/Sources/NTSFirestore/` — a Firestore Listen (gRPC) client for live channel/mixtape tracklists, with generated protobuf/gRPC Swift code under `Generated/` and source `.proto` files in `mac/Proto/` (see `mac/Proto/regenerate.sh`)
- `mac/Sources/FSProbe/` — standalone probe binary, separate from the main app target
- `mixtapes/<slug>/` — per-mixtape assets checked into the repo (cover art, icons, animation `.mp4`s); the `animation_*.mp4` files are gitignored (kept locally, not tracked — the dial doesn't use them yet)
- `mac/codesign-local.sh` — local ad-hoc/keychain code signing so rebuilt dev binaries retain macOS permission grants
- `mac/dev.sh` — the `admin dev` / `make dev` rebuild-and-relaunch loop (R to reload, Q to quit)
- `mac/drive.sh` — `admin state` / `admin drive`'s verb-to-AppleScript map, plus the graceful `quit` and wait-for-state `launch` that bracket `admin deploy`

## Notes

- **The AppleScript surface, written for a user: `docs/automation.md`** — every
  command with worked examples, the errors verbatim, and what a script cannot
  reach. `mac/Resources/NTSRadio.sdef` stays canonical for terminology.
- Decision records: `docs/adr/0001-schedule-grid-not-live-endpoint.md`,
  `docs/adr/0002-show-index-from-sitemap.md`,
  `docs/adr/0003-hand-built-settings-window.md`,
  `docs/adr/0004-no-audio-metering.md`,
  `docs/adr/0005-discovery-is-the-services-job.md`.
- Live tracklists require signing in with a paid NTS Supporters account; the Firestore listener path is only exercised when authenticated.
- `CLAUDE.local.md` documents the dev-loop convention in more detail: after code changes, press **R** in the already-running `admin dev` session rather than starting a second one.
- `mac/Sources/NTSFirestore/Generated/` is generated protobuf/gRPC code, not hand-written — regenerate via `mac/Proto/regenerate.sh` rather than editing directly.
- `tmp/` at the repo root is gitignored and used for scratch/design output. `admin snapshot` renders views off screen to `tmp/claude/design/swift-shots`; `admin snapshot-windows` (`mac/snapshot-windows.sh`) drives the *installed* app and captures the real windows to `tmp/claude/design/window-shots` — the only way to see AppKit's own chrome, since nothing rendered off screen contains a title bar or a toolbar.
- **Control surface — drive the app with `admin drive`, never the mouse.** The
  scripting dictionary is `mac/Resources/NTSRadio.sdef`; its implementation is
  `mac/Sources/NTSRadio/Model/Scripting.swift`. `mac/drive.sh` maps short verbs
  onto it and does the AppleScript quoting. Every command answers with the same
  JSON blob `state` returns, so one call both acts and reports:

  ```
  admin state
  admin drive tune mixtape:slow-focus
  admin drive tune episode:lung-dart/lung-dart-10th-august-2026
  admin drive tune channel:1 --wait     # answers once audio is coming out (10s cap)
  admin drive skip 1
  admin drive stop                      # back to idle, the launch state
  admin drive pane live
  admin drive pane tracks
  admin drive settings
  admin drive settings account
  admin drive catalog schedule
  admin drive filter mood sedative genre ambientnewage
  admin drive more
  admin drive genre Kosmische
  admin drive show veronica-vasicka
  admin drive seek 1800
  admin drive search veronica
  admin drive close-catalog
  admin drive updates
  admin drive set track-lead artist     # a setter prints `get state` afterwards
  ```

  `tune to` is the code path a click takes; `skip by` is the one the media keys
  take. Adding a command means editing both halves, plus a verb in
  `mac/drive.sh`. Only the installed `.app` carries the dictionary — `admin
  dev`'s bare binary answers nothing.
- **Verifying a change: `.claude/skills/verify-project/SKILL.md`** shadows the bundled `verify` skill, which is marked `disable-model-invocation` and so only runs when the user types `/verify` — stalling any unattended `implement` / `iterate` / `orchestrate` pass. The project version carries this app's build-install-drive-observe recipe: the scripting calls above, the pixel-scan technique for the menu-bar status item (it owns no enumerable window, and no scripted surface either), and the locked-display check that otherwise yields an all-black screenshot at exit 0.
