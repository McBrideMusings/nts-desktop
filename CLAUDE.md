# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

NTS Radio is a native macOS menu-bar app (SwiftUI, Swift 6) for streaming NTS Radio (nts.live) — the two live channels and all of NTS's Infinite Mixtapes, picked from a radial cover-art dial. It plays streams via AVPlayer, fetches the mixtape catalog live from `https://www.nts.live/api/v2/mixtapes` (disk-cached for offline/instant launch), and — for signed-in NTS Supporters accounts — subscribes to Google Firestore's Listen API for real-time live tracklists. Active development; the last commit merged a "now-playing source links" feature and the changelog is still at `0.1.0`.

## Commands

Prefer `admin <task>` (this repo has `admin.toml`); the underlying `make` targets in the root `Makefile` just delegate to `mac/`.

```
admin setup      # swift package resolve (one-time, after a fresh clone)
admin dev        # run from source; press R to rebuild & relaunch, Q to quit — do not run a second instance
admin build      # compile the release binary (swift build -c release)
admin app        # assemble "NTS Radio.app" (bundles mixtapes + fonts)
admin start      # build the .app and launch it
admin install    # build the .app and install to /Applications
admin deploy     # build a distributable NTS Radio.dmg
admin snapshot   # render each popover state to PNG for visual verification
admin clean      # remove mac/.build and mac/build
```

Requires macOS 15+ and Xcode 16+ / Swift 6 to build.

## Architecture

The whole app lives in the `mac/` Swift package (root `Makefile`/`admin.toml` just delegate into it):

- `mac/Sources/NTSRadio/Model/` — `Catalog.swift` (mixtape catalog fetch/cache), `PlayerEngine.swift` (AVPlayer), `NTSAPI.swift` / `NTSAuth.swift` (NTS REST API + sign-in), `AppModel.swift` (app state), `NowPlayingCenter.swift` (system media keys + the Control Center tile), `TracklistAdapter.swift`, `Cache.swift`
- `mac/Sources/NTSRadio/Views/` — `DialView.swift` (radial mixtape dial), `ChannelRail.swift`, `NowPlayingBar.swift`, `TracklistOverlay.swift`, `TopBar.swift`, `SettingsView.swift`, `LoginView.swift`, `MenuBarIcon.swift`, `PopoverView.swift`
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
- `tmp/` at the repo root is gitignored and used for scratch/design output (e.g. `admin snapshot` writes PNGs to `tmp/claude/design/swift-shots`).
