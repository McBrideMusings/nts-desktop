# Verification: cross-cutting

How to run this file: the offline items need Wi-Fi genuinely off at the menu bar, not a proxy — and they need patience, because a live source plays on for about 5 seconds after a disconnect and an episode for about 14 minutes. The caching items mostly need a `clean` machine, which is the repo's biggest verification blocker: either a second Mac, or moving `~/Library/Application Support` for the app aside and putting it back afterwards. The keyboard items run anywhere. Results already filled in came from the scripted pass of 2026-08-27.

## cross-cutting/offline-and-outages.md

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| OFF-01 | P1 | offline | The banner names the consequence in plain words, not the endpoint (what an outage is). | App running, window open. | 1. Turn Wi-Fi off.<br>2. Wait for the schedule poll (up to 60s).<br>3. Read the banner. | `No connection` over `the schedule may be out of date`. No URL, no error code. | — |
| OFF-02 | P1 | offline | The headline distinguishes offline from NTS not answering (what an outage is). | — | 1. With Wi-Fi off, note the headline.<br>2. If an NTS 5xx can be induced, note it then. | `No connection` and `NTS isn't answering` respectively. | — |
| OFF-03 | P1 | offline | An outage clears only when its own endpoint succeeds (clearing). | A schedule outage showing. | 1. Turn Wi-Fi on.<br>2. Watch the banner without touching anything. | It persists until the next schedule poll succeeds — up to 60s, not instantly. | — |
| OFF-04 | P1 | offline | A second failing endpoint replaces the first (edge cases) — **B-14**. | Wi-Fi off, a schedule outage showing. | 1. Press play on an episode.<br>2. Read the banner. | It changes to `this episode wouldn't start`; the schedule outage is gone though still true. | — |
| OFF-05 | P1 | offline+supporter | The Firestore tracklist drops silently (modifiers) — **B-09**. | Signed in as a Supporter, NTS 1 playing, drawer open with rows. | 1. Turn Wi-Fi off.<br>2. Wait 5 minutes.<br>3. Read the drawer and the banner. | Record. Expected: rows frozen, no banner about the tracklist, nothing marking it stale. | — |
| OFF-06 | P1 | offline | The account sync fails silently (edge cases) — **B-09**. | Signed in, Wi-Fi off. | 1. Relaunch the app.<br>2. Watch for a banner. | Record. Expected: none. | — |
| OFF-07 | P2 | offline | The banner cannot be dismissed and has no retry (cancel and interrupt). | A banner showing. | 1. Click it. 2. Press Escape. 3. Look for a retry control. | Nothing dismisses it; no retry. | — |
| OFF-08 | P2 | offline | The banner survives every pane change (cancel and interrupt). | A banner showing. | 1. Switch pane, open the drawer, open a detail. | The banner stays above the now-playing bar throughout. | — |
| OFF-09 | P2 | script | The blob carries a `detail` field the banner does not show (driven by script). | An outage showing. | 1. Read `outage`.<br>2. Compare with the banner. | Five fields including `detail`, whose text is not on screen. | — |
| OFF-10 | P2 | offline | An episode failure is reported twice, in two wordings (interactions) — **B-17**. | Wi-Fi off. | 1. Play an episode.<br>2. Read the banner and the now-playing subtitle. | Two different sentences about one failure. | — |
| OFF-11 | P2 | offline | An outage does not survive a relaunch (cancel and interrupt). | A banner showing, Wi-Fi still off. | 1. Quit and relaunch.<br>2. Look for the banner immediately. | Absent until something next fails. | — |
| OFF-12 | P1 | offline | Search still works with no network (what still works offline). | Warm machine. | 1. Quit, Wi-Fi off, launch.<br>2. Search for a known show. | Full results from disk. | — |
| OFF-13 | P2 | offline | Explore breaks offline in a way the other surfaces do not (what still works offline). | Warm machine, Wi-Fi off, app relaunched. | 1. Open Explore. | Empty, unlike the dial, schedule and search which are all populated. | — |

