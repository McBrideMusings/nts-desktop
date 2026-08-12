# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

NTS Radio is a native macOS menu-bar app (SwiftUI, Swift 6) for streaming NTS Radio (nts.live) — the two live channels and all of NTS's Infinite Mixtapes, picked from a radial cover-art dial. It plays streams via AVPlayer, fetches the mixtape catalog live from `https://www.nts.live/api/v2/mixtapes` (disk-cached for offline/instant launch), and — for signed-in NTS Supporters accounts — subscribes to Google Firestore's Listen API for real-time live tracklists. Active development; the last commit merged a "now-playing source links" feature and the changelog is still at `0.1.0`.

## Commands

Prefer `admin <task>` (this repo has `admin.toml`); the underlying `make` targets in the root `Makefile` just delegate to `mac/`.

```
admin build      # compile the release binary (swift build -c release)
admin dev        # run from source; press R to rebuild & relaunch, Q to quit — do not run a second instance
admin deploy     # assemble "NTS Radio.app" and install it to /Applications on this machine
admin distribute # build a distributable NTS Radio.dmg

admin setup      # swift package resolve (one-time, after a fresh clone)
admin snapshot   # render each popover state to PNG for visual verification
admin snapshot-windows  # photograph the real windows — title bar, toolbar, chrome (drives the installed app)
admin clean      # remove mac/.build and mac/build
```

Requires macOS 15+ and Xcode 16+ / Swift 6 to build.

## Architecture

The whole app lives in the `mac/` Swift package (root `Makefile`/`admin.toml` just delegate into it):

