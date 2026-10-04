# Hand verification

**264 claims about how this app behaves**, one per row, precise enough to tell pass from fail. Use them as a lookup while verifying a change, or as a regression sweep when a change is broad enough to warrant one.

They came out of a product-description pass over the whole app in August 2026: 27 documents written from the code, then driven against the installed build. The 65 rows whose Device includes `script` carry a machine-readable check, and `admin verify` runs them and writes their Result (see **Running the scripted rows**). The rest need a person and are marked `—` until someone runs them.

The machine-specific side of verification — how to build, install and get a handle on the app — is `.claude/skills/verify-project/SKILL.md`, which is deliberately untracked. This directory is the part that is true on any machine.

**Results are recorded in place.** Fill the Result column when you run something. If a claim turns out to be wrong, the row is what is wrong — fix it, and say so.

## What is here

| File | Covers |
| --- | --- |
| [foundations.md](foundations.md) | `foundations/*` |
| [playing.md](playing.md) | `playing/*` and `live/*` |
| [catalog.md](catalog.md) | `catalog/*` |
| [system.md](system.md) | `system/*` |
| [cross-cutting.md](cross-cutting.md) | `cross-cutting/*` |

Each file has one table per document. Each row is an item with a stable ID, a priority, what it needs, the claim with a link to the document section, the setup, numbered steps, the expected result, and a Result column. Items that cannot be checked by hand are listed under each document as "Not checkable by hand".

**Priorities.** **P1** is an established fact, a claim many documents depend on, or a suspected bug. **P2** is an ordinary claim. **P3** is a number, a colour, or a timing.

## How to run a pass

