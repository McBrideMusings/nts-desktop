# Verification: foundations

How to run this file: install and launch a clean build per the protocol, with volume audible and mute off. Most items here are `script` and can be run in one sitting; the `mouse` items need the radio window open. Two blocks need conditions this machine does not have — **PLAY-11** and **ACCT-05 to ACCT-08** need a `free-account`, and **ACCT-01 to ACCT-03** need `signed-out`. Do those as their own passes. Results already filled in came from the scripted pass of 2026-08-27.

## foundations/playing.md

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PLAY-01 | P1 | script | Only an episode reports a duration and is seekable (the three kinds of source). | App running, idle. | 1. `tune to "channel:1"`, read `duration`, `seekable`.<br>2. `tune to "mixtape:slow-focus"`, read both.<br>3. `tune to "episode:anz/anz-25th-june-2026"`, wait 8s, read both. | Channel and mixtape: `duration: 0`, `seekable: false`. Episode: a real duration, `seekable: true`. | pass (scripted 2026-10-03) |
| PLAY-02 | P1 | script | Playing and rendering are separate states (playing is not the same as rendering). | Idle. | 1. `tune to "channel:1"`.<br>2. Read `playing` and `rendering` immediately, then again after 6s. | Both fields present and independently reported; `rendering` true once audio starts. | pass (scripted 2026-10-03) |
| PLAY-03 | P1 | mouse | Resuming a live source rejoins at the live edge, not the buffer (what "resume" means). | NTS 1 playing, window open. | 1. Note the audio.<br>2. Press pause.<br>3. Wait 60s.<br>4. Press play. | Audio resumes at the *current* broadcast, not 60s behind. | — |
| PLAY-04 | P2 | mouse | Resuming an episode continues from where it was (what "resume" means). | An episode playing, past 0:30. | 1. Note the seek bar position.<br>2. Pause, wait 30s, play. | Playback continues from the noted position, not from 0:00. | — |
| PLAY-05 | P1 | script | Skip walks mixtapes and wraps in both directions (skipping). | `tune to "mixtape:slow-focus"`. | 1. `skip by 1`, read `source`.<br>2. `skip by -1`, read `source`. | Moves to a different mixtape, then back to `mixtape:slow-focus`. | pass (scripted 2026-10-03) |
| PLAY-06 | P1 | script | Skip on an episode is refused (skipping). | An episode tuned. | 1. `skip by 1`, read `source`. | Error `-1708`; `source` unchanged. | pass (scripted 2026-10-03) |
| PLAY-07 | P2 | script | Skip on idle is refused (skipping). | Freshly launched, idle. | 1. `skip by 1`, read `source`. | Error `-1708`; `source: "idle"`. | pass (scripted 2026-10-03) |
| PLAY-08 | P2 | script | Skipping while paused stays paused (skipping). | A mixtape tuned and paused. | 1. `skip by 1`.<br>2. Read `playing`. | `playing: false`. | pass (scripted 2026-10-03) |
| PLAY-09 | P3 | script | Buffered-ahead differs by source kind (buffered ahead). | — | 1. Tune each of a channel, a mixtape and an episode; wait 8s after each; read `bufferSeconds`. | Roughly 5s, 27s and 800s+ respectively. | pass (scripted 2026-10-03) |
| PLAY-10 | P1 | script | The app launches idle and does not remember the tuned source (edge cases). | Something playing. | 1. Quit the app.<br>2. Relaunch.<br>3. Read `source`. | `source: "idle"`, nothing playing. | pass (scripted 2026-10-03) |
| PLAY-11 | P2 | free-account | Playback is unaffected by the account (modifiers). | Signed in without a subscription. | 1. Tune each source kind. | All three play normally. | blocked — no free account |
| PLAY-12 | P2 | script | `play` while already playing is a no-op, not a reconnect (what "resume" means). | NTS 1 playing and rendering. | 1. `play`.<br>2. Listen for an audible interruption. | No gap or restart in the audio. | — |
| PLAY-13 | P2 | offline | A live stream keeps playing on its buffer then stalls (cancel and interrupt). | NTS 1 playing. | 1. Turn Wi-Fi off.<br>2. Watch for ~15s, reading `playing` and `rendering`. | Audio continues ~5s, then stops. `playing` stays true, `rendering` goes false. | — |

Not checkable by hand:

- Whether a live stream resumes on its own after a long sleep, or requires a press (open questions).

