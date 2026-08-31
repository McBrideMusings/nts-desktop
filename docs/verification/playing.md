# Verification: playing and live

How to run this file: install and launch a clean build per the protocol, volume audible, mute off, window open on the live pane. **This file is where the pointer items live** — the seek bar and the dial cannot be driven by script at all, so almost everything here needs a mouse and a pair of eyes. Set the window to at least 700pt wide before starting, and have a way to make it narrower than 495pt for the degradation items. Results already filled in came from the scripted pass of 2026-08-27.

## playing/the-seek-bar.md

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SEEK-01 | P1 | mouse | The bar exists only for an episode (summary). | Window open. | 1. Tune NTS 1; look above the transport.<br>2. Tune a mixtape; look.<br>3. Tune an episode; look. | Absent for the first two, present for the third. Absent, not disabled. | — |
| SEEK-02 | P1 | mouse | The scrub begins at the press, with no distance threshold (press). | An episode playing past 0:30. | 1. Press on the track 200px right of the thumb and hold still.<br>2. Watch the thumb and the left label. | Both jump to the press point immediately. The audio does not move. | — |
| SEEK-03 | P1 | mouse | A plain click commits a seek (release without dragging). | An episode playing. | 1. Click once on the track, halfway along.<br>2. Listen. | The audio jumps to that point. There is no way to press and change your mind. | — |
| SEEK-04 | P1 | mouse | During the drag the bar follows the pointer and the audio does not (during the drag). | An episode playing. | 1. Press on the track and hold for 30s without releasing.<br>2. Listen throughout.<br>3. Release at the same point. | Audio plays on from the old position throughout. The seek lands where the pointer was, not 30s later. | — |
| SEEK-05 | P2 | mouse | Vertical movement is ignored and the pointer may leave the window (during the drag). | An episode playing. | 1. Press on the track.<br>2. Drag 300px down and out of the window, moving horizontally.<br>3. Release. | The scrub tracks horizontally throughout and commits on release. | — |
| SEEK-06 | P1 | mouse | The thumb does not snap back after a seek (release after dragging). | An episode playing. | 1. Drag to 75% and release.<br>2. Watch the thumb closely for 2s. | It stays at 75%. No visible snap back and forward. | — |
| SEEK-07 | P1 | script | `seek to` moves the playhead exactly and clamps at both ends (driven by script). | An episode tuned, duration known. | 1. `seek to 1800`, read `position`.<br>2. `seek to -50`, read.<br>3. `seek to 99999`, read. | 1800; 0; the duration. | pass |
| SEEK-08 | P1 | script | Seeking a live source fails rather than doing nothing (driven by script). | NTS 1 tuned. | 1. `seek to 1800`. | Error `-1708` with the documented message. | pass |
| SEEK-09 | P2 | mouse | The labels switch format at an hour (edge cases). | — | 1. Tune an episode under an hour; read both labels.<br>2. Tune one over an hour; read both. | `m:ss` then `h:mm:ss`. | — |
| SEEK-10 | P3 | mouse | The hit area is taller than the track (edge cases). | An episode playing. | 1. Click 5px above the visible 3pt track. | The seek registers. | — |
| SEEK-11 | P2 | mouse | Dismissing the window mid-drag commits nothing (cancel and interrupt). | An episode playing, window open. | 1. Press on the track at 75%.<br>2. Without releasing, click the menu-bar icon to dismiss.<br>3. Reopen and read `position`. | The playhead is where it was, not at 75%. | — |
| SEEK-12 | P2 | mouse | Changing source mid-drag abandons the scrub silently (cancel and interrupt). | An episode playing. | 1. Press on the track.<br>2. From a terminal, `tune to "channel:1"`.<br>3. Release. | No seek; the bar slides away. No error. | — |
| SEEK-13 | P3 | mouse | The reveal is a 0.2s ease-out combining fade and move (open questions). | — | 1. Tune from a channel to an episode.<br>2. Screen-record the bottom of the window. | A ~0.2s slide up from the bottom edge with a fade. | — |