## cross-cutting/first-launch-and-caching.md

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CACHE-01 | P1 | clean | The very first launch is the only empty one (the very first launch). | No Application Support data for the app. | 1. Launch, open the window within 2s.<br>2. Photograph the dial, the schedule and the search count line.<br>3. Repeat at 10s, 30s, 60s. | An empty dial and schedule filling in; the search line counting up from near zero. **Time each.** | blocked — needs a clean machine |
| CACHE-02 | P1 | clean | The backfill crawl takes minutes, and search improves throughout (why the crawl runs once). | A clean machine, just launched. | 1. Poll `showIndex` every 30s until `running: false`.<br>2. Note the elapsed time and the final `named`/`remaining`. | The crawl completes; measure how long against the ~8-minute arithmetic estimate. | blocked — needs a clean machine |
| CACHE-03 | P1 | mouse | A warm launch is populated before any request could return (summary). | A warm machine. | 1. Quit, Wi-Fi off, launch.<br>2. Open the window within 2s. | Dial, schedule and search all populated. | — |
| CACHE-04 | P1 | script | The tuned source is never remembered (edge cases). | Something playing. | 1. Quit, relaunch, read `source`. | `idle`. | — |
| CACHE-05 | P1 | script | Preferences persist but Explore's results do not (confirmed). | A mood set, several Explore pages loaded. | 1. Quit and relaunch.<br>2. Read `exploreMood` and `exploreLoaded`. | The mood persists; loaded is back to 12. | pass |
| CACHE-06 | P2 | mouse | Slot artwork survives a relaunch (what is cached). | Schedule scrolled through a distant day so its rows filled. | 1. Quit and relaunch.<br>2. Return to that day. | Rows are already dressed, with no fetch. | — |
| CACHE-07 | P2 | offline | A failed refresh keeps the cached copy (cancel and interrupt). | Warm machine, Wi-Fi off. | 1. Launch and wait past a schedule poll.<br>2. Check the schedule. | Still populated, with a banner — not cleared. | — |
| CACHE-08 | P2 | mouse | Opening a show by hand does the crawl's work for it (why the crawl runs once). | A machine mid-crawl. | 1. Note `remaining`.<br>2. Open an uncrawled show's detail.<br>3. Note `remaining` again. | Down by one. | blocked — crawl complete here |
| CACHE-09 | P2 | mouse | The search scope line changes wording once the crawl stops (the line under the field). | A machine with stragglers, crawl finished. | 1. Read the line under the search field. | `NAMES DIDN'T LOAD`, not `STILL LOADING NAMES`. | — |
| CACHE-10 | P2 | mouse | Slot artwork is written on quit (cancel and interrupt). | Schedule scrolled so new rows filled. | 1. Quit immediately after the rows fill.<br>2. Relaunch and return to that day. | Rows still dressed — the write survived the quit. | — |
| CACHE-11 | P3 | — | The caches are recoverable only by hand (interactions) — **B-15**. | — | 1. Look for any in-app control that clears or rebuilds any cache. | None. | — |

Not checkable by hand:

- Whether a corrupt cache file is handled gracefully or crashes the launch, without deliberately corrupting one (open questions).

## cross-cutting/keyboard-and-focus.md

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| KEY-01 | P1 | keyboard | Escape does nothing anywhere (Escape does nothing, anywhere) — **B-16**. | Window open, something playing. | 1. Press Escape with the drawer open.<br>2. With a detail open.<br>3. With a query typed.<br>4. With the genre drawer open.<br>5. With nothing open. | Nothing closes or clears at any step. Record each. | — |
| KEY-02 | P1 | keyboard | The four shortcuts are the whole set (the four shortcuts). | Show in Dock on, app frontmost. | 1. Read every item in the App and Edit menus. | ⌘,, ⌘W, ⌘H, ⌘Q, plus the standard Edit set. Nothing for playback. | — |
| KEY-03 | P1 | keyboard | No shortcut touches playback (interactions). | Something playing, app frontmost. | 1. Try ⌘P, Space, ⌘→, ⌘M. | None affects playback. | — |
| KEY-04 | P1 | script+keyboard | A scripted command does not steal focus (nothing takes focus). | A text editor frontmost, caret in a document, NTS window closed. | 1. Type continuously.<br>2. From another terminal run `open window`, then `tune to "channel:1"`, then `open catalog`.<br>3. Keep typing without pausing. | Every keystroke lands in the editor. The NTS window appears and changes behind it. | — |
| KEY-05 | P2 | keyboard | Tab does not move between controls (release without dragging). | Radio window key. | 1. Press Tab repeatedly, watching for a focus ring. | Nothing focuses. | — |
| KEY-06 | P2 | keyboard | There is no shortcut to summon the window (edge cases). | Window dismissed. | 1. Read the App menu for a show-window item. | None. The menu-bar icon or a script is the only route. | — |
| KEY-07 | P2 | keyboard | ⌘W closes whichever window is key (edge cases). | Both windows open. | 1. With Settings key, press ⌘W.<br>2. With the radio window key, press ⌘W. | Each closes the key window only. | — |
| KEY-08 | P2 | keyboard | The search field needs a click; there is no ⌘F (edge cases). | Catalog open. | 1. Press ⌘F.<br>2. Type. | Nothing focuses; the text goes nowhere. | — |
| KEY-09 | P2 | keyboard | The media keys work without focus (cancel and interrupt). | NTS 1 playing, another app frontmost, NTS window closed. | 1. Press the play/pause key. | It reaches NTS Radio. | — |
| KEY-10 | P3 | keyboard | ⌘V works in the sign-in fields (modifiers). | Settings ▸ Account, signed out. | 1. Copy text, click the email field, ⌘V. | Pasted. | — |

Not checkable by hand without an accessibility pass:

- **The whole of VoiceOver, Reduce Motion, Increase Contrast and Dynamic Type.** No document in this repo has assessed any of it, and the facts gathered while writing them — no Tab navigation, no keyboard targets, state conveyed by motion in both the menu-bar icon and the level meter — are enough to expect problems and not enough to name them. This wants its own pass with its own checklist, and none exists yet. See bug-triage.md.
