# Verification: catalog

How to run this file: install and launch a clean build per the protocol, open the catalog pane. **Clear the query between sections** — a standing query overrides every tab's rows (B-04) and will silently invalidate the tab items. Do that with `open catalog searching for ""`, not `open catalog`, which also clears the detail. Several items need the schedule's own clock, so check `onAir` and `nextUp` before starting to find a boundary you can wait for. Results already filled in came from the scripted pass of 2026-08-27.

## catalog/explore.md

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| EXP-01 | P1 | script | A filter change clears the grid and restarts from page one (release without dragging). | Explore with several pages loaded. | 1. Read `exploreLoaded` (should be >12).<br>2. `filter explore mood "sedative"`.<br>3. Read again. | Back to 12. | pass (scripted 2026-10-04) |
| EXP-02 | P1 | mouse | Scrolling to the last card fetches the next twelve (the simple case). | Explore, freshly filtered. | 1. Read `exploreLoaded`.<br>2. Scroll to the bottom of the grid.<br>3. Read again. | Increased by 12; no button was pressed. | — |
| EXP-03 | P1 | script | An unknown genre id is refused, not applied (driven by script). | Explore showing. | 1. `filter explore genres {"nonsense"}`. | Error `-1703` naming `browse genre "Kosmische"`. The grid is unchanged. | pass (scripted 2026-10-03) |
| EXP-04 | P1 | script | `browse genre` clears every other filter (driven by script). | Explore with a mood and two genres set. | 1. `browse genre "Kosmische"`.<br>2. Read `exploreMood`, `exploreGenres`. | Mood empty; genres exactly the one. | pass (scripted 2026-10-04) |
| EXP-05 | P1 | mouse | Playing a card leaves Explore exactly as it was (release without dragging). | Explore with 3+ pages loaded, scrolled down. | 1. Note the scroll position and `exploreLoaded`.<br>2. Click a card to play it.<br>3. Look at the grid. | Same filters, same loaded count, same scroll position. | — |
| EXP-06 | P2 | mouse | Mood is exclusive; genres accumulate (the four filters). | Genre drawer open. | 1. Pick mood A, then mood B.<br>2. Pick genre X, then genre Y.<br>3. Pick mood B again. | Only B is set after step 1; both X and Y after step 2; no mood after step 3. | — |
| EXP-07 | P2 | script | Filters persist across a relaunch (confirmed). | A mood and a genre set. | 1. Quit and relaunch.<br>2. Read `exploreMood` and `exploreGenres`. | Both as set. | pass (scripted 2026-10-04) |
| EXP-08 | P2 | offline | A filter change while offline empties the grid unrecoverably (modifiers). | Explore loaded, then Wi-Fi off. | 1. Change a filter.<br>2. Try to clear the filter. | The grid is empty and stays empty until the network returns. | — |
| EXP-09 | P2 | offline | A failed page shows nothing in the grid (open questions) — **B-13**. | Explore loaded, Wi-Fi off. | 1. Scroll to the last card.<br>2. Watch the grid and the bottom of the window. | Record. Expected: no rows appear, nothing in the grid says why, banner at the bottom. | — |
| EXP-10 | P3 | script | The total is far larger than what is loaded (confirmed). | Explore, no filters. | 1. Read `exploreLoaded` and `exploreTotal`. | 12 against a total of at least 1,000. | pass (scripted 2026-10-03) |

## catalog/the-genre-drawer.md

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GEN-01 | P1 | mouse | Only one primary is expanded at a time (why one primary at a time). | Genre drawer open. | 1. Expand primary A.<br>2. Expand primary B. | A collapses as B expands. | — |
| GEN-02 | P1 | mouse | Selections survive collapsing (why one primary at a time). | Genre drawer open. | 1. Expand A, select a subgenre.<br>2. Expand B.<br>3. Look for the selection's chip. | The chip is still shown outside the drawer; the filter still applies. | — |
| GEN-03 | P2 | mouse | Each selection restarts the grid separately (release without dragging). | Explore, network inspector or `exploreLoaded` polling running. | 1. Select four genres in quick succession.<br>2. Watch `exploreLoaded`. | It resets to 12 four times. Record whether four searches are actually issued. | — |
| GEN-04 | P1 | script | The whole genre list is settable in one call (driven by script). | Explore showing. | 1. `filter explore genres {"ambientnewage", "ambientnewage-kosmiche"}`.<br>2. Read `exploreGenres`. | Both ids present. One search, not two. | pass (scripted 2026-10-04; one search versus two is not reported) |
| GEN-05 | P2 | offline | An offline launch has no genres to pick from (modifiers). | Wi-Fi off before launching. | 1. Launch, open Explore, open the genre drawer. | The list is empty. | — |
| GEN-06 | P2 | script | The drawer's own state is not reported (confirmed). | Genre drawer open. | 1. Read the whole blob. | No field for the drawer being open or which primary is expanded. | pass (scripted 2026-10-03) |

