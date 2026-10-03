# Verification: system

How to run this file: most of it needs conditions the everyday machine does not have. **INST-\* needs a downloaded release and ideally a second Mac.** **UPD-\* needs a `release` copy** — a local `admin deploy` build carries `CFBundleVersion: 1` and suppresses automatic checks by design, so it cannot verify the update path. The Settings and Dock items run on any install. Do not run UPD-04 on a machine you rely on: it installs a real update. Results already filled in came from the scripted pass of 2026-08-27.

## system/installing.md

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| INST-01 | P1 | release | The disk image window has one icon and no Applications alias (the disk image) — **B-07**. | A downloaded `NTS-Radio.dmg`. | 1. Double-click it.<br>2. Screenshot the window that opens. | Record. Expected: a default Finder window, one app icon, no alias, no background, no set geometry. | — |
| INST-02 | P1 | release+clean | Gatekeeper's behaviour on first launch (Gatekeeper). | A Mac that has never run the app, the `.dmg` downloaded via a browser. | 1. Copy the app to `/Applications`.<br>2. Double-click it.<br>3. Record the dialog verbatim. | Either a standard "downloaded from the internet" confirmation (notarized) or a refusal needing right-click → Open (ad-hoc). Note which, since it decides B-07's severity. | — |
| INST-03 | P1 | clean | Nothing tells a new user this is a menu-bar app (finding it afterwards). | A Mac that has never run the app. | 1. Launch it for the first time.<br>2. Wait 10s without touching anything. | Record. Expected: no window, no Dock icon, no notification — only a new menu-bar icon. | — |
| INST-04 | P2 | clean | The first launch opens idle with an empty catalog (modifiers). | A Mac that has never run the app, online. | 1. Launch, open the window immediately.<br>2. Note the dial and the schedule.<br>3. Note both again after 30s. | Empty at first, populated after. Time how long. | — |
| INST-05 | P2 | release | Running the app from the mounted image works (edge cases). | The `.dmg` mounted. | 1. Double-click the app inside the image without copying it. | It runs. Nothing warns that it will vanish on eject. | — |
| INST-06 | P2 | release | The Homebrew route places the app with no disk-image step (the Homebrew cask). | A Mac with Homebrew, app not installed. | 1. `brew install --cask nts-radio`.<br>2. Check `/Applications`. | The app is installed with no window and no drag. | — |
| INST-07 | P3 | — | The image and the app disagree on the name (edge cases) — **B-17**. | The `.dmg`. | 1. Note the file name and the app inside. | `NTS-Radio.dmg` containing `NTS Radio.app`. | — |

Not checkable by hand:

- Which signing path a real release actually takes, without access to the CI secrets (open questions).

## system/the-settings-window.md

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SET-01 | P1 | mouse | Switching pane resizes the window once, smoothly, without walking up the screen (four rules the window follows). | Settings open on General. | 1. Note the window's position on screen.<br>2. Switch to Account and back, several times.<br>3. Note the position again. | Resizes smoothly, no shrink-then-grow, no toolbar chevron flashing, and the window does not creep up the screen. | — |
| SET-02 | P1 | mouse | The tabs are a preference-style toolbar, not a segmented picker (four rules). | Settings open. | 1. Look at the top of the window. | Icon-and-label toolbar items, as in System Settings — not a small segmented control. | — |
| SET-03 | P1 | keyboard | ⌘, opens Settings (modifiers). | App running, radio window key. | 1. Press ⌘,. | Settings opens. | — |
| SET-04 | P1 | keyboard | What Escape does here (cancel and interrupt) — the one open Escape question. | Settings open. | 1. Press Escape. | Record. This is the only place in the app where Escape plausibly does something. | — |
| SET-05 | P1 | script | The window's state is reported (driven by script). | Settings closed. | 1. Read `settingsVisible`, `settingsPane`.<br>2. `open settings "account"`, read both again. | `false`/`general`, then `true`/`account`. | pass (scripted 2026-10-03) |
| SET-06 | P2 | mouse | Every route lands on the last-shown pane (press). | Settings open on Account, then closed. | 1. Reopen via the gear.<br>2. Close, reopen via the status menu. | Account both times, not General. | — |
| SET-07 | P2 | mouse | Settings follows the system appearance while the radio window does not (edge cases). | Both windows open. | 1. Switch macOS between light and dark. | Settings changes; the radio window stays dark. | — |
| SET-08 | P2 | mouse | Clicking outside does not close it (cancel and interrupt). | Settings open. | 1. Click the Desktop. | It stays open. | — |
| SET-09 | P2 | mouse | Checkbox changes apply immediately with no Apply button (release without dragging). | Settings ▸ General. | 1. Toggle Show in Dock. | The Dock icon appears at once; there is no OK or Apply. | — |
| SET-10 | P3 | mouse | There is no cache control anywhere (interactions) — **B-15**. | Settings open. | 1. Read both panes in full. | No clear-cache, rebuild-index or refresh control. | — |