Not checkable by hand:

- Whether the seek bar's lack of a precision modifier is a problem is a product judgement (open questions).

## playing/the-now-playing-bar.md

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BAR-01 | P1 | mouse | Below 495pt the meter and slider go and the title gets their room (what it holds). | Window ~700pt wide, something playing. | 1. Note the meter and slider.<br>2. Drag the window narrower than 495pt.<br>3. Note again. | Meter and slider gone; mute, tracklist button and pane switch all remain; the title has more room. | — |
| BAR-02 | P1 | mouse | The subtitle reads `BUFFERING` while play is down and no audio is out (the two lines of text). | Idle. | 1. Tune a mixtape and watch the subtitle in the first second. | `BUFFERING`, replaced once audio starts. | — |
| BAR-03 | P1 | mouse | The level meter reads rendering, not playing (the level meter). | NTS 1 playing. | 1. Watch the lamps.<br>2. Turn Wi-Fi off and wait ~10s. | Lamps stop when audio stops, though the button still shows pause. | — |
| BAR-04 | P2 | mouse | The meter stops while muted (edge cases). | Something rendering. | 1. Press mute.<br>2. Watch the lamps. | They stop. | — |
| BAR-05 | P1 | mouse | Play/pause and the tracklist button are dead when idle (press). | Freshly launched, idle. | 1. Look at both buttons.<br>2. Click each. | Both dimmed to ~40%; neither does anything. | — |
| BAR-06 | P2 | mouse | The idle placeholders read as documented (the two lines of text). | Idle. | 1. Read both lines. | `NOTHING PLAYING` and `PICK A MIXTAPE OR CHANNEL`. | — |
| BAR-07 | P2 | mouse | An episode that fails shows `COULDN'T PLAY`, not `LOADING…` (the two lines of text). | Wi-Fi off. | 1. Tune an episode.<br>2. Wait for the failure.<br>3. Read both lines. | Title `COULDN'T PLAY`; subtitle the reason in capitals. | — |
| BAR-08 | P2 | mouse | The pane switch cannot light both segments (driven by script). | Window open. | 1. Click between LIVE and the catalog segment several times, watching both. | Exactly one lit at all times. | — |
| BAR-09 | P3 | mouse | Both segments carry tooltips (edge cases). | Window open. | 1. Hover each segment for 2s. | "What is on air now" and "The archive — schedule, saved and search". | — |
| BAR-10 | P3 | mouse | The tracklist button's tooltip changes with its state (edge cases). | Something playing. | 1. Hover the button closed, then open. | "Tracklist for what is playing", then "Hide the tracklist". | — |
| BAR-11 | P2 | mouse | A mixtape's episode line is a link when signed in (the two lines of text). | Signed in as a Supporter, a mixtape playing, past the first push. | 1. Read the subtitle.<br>2. Click it. | It is the episode title; clicking opens nts.live. | — |

## playing/volume-and-mute.md

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| VOL-01 | P1 | mouse | Volume applies continuously during the drag (during the drag). | Something playing, window ≥495pt. | 1. Drag the slider slowly from 80 to 20.<br>2. Listen throughout. | Loudness changes as the thumb moves, not on release. | — |
| VOL-02 | P1 | mouse | Muting does not move the slider (the simple case). | Volume at 60. | 1. Press mute.<br>2. Look at the slider.<br>3. Unmute. | The slider stays at 60, dimmed; audio returns at 60. | pass (script) |
| VOL-03 | P1 | script | `set volume to N` fails, `set its volume to N` works (driven by script) — **B-03**. | App running. | 1. `set volume to 30`.<br>2. `set its volume to 30`.<br>3. `set (volume) to 30`. | Step 1 errors `-2741`; steps 2 and 3 succeed. | pass |
| VOL-04 | P2 | script | Out-of-range values are clamped, not refused (edge cases). | App running. | 1. `set its volume to 150`, read.<br>2. `set its volume to -10`, read. | 100 and 0. | — |
| VOL-05 | P2 | mouse | Both persist across a relaunch (interactions). | Volume 33, muted. | 1. Quit and relaunch.<br>2. Read both. | 33 and muted. | — |
| VOL-06 | P2 | mouse | Mute is in the status menu and has no command form (driven by script). | — | 1. Right-click the menu-bar icon.<br>2. Check the dictionary for a mute command. | Mute is in the menu; the dictionary has the property only. | pass |
| VOL-07 | P3 | mouse | The slider dims to ~40% while muted but stays draggable (edge cases). | Muted. | 1. Drag the slider. | It moves; the value changes; audio stays silent. | — |

