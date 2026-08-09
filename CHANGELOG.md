# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
