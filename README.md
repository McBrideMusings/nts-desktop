# NTS Radio

A native macOS menu-bar app for [NTS Radio](https://www.nts.live) — the two live
channels and the Infinite Mixtapes, in a SwiftUI dial that lives in your menu bar.

## Features

- **Live channels** — NTS 1 and 2, with now-playing info.
- **Infinite Mixtapes** — all of NTS's 24/7 genre streams, picked from a radial
  cover-art dial.
- Play / pause, mute, and volume from a compact now-playing bar.
- **Live mixtape tracklists** — real-time, updating the moment a track changes
  (requires signing in with a paid NTS Supporters account).
- **Lives in the menu bar** — click the icon to toggle a floating, resizable
  window that stays open while you work in other apps. A top bar carries the
  macOS window controls, a login indicator, and settings.
- **Optional Dock icon** — off by default (menu bar only); enable it in
  Settings → Show in Dock.

## Requirements

- macOS 15 (Sequoia) or later
- Xcode 16+ / Swift 6 (to build)

## Build & run

The app lives in `mac/` (a Swift package). From the repo root:

```
make dev       # run from source; press R to rebuild & relaunch, Q to quit
make build     # compile the release binary
make app       # assemble "NTS Radio.app"
make install   # build and install to /Applications
make deploy    # build a distributable .dmg
```

Each target delegates to `mac/`; you can also run `make <target>` from inside
`mac/` directly.

To quit the app, open Settings (the gear in the window's top bar) and choose
**Quit NTS Radio** — a menu-bar-only app has no app menu.

## Project layout

```
mac/         # the SwiftUI menu-bar app (Swift package)
  Sources/NTSRadio/
    Model/   # catalog, AVPlayer engine, NTS API, auth, app state
    Views/   # menu-bar icon, dial, channel rail, now-playing bar, settings
  Sources/NTSFirestore/  # Firestore Listen client for live mixtape tracklists
  Proto/     # vendored Firestore protos + regenerate.sh
```

The infinite-mixtapes dial is built at runtime from NTS's public catalog
(`https://www.nts.live/api/v2/mixtapes`) — names, art, icons, and looping
animations are fetched live and disk-cached for offline/instant launch.

## License

MIT — see [LICENSE](LICENSE).