Not checkable by hand:

- Whether a subgenre and its primary can both be selected, and what that does to a Focused search's genre count (open questions).

## catalog/search.md

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SRCH-01 | P1 | script | A query overrides the selected tab's rows while the chip still names the tab (the odd state) — **B-04**. | Saved tab with items. | 1. `open catalog showing "saved"`, read `catalogRows`.<br>2. `open catalog searching for "veronica"`, read `catalogTab` and `catalogRows`.<br>3. Look at the tab chip on screen. | Rows become the search results; `catalogTab` still `saved`; the chip on screen still reads SAVED. | pass (scripted 2026-10-03; script half; the chip on screen needs eyes) |
| SRCH-02 | P1 | mouse | Results update as you type, with no submit (release without dragging). | Catalog open. | 1. Click the search field.<br>2. Type `ver`, then `on`, then `ica`, pausing between. | The result list narrows at each pause without pressing Enter. | — |
| SRCH-03 | P1 | offline | Search works entirely offline (modifiers). | Warm machine. | 1. Quit, Wi-Fi off, launch.<br>2. Search for a known show. | Full results. | — |
| SRCH-04 | P1 | script | `open catalog` with no query argument clears the query (driven by script) — **B-10**. | A query set. | 1. `open catalog searching for "kosmische"`, read `catalogQuery`.<br>2. `open catalog`, read again. | `"kosmische"` then `""`. | pass (scripted 2026-10-03) |
| SRCH-05 | P1 | mouse | Search matches a host's name inside a show title (what is searched). | Catalog open. | 1. Search `veronica`. | `Minimal Wave w/ Veronica Vasicka` is returned. | pass |
| SRCH-06 | P2 | mouse | Search matches a genre (what is searched). | Catalog open. | 1. Search `kosmische`. | Several shows tagged Kosmische. | pass |
| SRCH-07 | P2 | mouse | Folding lets a punctuation-free query match a punctuated name (how matching works). | Catalog open. | 1. Search `pussyrap`. | `PU$$YRAP W/ JODY SIMMS` is returned. | — |
| SRCH-08 | P2 | mouse | Name matches outrank description-only matches (ranking). | Catalog open. | 1. Search a single common first name.<br>2. Read the first five results. | Shows with the name in their title come before shows that only mention it. | — |
| SRCH-09 | P2 | mouse | The scope line states what was searched (the line under the field). | Catalog open. | 1. Read the line under the search field. | `N MIXTAPES · N SCHEDULED · N SHOWS`, plus a backfill clause if any remain. | — |
| SRCH-10 | P2 | mouse | Search does not match episode titles or track names (edge cases). | Catalog open. | 1. Search for a known episode title that is not a show name.<br>2. Search for a track artist. | Neither returns the episode or the track. | — |
| SRCH-11 | P2 | script | Results are not addressable (driven by script) — **B-01**. | A query with results. | 1. Read `catalogFirstRows`. | Display strings only; no aliases to pass to `tune to`. | pass (scripted 2026-10-03) |
| SRCH-12 | P2 | mouse | Leaving the catalog discards the query (cancel and interrupt). | A query set. | 1. Press LIVE.<br>2. Press the catalog segment. | The query is gone and the tab's own rows are back. | pass |

## catalog/saved.md

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SAVE-01 | P1 | script | `save` is a toggle, so twice unsaves (driven by script) — **B-08**. | App running. | 1. Read `savedCount` and `savedKeys`.<br>2. `save "anz"`, read.<br>3. `save "anz"`, read. | Up by one with `show:anz` first in `savedKeys`, then back to the original. Record. | — |
| SAVE-02 | P1 | script | `save` does not validate its alias (driven by script) — **B-11**. | App running. | 1. `save "not-a-real-show-xyz"`.<br>2. Open the Saved tab. | No error; a row appears titled from the alias. Record. **Unsave it afterwards.** | — |
| SAVE-03 | P1 | mouse | New items go to the top (the simple case). | Saved tab with items. | 1. Star a new show.<br>2. Open Saved. | It is the first row. | — |
| SAVE-04 | P1 | mouse | A show and an episode of it are separate saved things (the three kinds). | A schedule row with both glyphs. | 1. Star the show.<br>2. Star the episode.<br>3. Open Saved. | Two rows, one labelled SHOW and one EPISODE. | — |
| SAVE-05 | P1 | mouse | A row with no aliases cannot be saved (what can and cannot be saved). | Schedule scrolled to the furthest-out day. | 1. Find a row with no show alias (compare `slotsWithShow` against `slots`).<br>2. Look for its stars. | No star, rather than a star that fails. | — |
| SAVE-06 | P2 | offline | A star made offline is kept and pushed later (modifiers). | Signed in, Wi-Fi off. | 1. Star a show.<br>2. Turn Wi-Fi on, wait for a sync.<br>3. Check nts.live in a browser. | The follow appears on the website. | — |
| SAVE-07 | P2 | mouse | Signing out does not delete local saved items (edge cases). | Signed in with saved items. | 1. Note `savedCount`.<br>2. Sign out.<br>3. Read it again. | Unchanged. | — |
| SAVE-08 | P2 | script | No command lists or unsaves (driven by script). | — | 1. Read the dictionary. | `save` only; no list, no unsave. | pass (scripted 2026-10-03) |
| SAVE-09 | P3 | mouse | A schedule-saved show keeps the broadcast subtitle it had then (edge cases). | — | 1. Star a show from a schedule row.<br>2. Open Saved and read its subtitle. | `NTS 1 · 09:00 – 11:00` — a broadcast time, not a property of the show. | — |