## system/media-keys-and-now-playing.md

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| MK-01 | P1 | keyboard | The media keys drive the app with the window closed (cancel and interrupt). | NTS 1 playing, window dismissed. | 1. Press the play/pause key.<br>2. Press it again. | Audio stops and starts. | — |
| MK-02 | P1 | keyboard | Next track moves to the neighbouring **source**, not a track (what "next track" means here). | A mixtape playing. | 1. Press the next-track key. | A different mixtape starts. The track within the mixtape does not skip. | — |
| MK-03 | P1 | keyboard | Next on an episode does nothing (what "next track" means here). | An episode playing. | 1. Press next, then previous. | Playback continues unchanged. Record whether this reads as a broken key. | — |
| MK-04 | P1 | mouse | The tile is marked live for a stream and scrubbable for an episode (summary). | — | 1. Play NTS 1; open Control Center and look at Now Playing.<br>2. Play an episode; look again. | No scrubber or elapsed time for the channel; both for the episode. | — |
| MK-05 | P1 | mouse | The tile's scrubber seeks the episode (release after dragging). | An episode playing, Control Center open. | 1. Drag the tile's scrubber to the middle.<br>2. Read `position`. | The audio and `position` both move there. | — |
| MK-06 | P2 | mouse | The tile follows a seek made in the app (the tile's elapsed time). | An episode playing, Control Center open. | 1. Drag the app's seek bar to 75%.<br>2. Watch the tile. | Its elapsed time jumps to match rather than counting on from the old position. | — |
| MK-07 | P2 | mouse | Four tile controls are absent, not inert (what each control does). | Something playing, Control Center open. | 1. Look for seek-forward, seek-backward, skip-forward, skip-backward and stop. | None offered. | — |
| MK-08 | P2 | keyboard | Volume keys change the system volume, not the app's (edge cases). | Something playing, app volume at 41. | 1. Press the volume-down key twice.<br>2. Read `volume`. | Still 41; the Mac's own volume changed. | — |
| MK-09 | P2 | keyboard | Another media app takes the keys (cancel and interrupt). | NTS 1 playing. | 1. Start playback in another media app.<br>2. Press play/pause. | It reaches the other app. | — |
| MK-10 | P1 | script | `skip by` shares the media keys' path (driven by script). | A mixtape playing. | 1. `skip by 1`, note the source.<br>2. Press the next-track key from the same state. | Both reach the same next mixtape. | pass (scripted 2026-10-03; script half; the media key needs a keyboard) |

Not checkable by hand:

- Whether media-key handling is genuinely absent under `admin dev` was not tested; the documented reason is that a bare binary has no bundle identifier (edge cases).

## system/updates.md

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| UPD-01 | P1 | release | A release copy checks automatically (how checking works). | A copy installed from a GitHub Release or the tap. | 1. Read `autoChecksForUpdates`. | `true`. | — |
| UPD-02 | P1 | — | A local build suppresses automatic checks by design (development builds never check). | An `admin deploy` build. | 1. `defaults read "/Applications/NTS Radio.app/Contents/Info.plist" CFBundleVersion`.<br>2. Read `autoChecksForUpdates`. | `1` and `false`. Not a defect. | pass |
| UPD-03 | P1 | script | `check for updates` returns before the check completes (driven by script) — **B-12**. | App running. | 1. `check for updates` and time the reply.<br>2. Read the blob for any result field. | Returns immediately; nothing reports found, downloading or failed. | — |
| UPD-04 | P2 | release | An update relaunches the app and playback stops (interactions). | A release copy with an update available. **Do not run on a machine you rely on.** | 1. Start playback.<br>2. Check for updates and accept.<br>3. After the relaunch, read `source`. | The app relaunches; `source: "idle"`; nothing playing. | — |
| UPD-05 | P2 | script | `auto checks for updates` is writable (driven by script). | App running. | 1. `set auto checks for updates to true`, read.<br>2. Set it back. | The value changes both ways. | pass (scripted 2026-10-03) |
| UPD-06 | P2 | offline | A check fails cleanly when offline (modifiers). | Wi-Fi off. | 1. Settings ▸ General → Check for Updates…. | Sparkle reports a failure; the app's own outage banner does not appear. | — |
| UPD-07 | P3 | script | No version field is reported (driven by script) — **B-12**. | — | 1. Read the whole blob. | No `version`. | pass (scripted 2026-10-03) |

Not checkable by hand:

- Whether a Homebrew-installed copy updated in place by Sparkle confuses Homebrew's record of what is installed (open questions).

## system/start-on-login-and-dock.md

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DOCK-01 | P1 | mouse | Show in Dock applies live with no relaunch (Show in Dock). | Settings ▸ General, Dock icon off. | 1. Tick Show in Dock.<br>2. Watch the Dock. | An icon appears at once. | — |
| DOCK-02 | P1 | mouse | Turning it on reveals the main menu (edge cases). | Dock icon off. | 1. Note the menu bar.<br>2. Tick Show in Dock and bring the app forward. | An application menu appears for the first time. | — |
| DOCK-03 | P2 | mouse | Clicking the Dock icon raises the radio window (edge cases). | Dock icon on, window dismissed. | 1. Click the Dock icon. | The radio window appears. | — |
| DOCK-04 | P1 | mouse | Open at login reports off when approval is withdrawn (Open at login). | Open at login ticked. | 1. Switch it off in System Settings ▸ General ▸ Login Items.<br>2. Return to the app's Settings and read the checkbox. | Unticked. Note whether it needed a relaunch. | — |
| DOCK-05 | P2 | mouse | The app actually starts at login (Open at login). | Open at login ticked, app quit. | 1. Log out and back in.<br>2. Check the menu bar. | The icon is there. | — |
| DOCK-06 | P1 | script | Neither setting is scriptable or reported (driven by script) — **B-12**. | — | 1. Read the whole blob.<br>2. Read the dictionary. | No `showInDock`, no `startOnLogin`, no command for either. | pass (scripted 2026-10-03) |
| DOCK-07 | P2 | mouse | Both settings appear in the status menu too (interactions). | — | 1. Right-click the menu-bar icon. | Open at Login and Show in Dock, reflecting the current state. | — |
| DOCK-08 | P3 | mouse | The menu-bar icon cannot be hidden (edge cases). | Settings ▸ General. | 1. Read the pane for any hide-icon control. | None. | — |