## playing/the-tracklist-drawer.md

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TRK-01 | P1 | script+supporter | The held track is real and observable (the held track) — needs ~1s polling. | Signed in as a Supporter, NTS 1 playing, drawer open. | 1. Poll `get state` every second for 10 minutes, logging `pendingTrack` and `pendingSeconds`.<br>2. Find a track change. | At a change, `pendingTrack` is non-empty and `pendingSeconds` counts down from ≈5. | — (not caught at 20s sampling) |
| TRK-02 | P1 | mouse+supporter | The current track is the top row for a live source (which row is "now playing"). | NTS 1 playing, drawer open. | 1. Note which row is marked. | The topmost. | — |
| TRK-03 | P1 | mouse | For an episode the marked row follows the playhead, backwards too (which row is "now playing"). | An episode with a tracklist playing, drawer open. | 1. Note the marked row.<br>2. Seek forward 20 minutes; note it.<br>3. Seek back to the start; note it. | The mark moves forward, then back to the first row. | — |
| TRK-04 | P1 | mouse | Switching source republishes immediately with no hold (cancel and interrupt). | NTS 1 playing, drawer open with rows. | 1. Tune NTS 2.<br>2. Watch the drawer. | The list changes at once; it does not sit empty for ~5s. | — |
| TRK-05 | P2 | mouse | Returning to a source within 120s restores its list instantly (release without dragging). | NTS 1 playing, drawer open with rows. | 1. Tune NTS 2, wait 30s.<br>2. Tune NTS 1.<br>3. Watch the drawer. | NTS 1's rows appear immediately. | — |
| TRK-06 | P2 | mouse | The header label differs by source kind (which row is "now playing"). | — | 1. Open the drawer on a channel, a mixtape and an episode in turn. | `TRACKLIST`, `RECENTLY PLAYED`, `TRACKLIST`. | — |
| TRK-07 | P1 | offline+supporter | A dropped live connection is completely silent (cancel and interrupt) — **B-09**. | NTS 1 playing, drawer open with rows. | 1. Turn Wi-Fi off.<br>2. Wait 5 minutes.<br>3. Watch the drawer and the banner. | Record. Expected: rows freeze, no banner, no staleness marker. | — |
| TRK-08 | P2 | mouse | Pausing publishes a held track at once (the held track). | NTS 1 playing, drawer open, a hold in progress (see TRK-01). | 1. Press pause during a hold.<br>2. Watch the top row. | It appears immediately. | — |
| TRK-09 | P2 | mouse | An empty episode tracklist reads the same as every other empty case (edge cases) — related to **B-02**. | An older or spoken-word episode. | 1. Play it, open the drawer. | `No tracklist available`. | — |
| TRK-10 | P2 | script | Only one track string is exposed, and no row list (driven by script). | Something playing with a tracklist. | 1. Read the whole blob. | `currentTrack` is one combined string; no row array. | pass |

