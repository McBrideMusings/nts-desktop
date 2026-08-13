# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Follow a show or save its episode straight from a live channel card: two
  glyphs in the card's top-right corner, left of the live LED. They appear when
  the pointer is on the card, and a star that is already set stays lit, so a
  resting rail marks only the programmes you kept. Both write to the same
  `Saved` list the catalog writes to, and sync to the NTS account.
- The channel card's title opens that broadcast's page on nts.live, and its
  genre chips open the archive filtered to that genre — the schedule prints
  genres as names and Explore filters on ids, so "Kosmische" is looked up as
  `ambientnewage-kosmiche`. A genre Explore does not file stays plain text.
  The city stays a label: Explore has no location filter, and 12 of the 1834
  indexed shows carry a location at all, written "LDN" where the card prints
  "LONDON".
- A show's genre tags in the archive browse that genre too, the same as a
  channel card's chips. Its mood tags stay labels, which falls out of the same
  lookup — a mood is not a genre id, so nothing pretends it has somewhere to go.
- `browse genre "<name>"` in the AppleScript dictionary — the genre chip's own
  door, taking the name the card prints, so the name-to-id translation is
  drivable without a mouse.
- `open show "<alias>"`, plus `catalogDetail` and `detailTags` in the `state`
  blob. A show's page could only be reached by clicking a tile, so nothing about
  that pane could be driven or read back — and a detail pane covering the whole
  catalog was invisible from `state` while the grid's own fields carried on
  describing the list underneath it.
- Unstarring reaches the NTS account in every case, not just for stars that
  predate the launch sync. Removing a favourite needs the Firestore document
  name, and only rows in the snapshot read at startup had one — so a star and an
  unstar in the same session deleted the local row, left the account's, and the
  next launch synced it straight back. The document name is kept when the
  favourite is created, an unstar issued before that create lands waits for it,
  and one issued before or during a sync is held until the fetch names the
  document. A delete that fails no longer forgets what it was aiming at.

- `knob angle` in the AppleScript dictionary and the `state` blob — where the
  dial's index mark points, in degrees clockwise from the top, counting turns
  rather than wrapping at 360. Two readings therefore say which way the dial
  turned and how far, which is what makes the rotation checkable from a script.
- `channels`, `bufferSeconds`, `pendingTrack` and `pendingSeconds` in the `state`
  blob. `state` could only ever describe the source you were listening to, so
  with a mixtape playing the channel rail's contents were invisible from a
  script; `channels` reports each channel's programme and how many slots it still
  holds regardless. `bufferSeconds` is the audio AVPlayer has fetched but not yet
  played — 4.9s median on the Icecast channel streams, 29.1s on the mixtape HLS —
  and `pendingTrack` / `pendingSeconds` name the track being held back and how
  long it has left to wait.
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

- An AppleScript dictionary, so a program can drive the radio and read back what
  it did without anyone touching the mouse. `tell application "NTS Radio" to get
  state` answers with a JSON object — what is tuned, whether audio is genuinely
  rendering as opposed to merely buffering, the current track, volume, whether
  the window is up — and `tune to`, `play`, `pause`, `skip by`, `open window` and
  `close window` each answer with that same blob, so one call both acts and
  reports. `open window` deliberately does not activate the app: a scripted open
  must never take the keyboard from whoever is at the machine.

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
- Picking a mixtape or a channel now starts playing it. Before, clicking a dial
  wedge, a channel card, or a catalog row while nothing was playing only tuned
  the source and left the app silent until Play was pressed. The media keys are
  unchanged: skipping to the next source while paused stays paused.

- Each tracklist row leads with the artist and carries the track underneath, the
  order nts.live lists them in. A track still being identified arrives with no
  artist, and keeps its title on the lead line rather than showing a blank one.

- The five equaliser bars in the now-playing bar are a dot-matrix level panel:
  five columns of seven lamps filling from the bottom, with a peak lamp held
  above each column and falling back a lamp at a time. Quantising to whole lamps
  is what makes it read as a piece of hardware rather than as an animation.
  Resting — idle, paused, muted, or buffering — is the bottom row lit and
  nothing else. The levels are invented, deliberately: see **Fixed** for what it
  now moves on, and `LevelLamps` for why measuring them is not worth a
  permission prompt.

### Fixed

- The now-playing indicator moves only while audio is genuinely coming out. It
  read `isPlaying` — whether Play had been pressed — so through a buffering
  stall, when AVPlayer is sitting in `waitingToPlayAtSpecifiedRate` and the
  speakers are silent, the bars kept bouncing. It reads `engine.isRendering`
  now, and rests.
- The indicator's bars no longer drift off their baseline. Each bar was drawn at
  full height and squashed by `scaleEffect` under a `repeatForever` animation
  with nothing recording where that animation had got to; `PlayerEngine`
  publishes `position` twice a second, so the bar was rebuilt mid-squash and the
  repeat restarted from wherever the picture happened to be, leaving the cluster
  floating clear of the floor. Every lamp in its replacement is a function of the
  clock alone, so there is no part-finished animation to interrupt.
- The channel rail hands over to the next programme on its own clock instead of
  waiting to be told. NTS serves `/api/v2/live` with `cache-control: max-age=900`,
  so for up to fifteen minutes after the hour every 60-second poll returned the
  same pre-changeover JSON: at 15:11 London the rail read "Vanilla Glint w/ DJ
  Cinco De Mayo & Gustavio, 14:00 – 15:00" while nts.live had moved on to "Skinny
  Girl Diet" an hour later. Every poll already carries `now` plus `next` … `next17`
  with the minute each slot ends, so a changeover needs no request at all — the
  finished slot is dropped on a timer set to its own end time, and the poll only
  re-anchors the schedule.
- A track no longer appears in the tracklist before you can hear it. NTS pushes
  each track over Firestore the moment it airs, but AVPlayer is behind the live
  edge by whatever it has buffered — measured at 4.9s on the channel streams and
  29.1s on the mixtape HLS — so the top row lit up while the previous track was
  still coming out of the speakers. A newly started track now waits for the
  player's current buffer to drain before it reaches the list. The backfill on
  opening the app or switching source is not delayed, and neither is a paused
  player.
- The dial waits for a real size before drawing. Its whole geometry is a
  fraction of the smaller window dimension, so on a layout pass that reported
  zero it collapsed to a point in the top-left corner — and a click landing in
  that frame was measured from the corner and could select a mixtape nowhere
  near the cursor.
- The dial's index mark takes the short way round. Its angle was the position's
  number times 22.5°, which always landed between 0° and 360°, so stepping from
  the last mixtape (337.5°) to the first (0°) read as a 337.5° journey backwards
  instead of a 22.5° nudge forwards — the knob unwound almost a full turn every
  time the selection wrapped. The angle now counts turns instead of wrapping, and
  each move takes whichever direction is shorter.
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