## catalog/the-schedule-timeline.md

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SCHD-01 | P1 | mouse | The list opens anchored on what is on air, a fifth down (the simple case). | Catalog closed. | 1. Open the catalog on the Schedule tab.<br>2. Look at where the on-air row sits. | Marked ON AIR, about a fifth down the visible area, with the previous programme readable above. | — |
| SCHD-02 | P1 | mouse | Switching channel re-anchors (one channel at a time). | Schedule tab, scrolled several days ahead. | 1. Switch to the other channel. | The list jumps back to that channel's on-air programme. | — |
| SCHD-03 | P1 | mouse | The list advances at a boundary without input (cancel and interrupt). | A boundary within 10 minutes (check `nextUp`). | 1. Leave the Schedule tab open, untouched.<br>2. Watch across the boundary. | The finished programme drops off; the next takes the ON AIR badge, animated. | — |
| SCHD-04 | P1 | mouse | The NOW rule sits in a gap rather than the grid looking broken (the clock is drawn twice). | Find a gap in the grid (a day with fewer slots). | 1. Scroll to a gap.<br>2. Look for the rule when the clock is in one. | The rule marks the current minute inside the gap. | — |
| SCHD-05 | P1 | mouse | The ON AIR badge tunes the channel (the simple case). | Schedule tab, nothing playing. | 1. Click the ON AIR badge. | That channel starts playing. | — |
| SCHD-06 | P1 | mouse | A future row opens its show rather than playing (release without dragging). | Schedule tab. | 1. Click a row two days ahead. | The show's detail opens. Nothing plays. | — |
| SCHD-07 | P2 | mouse | Rows fill with artwork as they scroll into view (slot artwork). | Schedule tab, a day never visited. | 1. Scroll to it quickly.<br>2. Watch the rows for 10s. | Rows arrive blank and fill in, a few at a time rather than all at once. | — |
| SCHD-08 | P2 | offline | A row that failed retries on a second scroll past (slot artwork). | Wi-Fi off. | 1. Scroll to an unvisited day; rows stay blank.<br>2. Wi-Fi on.<br>3. Scroll away and back. | The rows fill in on the second pass. | — |
| SCHD-09 | P1 | script | An invalid channel is refused (driven by script). | — | 1. `open catalog showing "schedule" channel 3`. | Error `-1703`: `NTS 3 is not a channel. Use 1 or 2.` | pass (scripted 2026-10-05) |
| SCHD-10 | P2 | script | The schedule spans 8 or more days at up to 17 slots each (confirmed). | — | 1. Read `scheduleDays`. | At least 8 entries, each with a count from 1 to 17; the first and last days are partial. | pass (scripted 2026-10-05) |
| SCHD-11 | P2 | mouse | Day headers pin as they pass under the top edge (summary). | Schedule tab. | 1. Scroll slowly through a day boundary. | The header sticks at the top until the next day pushes it up. | — |
| SCHD-12 | P3 | mouse | `YESTERDAY` never appears (edge cases) — **B-17**. | Schedule tab. | 1. Scroll to the very top of the grid.<br>2. Read the first day header. | `TODAY`, not `YESTERDAY`. Record if it ever shows. | — |