## live/the-dial.md

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DIAL-01 | P1 | mouse | The dial cannot be rotated (becoming a drag) — **B-05**. | Live pane, dial visible. | 1. Press on a wedge.<br>2. Drag in a full circle without releasing.<br>3. Release. | Record. Expected: no rotation; the tap resolves at the release point. | — |
| DIAL-02 | P1 | mouse | Hovering previews on the knob face without committing (the knob face). | Live pane, a mixtape tuned. | 1. Move the cursor slowly across several wedges.<br>2. Watch the knob face.<br>3. Move off the dial. | The face reads out each mixtape in turn, then returns to the tuned one. Nothing changes what is playing. | — |
| DIAL-03 | P1 | mouse | The knob is a dead zone (press). | Live pane. | 1. Click the centre of the knob. | Nothing happens — no selection, no play/pause. | — |
| DIAL-04 | P1 | mouse | Clicking a wedge tunes and plays (release without dragging). | Live pane, idle. | 1. Click a wedge. | That mixtape plays; the index turns to it. | — |
| DIAL-05 | P2 | script | `knobAngle` is 0 when idle and a multiple of 22.5 otherwise (edge cases). | Idle. | 1. Read `knobAngle`.<br>2. Tune a mixtape, read again. | 0, then a multiple of 22.5. | pass |
| DIAL-06 | P2 | mouse | The dial is capped in size (the layout follows the hardware). | Window open. | 1. Make the window full screen.<br>2. Look at the dial. | It stops growing; the extra space becomes margin. | — |
| DIAL-07 | P2 | offline | The dial draws and is tunable from the disk cache (modifiers). | Warm machine. | 1. Quit, Wi-Fi off, launch.<br>2. Open the live pane. | All 16 wedges drawn with art. | — |
| DIAL-08 | P3 | mouse | The accent colour follows the tuned mixtape (edge cases). | — | 1. Tune two different mixtapes.<br>2. Compare the seek bar fill and the level meter. | Different accent colours. | — |

## live/the-channel-cards.md

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CARD-01 | P1 | mouse | The inactive card is dimmed, not drained (summary). | NTS 1 playing. | 1. Look at both cards. | Both show their photographs; the inactive one is dimmer but readable. | — |
| CARD-02 | P1 | mouse | Hovering brings the photo to full strength with an accent outline (hovering previews). | NTS 1 playing. | 1. Hover the NTS 2 card. | The photo brightens; an accent outline appears. Nothing plays. | — |
| CARD-03 | P1 | mouse | The card degrades in three steps as the window narrows (what a card carries). | Window ~800pt wide. | 1. Narrow the window in stages, noting the card at each.<br>2. Continue to 340pt. | Chips go, then the metadata line shortens to times, then the words go — photograph, numeral and LED remain. | — |
| CARD-04 | P1 | mouse | A genre chip opens Explore filtered to that genre (the genre chips). | A card showing chips. | 1. Note a chip's text.<br>2. Click it. | The catalog opens on Explore filtered to it — the same result as `browse genre` with that name. | — |
| CARD-05 | P2 | mouse | A chip Explore does not file stays plain text (the genre chips). | A card whose chips include an unusual tag. | 1. Hover and click each chip. | At least one is not clickable and is styled as plain text. | — |
| CARD-06 | P1 | mouse | The LED is not a control (the LED is not a button). | NTS 1 playing. | 1. Click the boxed numeral on the NTS 2 card. | It behaves as clicking the card — it is not a separate target. Record if it differs. | — |
| CARD-07 | P1 | mouse | The card changes programme on its own at a boundary (cancel and interrupt). | A boundary within 10 minutes (check `nextUp`). | 1. Leave the window open on the live pane.<br>2. Watch across the boundary. | The photograph, title and chips change without any input. | — |
| CARD-08 | P2 | mouse | The two stars save different things (the two stars). | A card with both glyphs. | 1. Click the first; check Saved.<br>2. Undo, click the second; check Saved. | One saves the show, one the episode, distinguishable in the Saved tab. | — |
| CARD-09 | P3 | mouse | The card stretches rather than letterboxing (what a card carries). | — | 1. Set the window to a strongly non-square shape. | Cards fill their slots; no bare rail either side. | — |

Not checkable by hand:

- Whether the double photograph swap at a changeover is perceptible (open questions).
- Whether the LED reads as a control is a design judgement, not a pass/fail.
