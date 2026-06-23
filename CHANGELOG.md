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