## foundations/the-catalog.md

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CAT-01 | P1 | script | The backfill crawl reports its own progress (the show index and the backfill crawl). | App running. | 1. `get state`, read `showIndex`. | Four fields: `shows`, `named`, `remaining`, `running`. | pass (scripted 2026-10-03) |
| CAT-02 | P1 | clean | On a first launch the catalog is empty until the network answers (the very first launch). | A machine with no Application Support data for the app. | 1. Launch.<br>2. Open the window within 2s.<br>3. Note the dial, the schedule and the search count. | Dial empty, schedule empty, search count rising from near zero. | blocked — needs a clean machine |
| CAT-03 | P2 | script | Not every schedule slot resolves to an episode (edge cases). | App running, schedule loaded. | 1. `get state`, compare `slots` and `slotsWithEpisode` per channel. | At least one channel where they differ. | pass (scripted 2026-10-03) |
| CAT-04 | P2 | script | The counts are as documented (confirmed). | App running. | 1. Read `mixtapeCount`, `genreCount`, `moodCount`, `channelCount`. | 16, 20, 10, 2. | pass (scripted 2026-10-03) |
| CAT-05 | P2 | mouse | A show with no real name yet shows an alias-derived title (edge cases). | A machine mid-crawl. | 1. Search for a show not yet named.<br>2. Read its tile. | The alias with hyphens as spaces, wrong in case and punctuation. | blocked — crawl complete here |
| CAT-06 | P3 | offline | The catalog draws entirely from disk (modifiers). | Warm machine, Wi-Fi off, app relaunched. | 1. Open the dial, the schedule and search. | All three populated. | — |

Not checkable by hand:

- Whether the one show marked `remaining` is a permanent straggler or the newest (open questions).

## foundations/the-window.md

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| WIN-01 | P1 | mouse | Clicking the icon while the window is buried **raises** it rather than hiding it (release without dragging). | Window open, then Safari brought forward over it. | 1. Click the menu-bar icon once. | The window comes to the front. It does **not** hide. | — |
| WIN-02 | P1 | mouse | Clicking the icon while the window is frontmost and key hides it (release without dragging). | Window open, app frontmost, window key. | 1. Click the icon once. | The window goes off screen. | — |
| WIN-03 | P1 | mouse | Clicking outside the window does not dismiss it (cancel and interrupt). | Window open. | 1. Click on the Desktop. | The window stays on screen. | — |
| WIN-04 | P1 | mouse | The waterline moves only while audio is rendering (the menu-bar icon). | NTS 1 playing. | 1. Watch the icon while rendering.<br>2. Pause.<br>3. Watch again. | Motion while rendering; still when paused. | — |
| WIN-05 | P1 | mouse | Pausing keeps the badge and stops only the motion (the menu-bar icon). | NTS 2 playing. | 1. Pause.<br>2. Screenshot the menu bar and zoom. | The badge still reads `2`; no NTS wordmark. | — |
| WIN-06 | P2 | mouse | The badge follows a source change made while paused (edge cases). | NTS 2 tuned, paused. | 1. `skip by 1` (moves to NTS 1).<br>2. Screenshot the menu bar. | The badge reads `1`, not `2`. | — |
| WIN-07 | P2 | mouse | The right-click menu carries the eight documented items (the right-click menu). | App running. | 1. Right-click the icon. | Play/Pause, Mute, Live 1, Live 2, Open at Login, Show in Dock, Check for Updates…, Settings…, Quit. | — |
| WIN-08 | P1 | script | `open window` does not take keyboard focus (driven by script). | Window closed, a text editor frontmost with the caret in a document. | 1. Type continuously in the editor.<br>2. From another terminal, run `open window`.<br>3. Keep typing. | The window appears; every keystroke still lands in the editor. | pass (scripted 2026-10-04; frontmost app compared, no keystrokes typed) |
| WIN-09 | P2 | mouse | The window's minimum size follows the two-part rule (during the drag). | Window open. | 1. Drag the corner to make it as small as possible, first wide-and-short, then narrow-and-tall. | Stops at 520×230 and at 340×520. Dragging diagonally through the corner does not stick or jump. | — |
| WIN-10 | P2 | keyboard | ⌘W closes the window but does not quit (edge cases). | Window open and key. | 1. Press ⌘W.<br>2. Check the menu bar. | Window closes; the icon remains. | — |
| WIN-11 | P2 | script | Window state survives a close and reopen (confirmed). | Catalog pane, drawer open. | 1. `close window`, `open window`, read `pane` and `tracksOpen`. | Both unchanged. | pass (scripted 2026-10-04) |
| WIN-12 | P2 | script | A closed window holds no SwiftUI content, and opening it puts the content back. | Window closed. | 1. `open window`, `close window`, twice, reading `windowContentAttached` after each. | `true`, `false`, `true`, `false`. | — |

Not checkable by hand:

- Whether the window's position and size persist across a relaunch (open questions).