1. **Bring up the surface.** Run `admin deploy`. It quits any running instance, installs a clean build, relaunches it, and returns only once the app answers `get state`. Note what that gives you — see **What the local build is not** below.
2. **Confirm the commit.** Every document ends `Verified against nts-desktop commit 05e3b3f`. Run `git -C <repo> rev-parse --short HEAD`; if it differs, the documents describe a different build and some failures will be drift rather than defects. Say so in the note rather than filing them.
3. **Keep the documents open beside the app.** Read the linked section before each item — the item is a summary, the section is the claim.
4. **Run the scripted rows first:** `admin verify P1`, then `P2`, then `P3`. Then work the remaining rows by hand in the same order.
5. **Record `pass`, `fail`, or `blocked`** in the Result column, with a note for anything other than a clean pass. A fail is something the document says that the app does not do. A blocked item could not be run — no second account, no clean machine, a prior failure in the way.
6. **File every fail** as a [GitHub issue](https://github.com/McBrideMusings/nts-desktop/issues), quoting the item ID in its body; if an issue already covers it, comment there with the ID instead. **A fail is not automatically a product bug** — sometimes the document is wrong, and the fix is to the document. Say which.
7. **When every P1 and P2 item for a document has passed or been filed**, change its row in the coverage table from `drafted` to `verified`.

## Conditions the Device column uses

- **`mouse`** — a real pointer. Required for every drag, hover and click claim; none of these can be driven by script, which is the point of them.
- **`keyboard`** — real keystrokes. The app has four shortcuts and two text fields; nothing else has a keyboard target.
- **`script`** — `admin state` / `admin drive`, which wrap `osascript`. See below.
- **`offline`** — Wi-Fi off at the menu bar, not a proxy or a devtools toggle. A proxy can leave an in-flight connection alive; the app's buffer figures mean a live source keeps playing for about 5 seconds and an episode for about 14 minutes after a real disconnect, so **wait long enough**.
- **`supporter`** — the paid NTS Supporters account. The machine these documents were written against has one.
- **`free-account`** — a signed-in NTS account **without** a subscription. This does not exist on the verification machine and is the single most valuable condition to obtain: B-02 cannot be checked without it, and three documents' account rows are unverified for the same reason.
- **`signed-out`** — the app's stated default surface. Reaching it means signing out of a real session, so plan it as its own pass rather than mid-flow.
- **`clean`** — a machine with no Application Support data for the app. Needed for every first-launch claim, and unobtainable without either a second Mac or moving the app's support directory aside.
- **`release`** — a copy installed from a GitHub Release or the Homebrew tap, not from `admin deploy`. Needed for anything about updating.
- **`sleep`** — actually sleeping the Mac, not locking the display.

## Driving the app from a script

The app has an AppleScript dictionary that both acts and reports, and one call returns everything:

```
admin state
```

`admin drive <verb> [args]` runs any other command in the dictionary and prints the state it answers with — `admin drive tune channel:1`, `admin drive pane tracks`. Bare `admin drive` lists the verbs. Both wrap `osascript`; [`docs/automation.md`](../automation.md) has the raw form.

**Use it to set up a state exactly and to read state back after a real interaction. Do not use it to perform an interaction the item is about.** An item marked `mouse` is a claim about what a pointer does; driving it with `tune to` proves the command works and says nothing about the click.

What the script surface cannot do:

- **It cannot gesture.** There is no way to drag the seek bar, hover the dial, or scroll the timeline from a script.
- **It cannot see the menu-bar icon.** The icon owns no window and answers no property. Checking it means a menu-bar screenshot and a pixel scan.
- **It cannot read a list.** `catalogFirstRows` gives three display strings and `currentTrack` gives one; the rest is not exposed (B-01).
- **It launches the app.** Addressing a quit app starts it, so there is no way to observe a not-running app.
- **`set volume to N` does not work** — write `set its volume to N` (B-03).

## Running the scripted rows

```
admin verify                  # every check, P1 first
admin verify P1               # one priority
admin verify PLAY-05 EXP-01   # named rows
```

Every row whose Device includes `script` has a line in `mac/verify/<file>.tsv`, keyed by its ID: a list of `admin drive` verbs to run, and a `jq` predicate over the array of their replies that must come out true. `mac/verify/run.py`'s header documents the step vocabulary — besides the drive verbs, raw AppleScript, `sleep`, `until` (poll `get state` until a predicate holds), `await` (the same, but a timeout blocks the row rather than failing it), `relaunch`, `frontmost`, `dictionary` and `require`.

Before each row the runner returns the app to idle with the catalog and the radio window closed. After the run it restores every preference a row can change — volume, mute, update checks, track lead, Explore's filters, the catalog tab and the schedule channel. It rewrites each Result cell it ran as `pass (scripted <date>)`, `fail (scripted <date>)` or `blocked (scripted <date>) — <requirement>`, and keeps the replies from each row's last run in `tmp/claude/verify/checklist.json`, so a fail can be read without rerunning it. It exits 1 when any row fails or a preference could not be restored.

**What the runner never does:** drive `save`, which writes to the NTS account, or anything that brings the app to the front — `check for updates` does, through Sparkle's dialog. `open settings` does not: like `open window`, it puts the window on screen without activating the app, and the runner closes Settings before every row. A run never takes focus from whoever is typing. A row in the TSV whose steps read `manual` names, in its check column, what the state would have to report for a script to decide it. Rows whose Device does not include `script` have no line at all.

**`tune to` plays real audio**, at whatever volume the app is set to.

## What the local build is not

The machine these documents were verified against runs an `admin deploy` build, and that differs from what a user has in ways that matter to a pass:

- **It carries `CFBundleVersion: 1`**, so automatic update checks are suppressed. Every update claim needs a `release` copy.
- **It is signed with a local Apple Development identity**, so nothing about Gatekeeper or the disk image can be checked from it.
- **It is signed in as a Supporter** with 27 saved items and a `sedative` explore mood — the wrong state for every signed-out claim and the right one for every tracklist claim.

## Results so far

**`admin verify`, 2026-10-03, against the installed `admin deploy` build**, over all 65 rows with a check, with EXP-07, CACHE-05 and KEY-04 re-run, and SET-05 scripted, on 2026-10-04:

- **60 pass.** KEY-04 failed once on 2026-10-03 (`open window` answered `windowVisible: false` after `filter explore`) and has not failed since, on that day's build or a later one; `app.log` now records the window's state either side of every scripted open and close, so a repeat says why.
- **1 blocked.** OFF-09 needs an outage to be showing.
- **4 manual.** SAVE-01 and SAVE-02 drive `save`; UPD-03 would bring the app to the front; PLAY-12 has no field that records a reconnect.

The first pass, 2026-08-27 against commit `05e3b3f`, drove the same build entirely through `osascript` by hand and produced five corrections to the documents.

**What no scripted pass can cover:**

- **Anything a pointer does.** Every drag, hover, click target, tooltip and cursor claim.
- **Anything visible.** Layout, colour, animation, the three window-width degradation steps, the menu-bar icon in any state, whether any error text is legible or truncated.
- **Anything timed below a second.** The 0.2s seek-bar reveal, the 0.4s slot advance and the 25fps waterline. The held-track delay is within reach: TRK-01 polls once a second and caught it.
- **Every keyboard claim**, including the four shortcuts and whether Escape does anything in the settings window.
- **The signed-out surface**, which is what the documents describe as the default.
- **The free-account surface**, which is where B-02 lives.
- **First launch on a clean machine** — the most valuable unverified area in the repo.
- **Installing, Gatekeeper, and updating.**
- **Accessibility**, which no document has assessed at all.

**No document is marked `verified`.** A scripted pass is not sufficient on its own, and every document has at least one P1 or P2 item that needs a mouse, a pair of eyes, or a condition this machine does not have.
