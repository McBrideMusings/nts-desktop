# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Archivo's `OFL.txt` alongside the bundled font, so the app ships the SIL Open
  Font License the way that license requires. It lands in the app's resource
  bundle next to `Archivo.ttf`.
- Three bars beside the NTS wordmark in the menu bar, animating while audio
  plays and flat when it doesn't. They track `AVPlayer.timeControlStatus` rather
  than the play button, so a stalled stream stops the bars instead of bouncing
  through the silence. The image is a fixed 32×16pt in every state, so starting
  or stopping playback never shifts the menu-bar icons beside it.
- A catalog that covers the whole window, opened with the grid button in the
  title bar. Three tabs — **Schedule**, **Saved**, **Mixtapes** — plus a search
  field that is always present rather than a tab of its own. Every tile opens a
  full-width detail page.
- **Schedule** lists both channels' programmes for the next eighteen slots each.
  That data was already arriving in every `/api/v2/live` poll as `now` plus
  `next` … `next17`; the app had been decoding `now` and discarding the rest.
- **Search** filters shows, mixtapes and mixtape credits at once, so a host's
  name finds the mixtape their show feeds. It runs against a local index because
  NTS's `/api/v2/search` answers 200 with an empty result set for every type.
  The index is built once from `/api/v2/shows` and cached for a week; the header
  states how many shows are in it, since the endpoint refuses any offset past
  1000 and so cannot reach every show NTS lists.
- **Saved** shows and mixtapes, starred from any tile or detail page and stored
  in Application Support. NTS exposes no favourites API — `/api/v2/users/me`,
  `/api/v2/favourites` and `/api/v2/users/me/favourites` all answer 400 — so
  these stay on this Mac.
- Show detail: artwork, host blurb, genres and moods, and recent episodes that
  open on nts.live. Mixtape detail lists the shows feeding it, each one a link
  into that show's page.

### Changed

- The channel cards are now the programme's photograph, shown for **both**
  channels — the inactive one dimmed rather than drained of colour, where before
  only the playing channel's artwork appeared at all. The 86pt accent disc is
  gone; the channel number is a small printed box in the corner, as it is on the
  Atonemo faceplate, and the card carries the location, air time, and genres.
- The dial is the Atonemo's rotary: a knurled knob with a detent tick per
  position, the mixtape icons printed on the faceplate outside it, and a
  triangular index on the rim that turns to the selection. The knob's face
  carries the mixtape's cover art and name — it was a 166pt disc that showed
  nothing.
- Removed the "Hide Dial Dot When Small" setting along with the dial dot it
  controlled.

### Fixed

- The Keychain helper behind sign-in no longer discards the `OSStatus` from
  `SecItemDelete` and `SecItemAdd`. A failed write meant the refresh token never
  reached disk while the app carried on as if signed in, so the session ended at
  the next launch with nothing said. Failures now name themselves, and a missing
  item on the first write is correctly not treated as one.

## [0.1.0]

### Added

- Native macOS SwiftUI menu-bar app.
- Live NTS channels 1 & 2 and the Infinite Mixtapes, streamed via AVPlayer.
- Radial cover-art dial for selecting mixtapes; channel rail for the live streams.
- Now-playing bar with play/pause, mute, and volume.
- Tracklist view and a macOS-style settings sheet.
- Floating, resizable window toggled from the menu bar — stays open while other
  apps are focused; the dial reflows to fit any size.
- Top bar with the macOS window controls, a login-state indicator, and settings.
- Optional Dock icon (Settings → Show in Dock), persisted across launches.
- `make dev` / `admin dev` reload loop — press **R** to rebuild & relaunch,
  **Q** to quit; the dev app also exits with the terminal that started it.
- Now-playing source links: a live channel's show title links to its current
  episode on nts.live, and the playing mixtape's current source episode appears
  in the secondary line and links to that episode (sourced from NTS's Firestore
  `mixtape_titles`). Clickable labels render bold white with a hover underline.
- System playback controls. The laptop's play/pause media key and a headset's
  play/pause button start and stop the stream; next/previous step to the
  neighbouring source — the two live channels toggle between themselves, and
  mixtapes cycle the dial and wrap at both ends. The Now Playing tile in Control
  Center shows the current track (or the show/mixtape name when no track feed is
  available), the source, and its cover art — the mixtape's poster, a live
  channel's program art, or the channel's own gradient when it has none. Marked
  as a live stream, so no scrubber or elapsed time.

### Changed

- Synced the interface to the Claude Design prototype: the tracklist is now a
  full-width overlay (NOW PLAYING header, TIME/TRACK/COPY columns, per-row copy
  button, red accent on the playing row); the live-channel cards show the city +
  time range in the chip with the show name below; and the dial's center hub is
  an always-present passive disc (no play control in the hub) with a triangular
  tail pointing at the selected mixtape.
- The app launches idle — nothing is selected or playing until you pick a mixtape
  or channel (previously it auto-selected the first mixtape).
- Settings is now grouped GENERAL / DISPLAY sections with a "Hide Dial Dot When
  Small" toggle; sign-in moved into a standalone Account popover. (Show in Dock
  and the in-Settings Quit were removed; Quit remains in the menu-bar menu.)
- The app icon and the menu-bar icon are now the NTS logo, with the mark also
  centered in the window title bar.

### Fixed

- Decode HTML entities in live show titles (e.g. `&amp;` now renders as `&`).
- Capture the app's stdout in the `admin dev` / `make dev` log by making stdout
  unbuffered (a long-running GUI process otherwise never flushes to the pipe).
- Keychain re-prompt on every rebuild: local builds are now stable-signed (Apple
  Development identity + a fixed identifier) so macOS keeps the grant across
  rebuilds instead of treating each ad-hoc build as a new app.