## foundations/panes-and-drawers.md

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PANE-01 | P1 | script | All four pane/drawer combinations are reachable (the shape). | Something tuned. | 1. `show pane "live"` then `"tracks"`; read both fields.<br>2. `show pane "catalog"` then `"tracks"`; read both. | live+closed, live+open, catalog+closed, catalog+open all observed. | pass (scripted 2026-10-03) |
| PANE-02 | P1 | mouse | Pressing the already-lit pane segment still closes the drawer (the rule that catches people). | Live pane, drawer open. | 1. Press the LIVE segment. | The drawer closes; the pane does not change. | — |
| PANE-03 | P1 | script | Leaving the catalog discards the query and the detail (what each transition discards). | Catalog, a query set, a show open. | 1. `close catalog`.<br>2. `show pane "catalog"`.<br>3. Read `catalogQuery` and `catalogDetail`. | Both empty. | pass (scripted 2026-10-03) |
| PANE-04 | P1 | script | The tab survives leaving and re-entering the catalog (what each transition discards). | Catalog on the Saved tab. | 1. `close catalog`, `show pane "catalog"`, read `catalogTab`. | `saved`. | pass (scripted 2026-10-03) |
| PANE-05 | P1 | script | `show pane "none"` drops the drawer without changing the pane (driven by script). | Catalog pane, drawer open. | 1. `show pane "none"`, read both fields. | `tracksOpen: false`, `pane: "catalog"`. | pass (scripted 2026-10-03) |
| PANE-06 | P1 | script | `show pane "tracks"` while idle raises an error, while the button is silently dead (edge cases). | Freshly launched, idle. | 1. `show pane "tracks"`.<br>2. Click the tracklist button in the window. | The command errors `-1728`, "Nothing is playing, so there is no tracklist to show."; the button does nothing and says nothing. | pass (scripted 2026-10-03; script half; the button needs a mouse) |
| PANE-09 | P2 | script | `show pane` accepts an undocumented fifth value (driven by script). | Something tuned. | 1. `show pane "tracklist"`, read `tracksOpen`.<br>2. Read the `.sdef`'s description for the parameter. | `true`; the `.sdef` names only live, catalog, tracks, none. | pass (scripted 2026-10-03) |
| PANE-07 | P2 | mouse | The drawer covers a detail and gives it back (edge cases). | A show detail open, something playing. | 1. Open the drawer.<br>2. Close it. | The detail is showing again, unchanged. | — |
| PANE-08 | P2 | keyboard | Escape closes neither the drawer nor a detail (cancel and interrupt) — **B-16**. | Drawer open over a detail. | 1. Press Escape.<br>2. Press it again. | Nothing closes. Record what happens. | — |

## foundations/the-scripting-dictionary.md

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DICT-01 | P1 | mouse | Script Editor shows the dictionary (discovering it). | — | 1. Open Script Editor.<br>2. File → Open Dictionary → NTS Radio. | All 17 commands and 11 properties listed with their descriptions. | — |
| DICT-02 | P1 | mouse | Shortcuts cannot see the app (discovering it) — **B-06**. | — | 1. Open Shortcuts.<br>2. Search the action list for "NTS". | No NTS Radio actions. Record what appears. | — |
| DICT-03 | P1 | script | `set volume to N` fails; `set its volume to N` works (the volume collision) — **B-03**. | App running. | 1. `set volume to 30`.<br>2. `set its volume to 30`.<br>3. `get volume`. | Step 1 errors `-2741`. Step 2 succeeds. Step 3 reads 30. | pass (scripted 2026-10-03) |
| DICT-04 | P1 | script | Every command answers with the same state blob (the state blob). | App running. | 1. Run `state`, `tune to "channel:1"`, `show pane "live"` and `open catalog` in turn.<br>2. Compare the replies' shape. | All four return the same ~2.7KB JSON object. | pass (scripted 2026-10-03) |
| DICT-05 | P1 | script | Argument errors name the valid values (errors). | App running. | 1. `open catalog showing "search"`.<br>2. `filter explore genres {"nonsense"}`.<br>3. `seek to 1800` on a channel. | `-1703` naming explore/schedule/saved; `-1703` naming `browse genre "Kosmische"`; `-1708` naming the continuous streams. | pass (scripted 2026-10-03) |
| DICT-06 | P1 | script | Parameters are type-checked before the command runs (errors). | An episode tuned. | 1. `seek to "half"`.<br>2. `seek to true`.<br>3. Read `position` after each. | Both raise `-1700`; `position` does not jump to 0. | pass (scripted 2026-10-03) |
| DICT-07 | P1 | script | Opening a show does not report its episodes (automation gaps) — **B-01**. | Explore showing. | 1. `open show "anz"`.<br>2. Read `catalogDetail`, `catalogRows`, `catalogFirstRows`. | `catalogDetail: "show:anz"`; rows still Explore's. Record. | pass (scripted 2026-10-03; confirms B-01) |
| DICT-08 | P2 | script | All thirteen properties besides `state` read individually (the eleven properties). | Something playing. | 1. `get` each of the thirteen in turn. | All return a value; none errors. | pass (scripted 2026-10-03) |
| DICT-09 | P2 | script | Addressing a quit app launches it (edge cases). | App not running. | 1. `osascript -e 'tell application "NTS Radio" to get state'`. | The app launches and answers. | pass (scripted 2026-10-03) |
| DICT-10 | P2 | script | The six writable properties are writable; the other seven are not (the eleven properties). | App running. | 1. `set muted to true`.<br>2. `set auto checks for updates to true`.<br>3. Attempt `set playing to true`.<br>4. Attempt `set source to "channel:1"`. | The first two succeed; the last two error. | pass (scripted 2026-10-03) |

