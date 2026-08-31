# NTS Radio

A native macOS menu-bar app for [NTS Radio](https://www.nts.live) — the two live
channels, the Infinite Mixtapes, and the whole archive, in a window you summon
from the menu bar.

## Features

- **Live channels** — NTS 1 and 2, each showing what is on air now with its
  photograph, location and genres.
- **Infinite Mixtapes** — all sixteen of NTS's 24/7 genre streams, picked from a
  radial cover-art dial.
- **The archive** — browse by mood and genre, search every show NTS publishes,
  read a fortnight of either channel's schedule day by day, and play any past
  episode with a working scrubber.
- **Live tracklists** — for both the channels and the mixtapes, updating as
  tracks change, held back so a row lights up when you hear it rather than when
  NTS announces it. Requires a paid NTS Supporters account.
- **Save what you like** — follow a show or keep a single episode. Saved items
  sync both ways with the same favourites your account holds on nts.live.
- **Lives in the menu bar** — click the icon for a floating, resizable window
  that stays open while you work in other apps, and never steals focus.
- **Media keys and Control Center** — play, pause and skip from the keyboard, a
  headset, or the lock screen.
- **Fully scriptable** — seventeen AppleScript commands, and every one of them
  answers with the app's whole state as JSON. See
  [docs/automation.md](docs/automation.md).
- **Works offline** — the mixtape dial, the schedule, artwork and search all
  come from disk, so the app is browsable with no network.

## Install

**Homebrew:**

```
brew install --cask nts-radio
```

**Or download** the latest `.dmg` from
[Releases](https://github.com/McBrideMusings/nts-desktop/releases), open it, and
drag **NTS Radio** into `/Applications`.

The app has no Dock icon by default — after launching it, look for the square at
the right end of your menu bar. Turn the Dock icon on in **Settings ▸ General ▸
Show in Dock** if you would rather have one.

Requires macOS 15 (Sequoia) or later.

## Using it

- **Click the menu-bar icon** to show or hide the window.
- **Right-click it** for play/pause, mute, the two live channels, and **Quit**.
- **⌘,** opens Settings. **⌘Q** quits.
- Sign in under **Settings ▸ Account** to get live tracklists and to sync your
  saved items with nts.live.

## Build from source

Requires Xcode 16+ / Swift 6. The app lives in `mac/`, a Swift package; the root
`Makefile` and `admin.toml` delegate into it.

```
admin setup        # swift package resolve, once after a fresh clone
admin dev          # run from source; press R to rebuild & relaunch, Q to quit
admin build        # compile the release binary
admin deploy       # build the .app and install it to /Applications
admin distribute   # build a distributable NTS Radio.dmg
```

The equivalent `make` targets exist, with **one collision worth knowing**:
`admin deploy` installs to `/Applications`, while `make deploy` builds a `.dmg`.
Prefer the `admin` commands.

## Project layout

```
mac/                       # the SwiftUI menu-bar app (Swift package)
  Sources/NTSRadio/
    Model/                 # catalog, AVPlayer engine, NTS API, auth, app state
    Views/                 # menu-bar icon, dial, channel cards, now-playing bar, settings
    Resources/NTSRadio.sdef  # the AppleScript dictionary
  Sources/NTSFirestore/    # Firestore Listen client for live tracklists
  Sources/EpisodeMatch/    # show search and track→episode resolution (the tested part)
  Proto/                   # vendored Firestore protos + regenerate.sh
docs/                      # context, automation, API notes, decision records
```

The mixtape dial is built at runtime from NTS's public catalog
(`https://www.nts.live/api/v2/mixtapes`) — names, art, icons and animations are
fetched live and disk-cached, so the dial paints and is playable at launch
before any request returns.

## Documentation

- **[docs/CONTEXT.md](docs/CONTEXT.md)** — the vocabulary, the load-bearing
  numbers, and a list of things that look like bugs and are not.
- **[docs/automation.md](docs/automation.md)** — the AppleScript surface.
- **[docs/nts-api.md](docs/nts-api.md)** — NTS's endpoints, their limits and
  quirks.
- **[docs/verification/](docs/verification/)** — 264 checkable claims about how
  the app behaves, by area.
- **[docs/adr/](docs/adr/)** — why the schedule, the show index, the settings
  window, the absent audio metering and the discovery model are the way they are.

## License

MIT — see [LICENSE](LICENSE).