- `mac/Sources/NTSRadio/Model/` — `Catalog.swift` (mixtape catalog fetch/cache), `PlayerEngine.swift` (AVPlayer), `NTSAPI.swift` / `NTSAuth.swift` (NTS REST API + sign-in), `AppModel.swift` (app state), `NowPlayingCenter.swift` (system media keys + the Control Center tile), `TracklistAdapter.swift`, `Cache.swift`, `ShowIndex.swift` (local searchable show index), `Saved.swift` (local bookmarks), `CatalogRow.swift` (one tile type for the catalog grid), `Scripting.swift` (the AppleScript control surface)
- `mac/Sources/NTSRadio/Views/` — `DialView.swift` (radial mixtape dial), `ChannelRail.swift`, `NowPlayingBar.swift`, `TracklistOverlay.swift`, `CatalogOverlay.swift` (saved / search + detail), `ExploreView.swift` (the default tab: browse the archive by mood and genre), `ScheduleTimeline.swift` (the schedule tab: a fortnight of one channel's grid, day by day), `TitleBarControls.swift` (the title bar's settings button only — the band and the centred NTS mark are `PopoverView`'s, because AppKit insets the accessory past the traffic lights), `SettingsView.swift` (the panes of the Settings window — General and Account — as plain system `Form`s in the `.columns` style, deliberately carrying no `Theme` values), `MenuBarIcon.swift`, `PopoverView.swift`

### Where the window can be

`AppModel.pane` is one value with two cases — `.live` (channel cards + dial) and
`.catalog` — written only by `show(_:)`, so the two-segment switch in the
now-playing bar can never light both. The tracklist is **not** a third case: it is
a drawer (`AppModel.tracksOpen`) that covers whichever pane is up and gives it
back, with its own button outside the switch. All four combinations of the two are
real, visible states. This replaced two independent `Bool`s whose fourth
combination drew the catalog over the tracklist while leaving both buttons lit.

Nothing is drawn over the radio window. Settings and the account were both sheets
inside it, with painted traffic lights; they are the two panes of one real window
now (`SettingsWindowController` + `SettingsView`), so the title bar carries only a
gear — whose green dot is the signed-in state the account button used to show.

Four things about that window, each of which cost a wrong attempt first:

- **SwiftUI's `Settings` scene does not work here.** The app is an agent
  (`.accessory`) whenever "Show in Dock" is off, so there is no app menu for that
  scene to hang off; `openSettings()` reports success and creates no window. The
  scene declaration in `NTSRadioApp` stays an `EmptyView` placeholder only because
  an `App` must declare one.
- **The tabs are an `NSToolbar` with `toolbarStyle = .preference`**, not a
  SwiftUI `TabView` — a `TabView` of `.tabItem`s draws a small segmented picker,
  not the icon-and-label toolbar every Mac preferences window has.
- **One hosted view, whose pane changes** (`SettingsSelection`) — never a swapped
  `contentViewController`. Swapping made AppKit size the window to the incoming
  view first, so each tab click shrank the window, flashed the toolbar's overflow
  chevron, and grew back.
- **Never resize that window by hand.** `NSHostingController.sizingOptions =
  [.preferredContentSize]` lets AppKit do it. `setContentSize` keeps the
  bottom-left corner — AppKit's origin — so every switch to a taller pane walked
  the window up the screen.

There is a main menu (`AppDelegate.installMainMenu`) even though an agent app
never draws one: it is the only place a key equivalent can live, and without it
⌘, opened nothing, ⌘W closed nothing, and the sign-in fields had no ⌘V.

### NTS API limits worth knowing before extending the catalog

- `/api/v2/radio/schedule/{1,2}` is the programme grid: fourteen days per
  channel, ~16 slots a day, each with `start_timestamp`, `end_timestamp` and a
  `links[rel=details]` href naming the show and episode. Every slot carries a
  show alias; about 30% of them (the furthest-out ones) have no episode alias
  yet. No genres, location or artwork — those come from `ShowIndex` by alias,
  and the current programme's own photograph from
  `/api/v2/shows/<show>/episodes/<episode>` once the grid names it.
- `/api/v2/live` is **not used, deliberately**. It returns `now` plus `next` …
  `next17` per channel with `details` embedded for the first two, but it is
  served `cache-control: max-age=900`, so for up to fifteen minutes after every
  changeover it hands back the programme that just finished. Writing that over
  the grid is what made the rail show the previous hour's show. The grid above
  is the only record of what is on; anything that needs artwork or genres for
  the current slot fetches the episode by the aliases the grid supplies.
- `"embeds": {"tracklist": []}` — a bare array where the populated case is an
  object — is how an episode with no identified tracks is serialised, and that
  is every episode still on air. Decoding it strictly fails the whole episode
  request, so `ShowJSON.Embeds` reads the tracklist leniently.
- `/api/v2/search` answers 200 with an empty `results` array — even called
  exactly as nts.live calls it (`?q=…&types[]=show`) with browser headers, and
  even for terms in its own `metadata.popular_terms`. Search is local; there is
  no server search to fall back to.
- `/api/v2/shows` clamps `limit` to 12 and rejects any `offset` above 1000 with
  HTTP 422 — at most 1012 of the 1834 shows. Not used: `ShowIndex` seeds from the
  sitemap instead (below), which has no ceiling.
- `sitemap.xml.gz` → `sitemap{1,2}.xml.gz` is the complete public index and the
  source `ShowIndex` builds from: 1834 show aliases and 89,260 episode URLs in
  ~1.9MB gzipped, three requests, and `robots.txt` is `Allow: /`. Served with
  `Content-Encoding: gzip`, so URLSession decompresses them and the parser only
  sees XML. Regenerated about daily, so the current day's shows are missing from
  it; `/api/v2/collections/recently-added` (newest broadcast first, with
  `audio_sources`) covers the tail and is polled alongside it. Every `<lastmod>`
  inside is just the generation stamp — only the file's own `Last-Modified`/
  `ETag` mean anything.
- There is no favourites REST endpoint — `/api/v2/users/me`, `/api/v2/favourites`
  and `/api/v2/users/me/favourites` return the site's HTML shell, not JSON.
  Favourites live in two top-level Firestore collections: `favourites` holds
  `{show_alias, episode_alias, device_id, created_at, session}` — follows are the
  rows with an empty `episode_alias`, saved episodes the rest — and `user_devices`
  (doc id = installation id) holds `{device_id, firebase_user_uid, …}`.
  **`device_id` is a misnomer**: nts.live fills it with
  `getUserUid() || getInstallationId() || gaClientId`, so while signed in it is
  the Firebase uid, which is why favourites follow you across browsers. The
  installation id only carries stars made before signing in, and `user_devices`
  is how those are found later. Read `device_id IN [uid] + registered
  installation ids`; write `device_id = uid`. `NTSFavourites` does this over Firestore's REST API
  with the Firebase ID token; the gRPC client in `NTSFirestore` is Listen-only.
  **No `orderBy` in those queries** — filtering one field and ordering by
  another needs a composite index that does not exist in NTS's project, and
  asking answers `FAILED_PRECONDITION: The query requires an index`.
- Episode audio is a SoundCloud/Mixcloud page URL in `audio_sources`, which
  AVPlayer cannot open. `/api/v2/resolve-stream?url=<encoded>` returns
  `{"hls": "…m3u8?Policy=…&Signature=…"}` — signed and expiring, so resolve per
  play. It answers 401 without `Authorization: Basic <token>`, where the token is
  the `"NTS_API_TOKEN":"…"` constant in the HTML of every nts.live page. The app
  scrapes it at first play (`NTSAPI.siteToken`) rather than compiling it in, and
  re-reads it once on a 401.
- Explore is `/api/v2/search/episodes` with repeatable `genres[]` and `moods[]`,
  plus `intensity=<lo>-<hi>` (their 0–10 slider ×10) and `genre_count=<n>`.
  nts.live's "Focused" toggle is that `genre_count`; "Music Only" is just
  `moods[]=no-talkin`. 10 moods, 20 primary genres, 438 subgenres. None of it
  needs a user account.
- Every endpoint above is served `cache-control: max-age=900` with an ETag.
- **There is no audio to meter.** Both the live relay
  (`stream-relay-geo.ntslive.net/stream{,2}`) and the mixtape endpoints
  (`stream-mixtape-geo.ntslive.net/mixtape*`) hand AVPlayer an asset that reaches
  `readyToPlay` carrying **zero audio tracks**, so an `AVMutableAudioMix` has
  nothing to attach an `MTAudioProcessingTap` to and no sample ever reaches a
  callback. Measured, not assumed. The only route that does work is a CoreAudio
  process tap over the app's own output (`AudioHardwareCreateProcessTap`, macOS
  14.2+, read through a private aggregate device) — that does deliver real
  samples, but it is audio capture and therefore a permission prompt, which is
  not worth paying for a decoration. `LevelLamps` in `NowPlayingBar.swift`
  invents its levels on purpose and is honest only about *when* it moves.