Not checkable by hand:

- Whether the `.sdef` descriptions render well in Script Editor's browser is a judgement, not a pass/fail (open questions).

## foundations/the-account.md

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ACCT-01 | P1 | signed-out | Signed out, the tracklist drawer is empty for a live source (what signing in changes). | Signed out. | 1. Tune NTS 1.<br>2. Open the drawer. | `No tracklist available`. | — |
| ACCT-02 | P1 | signed-out | Signed out, an episode's tracklist still appears (what signing in changes). | Signed out. | 1. Tune an episode with a known tracklist.<br>2. Open the drawer. | Rows are listed. | — |
| ACCT-03 | P2 | signed-out | Signed out, a mixtape's subtitle is the static descriptor (the two lines of text). | Signed out. | 1. Tune a mixtape.<br>2. Read the now-playing subtitle. | `24/7 STREAM · NON-STOP`. | — |
| ACCT-04 | P1 | supporter | Signed in as a Supporter, a live tracklist populates (what signing in changes). | Signed in, Supporter. | 1. Tune NTS 1, wait 10s.<br>2. Read `trackCount` and `currentTrack`. | Non-zero count, a real artist and title. | pass |
| ACCT-05 | P1 | free-account | A signed-in non-Supporter sees an empty tracklist with no explanation (modifiers) — **B-02**. | Signed in without a subscription. | 1. Tune NTS 1, wait 20s.<br>2. Open the drawer.<br>3. Open Settings ▸ Account. | Record exactly what each shows. Expected per the document: `No tracklist available` and an email address with no subscription state. | blocked — no free account |
| ACCT-06 | P2 | free-account | A non-Supporter's mixtape subtitle behaviour (the two lines of text). | Signed in without a subscription. | 1. Tune a mixtape, wait 20s.<br>2. Read the subtitle. | Record. The document predicts `TUNING IN…` persisting, which would be a second symptom of B-02. | blocked — no free account |
| ACCT-07 | P2 | free-account | Playback is unaffected without a subscription (what signing in changes). | Signed in without a subscription. | 1. Play a channel, a mixtape and an episode. | All three play. | blocked — no free account |
| ACCT-08 | P3 | free-account | Saving works without a subscription (what signing in changes). | Signed in without a subscription. | 1. Star a show.<br>2. Check nts.live in a browser. | The follow appears on the website. | blocked — no free account |
| ACCT-09 | P1 | supporter | Saved items sync two ways (saved items and the account). | Signed in, a browser open on nts.live. | 1. Star a show in the app.<br>2. Reload nts.live and check the follows.<br>3. Follow a different show on the website.<br>4. Relaunch the app and open Saved. | Both appear in both places. | — |
| ACCT-10 | P1 | mouse | The gear carries a green dot when signed in (summary). | Signed in. | 1. Open the window and look at the title bar's gear. | A green dot. | — |
| ACCT-11 | P2 | offline | An offline launch stays signed in (edge cases). | Signed in. | 1. Quit, turn Wi-Fi off, launch.<br>2. Read `signedIn`. | `true`. | — |
| ACCT-12 | P2 | keyboard | ⌘V works in the sign-in fields (modifiers). | Signed out, Settings ▸ Account open. | 1. Copy text.<br>2. Click the email field, press ⌘V. | The text is pasted. | — |
| ACCT-13 | P2 | mouse | No command reaches the account (driven by script). | — | 1. Read the dictionary in Script Editor. | No sign-in, sign-out or account command. | pass |

Not checkable by hand:

- How a two-way sync conflict resolves (open questions).
- Whether the sign-in fields support autofill and the password manager, without a stored credential to test against.