## catalog/show-detail.md

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SHOW-01 | P1 | script | The episode list is not reported (driven by script) — **B-01**. | Explore showing 12 rows. | 1. `open show "anz"`.<br>2. Read `catalogDetail`, `catalogRows`, `catalogFirstRows`, `detailTags`. | Detail and tags set; rows still Explore's. | pass (scripted 2026-10-05) |
| SHOW-02 | P1 | mouse | The pane draws what it has, then fills in (what it knows, and when). | A show never opened. | 1. Click it and watch for 3s. | Artwork and title at once; tags, blurb and episodes appear after. | — |
| SHOW-03 | P1 | mouse | Scrolling to the last episode pages twelve more (the simple case). | A show with 30+ episodes open. | 1. Note the count line.<br>2. Scroll to the last episode.<br>3. Note it again. | Up by twelve. | — |
| SHOW-04 | P2 | mouse | The count line drops "OF" once everything is loaded (the episode count). | A show with fewer than 24 episodes. | 1. Page to the end.<br>2. Read the count line. | A bare number, no `OF`. | — |
| SHOW-05 | P1 | mouse | Playing an episode leaves the pane open (release without dragging). | A show open with episodes. | 1. Click an episode. | It plays; the show's pane is still showing. | — |
| SHOW-06 | P2 | mouse | Reopening a show in the same session is instant (release without dragging). | A show opened once. | 1. Go back, open it again. | Blurb and episodes appear with no delay. | — |
| SHOW-07 | P2 | offline | A show that fails shows no error (cancel and interrupt) — **B-13**. | Wi-Fi off. | 1. Open a show never opened before.<br>2. Read `detailError`. | Record. Expected: title and maybe artwork, no blurb, no episodes, no error in the pane; `detailError` names the network failure. | — |
| SHOW-08 | P2 | mouse | Leaving the catalog discards the detail (cancel and interrupt). | A show open. | 1. Press LIVE, then the catalog segment. | A list, not the detail. | pass |
| SHOW-09 | P3 | keyboard | Escape does not close the detail (cancel and interrupt) — **B-16**. | A show open. | 1. Press Escape. | Nothing closes. | — |
| SHOW-10 | P1 | script | A show whose page fails says why (cancel and interrupt). | None. | 1. `open show "not-a-real-show"`.<br>2. Read `detailError` until it is set. | The reply carries `detailError: ""`; within 10s it reads "nts.live answered HTTP 404." and `detailTags` stays empty. | pass (scripted 2026-10-05) |

## catalog/episode-playback.md

| ID | P | Device | Claim | Setup | Steps | Expected | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| EP-01 | P1 | script | An episode resolves through two hops to a signed third-party playlist (the two hops). | Idle. | 1. `tune to "episode:anz/anz-25th-june-2026"`, wait 8s.<br>2. Read `episodeStream`, `episodeLoading`, `episodeError`. | A signed `sndcdn.com` or `mixcloud` playlist URL; loading false; error empty. | pass (scripted 2026-10-03) |
| EP-02 | P1 | mouse | The transport shows a loading state during the hops (what the listener sees). | Idle, window open. | 1. Click an episode and watch the now-playing bar. | Title `LOADING…`, subtitle `FINDING THE AUDIO…`, until audio starts. | — |
| EP-03 | P1 | offline | A failure leaves the reason on screen (what the listener sees). | Wi-Fi off. | 1. Click an episode.<br>2. Read both lines and `episodeError`. | Title `COULDN'T PLAY`; a reason in both the subtitle and the blob. | — |
| EP-04 | P1 | script | Tuning elsewhere mid-resolve discards the result (cancel and interrupt). | Idle. | 1. `tune to` an episode.<br>2. Within 1s, `tune to "channel:1"`.<br>3. Wait 10s, read `source`. | `channel:1`, still playing. The episode never starts. | pass (scripted 2026-10-03) |
| EP-05 | P2 | script | An unknown episode fails with an HTTP error, not an AppleScript error (driven by script). | Idle. | 1. `tune to "episode:anz/not-a-real-episode"`.<br>2. Wait 5s, read `episodeError`. | The command succeeds; `episodeError` reads `nts.live answered HTTP 404.` | pass (scripted 2026-10-03) |
| EP-06 | P1 | mouse | The seek bar appears once an episode loads (interactions). | A channel playing. | 1. Play an episode.<br>2. Watch above the transport. | The seek bar slides up. | — |
| EP-07 | P2 | mouse | An episode's tracklist is complete immediately and public (the tracklist arrives whole). | An episode with a tracklist playing. | 1. Open the drawer as soon as audio starts. | The whole list is already there. | — |
| EP-08 | P2 | mouse | Re-tuning the same episode starts at 0:00 (edge cases). | An episode playing at 20:00. | 1. Tune a channel.<br>2. Tune the same episode again.<br>3. Read `position`. | 0, not 1200. | — |
| EP-09 | P2 | mouse | A failed resolve leaves the previous audio playing (modifiers). | NTS 1 playing, Wi-Fi off. | 1. Click an episode.<br>2. Listen. | The channel keeps playing until its buffer runs out; the failure does not silence it early. | — |
| EP-10 | P3 | script | The episode buffer is far larger than a live source's (confirmed). | An episode playing 20s. | 1. Read `bufferSeconds`. | Several hundred seconds. | pass (scripted 2026-10-03) |

Not checkable by hand:

- Whether a second audio source is ever present on a real episode, making the first-only rule visible (open questions).