- `mac/Sources/NTSFirestore/` — a Firestore Listen (gRPC) client for live channel/mixtape tracklists, with generated protobuf/gRPC Swift code under `Generated/` and source `.proto` files in `mac/Proto/` (see `mac/Proto/regenerate.sh`)
- `mac/Sources/FSProbe/` — standalone probe binary, separate from the main app target
- `mixtapes/<slug>/` — per-mixtape assets checked into the repo (cover art, icons, animation `.mp4`s); the `animation_*.mp4` files are gitignored (kept locally, not tracked — the dial doesn't use them yet)
- `mac/codesign-local.sh` — local ad-hoc/keychain code signing so rebuilt dev binaries retain macOS permission grants
- `mac/dev.sh` — the `admin dev` / `make dev` rebuild-and-relaunch loop (R to reload, Q to quit)

## Notes

- Own project — `origin` is `git@github.com:McBrideMusings/nts-desktop.git`; commit straight to `main`.
- Live tracklists require signing in with a paid NTS Supporters account; the Firestore listener path is only exercised when authenticated.
- `CLAUDE.local.md` documents the dev-loop convention in more detail: after code changes, press **R** in the already-running `admin dev` session rather than starting a second one.
- `mac/Sources/NTSFirestore/Generated/` is generated protobuf/gRPC code, not hand-written — regenerate via `mac/Proto/regenerate.sh` rather than editing directly.
- `tmp/` at the repo root is gitignored and used for scratch/design output. `admin snapshot` renders views off screen to `tmp/claude/design/swift-shots`; `admin snapshot-windows` (`mac/snapshot-windows.sh`) drives the *installed* app and captures the real windows to `tmp/claude/design/window-shots` — the only way to see AppKit's own chrome, since nothing rendered off screen contains a title bar or a toolbar.
- **Control surface — drive the app with `osascript`, never the mouse.** The
  scripting dictionary is `mac/Resources/NTSRadio.sdef`; its implementation is
  `mac/Sources/NTSRadio/Model/Scripting.swift`. Every command answers with the
  same JSON blob `state` returns, so one call both acts and reports:

  ```
  osascript -e 'tell application "NTS Radio" to get state'
  osascript -e 'tell application "NTS Radio" to tune to "mixtape:slow-focus"'
  osascript -e 'tell application "NTS Radio" to tune to "episode:lung-dart/lung-dart-10th-august-2026"'
  osascript -e 'tell application "NTS Radio" to skip by 1'
  osascript -e 'tell application "NTS Radio" to show pane "live"'
  osascript -e 'tell application "NTS Radio" to show pane "tracks"'
  osascript -e 'tell application "NTS Radio" to open settings'
  osascript -e 'tell application "NTS Radio" to open settings "account"'
  osascript -e 'tell application "NTS Radio" to open catalog showing "schedule"'
  osascript -e 'tell application "NTS Radio" to filter explore mood "sedative" genres {"ambientnewage"}'
  osascript -e 'tell application "NTS Radio" to explore more'
  osascript -e 'tell application "NTS Radio" to seek to 1800'
  osascript -e 'tell application "NTS Radio" to open catalog searching for "veronica"'
  osascript -e 'tell application "NTS Radio" to close catalog'
  ```

  `tune to` is the code path a click takes; `skip by` is the one the media keys
  take. Adding a command means editing both halves. Only the installed `.app`
  carries the dictionary — `admin dev`'s bare binary answers nothing.
- **Verifying a change: `.claude/skills/verify/SKILL.md`** shadows the bundled `verify` skill, which is marked `disable-model-invocation` and so only runs when the user types `/verify` — stalling any unattended `implement` / `iterate` / `orchestrate` pass. The project version carries this app's build-install-drive-observe recipe: the scripting calls above, the pixel-scan technique for the menu-bar status item (it owns no enumerable window, and no scripted surface either), and the locked-display check that otherwise yields an all-black screenshot at exit 0.
