---
name: verify-app
description: Prove a change to NTS Radio actually works by building it, installing it, driving the real app, and capturing pixels. Use for any verification of this repo's code — menu-bar behaviour, window UI, playback, catalog, settings. Use this instead of the bundled `verify` skill, which cannot be invoked programmatically.
---

# Verify — NTS Radio

Invoked as `verify-app`, not `verify`: the bundled `verify` skill is marked
`disable-model-invocation`, and that block is keyed to the **name**, so a
project skill called `verify` is refused too. The distinct name is what makes
this reachable from `implement`, `iterate`, and `orchestrate`.

**Verification is runtime observation.** Build the app, install it, drive it to where the changed code runs, capture what you see. That capture is the evidence.

**Don't run tests, don't typecheck, don't import-and-call.** This package has no test target anyway. A clean `swift build` is setup, not a step — it proves the compiler ran.

---

## 0. Preconditions — check these first, they cause silent wrong answers

### The display must be unlocked

A locked display makes `screencapture` write an **all-black PNG and exit 0**. Nothing fails; the answer is just wrong. This has cost multiple rounds.

```bash
python3 -c "
import Quartz
wins = Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly, Quartz.kCGNullWindowID)
shield = [w for w in wins if 'Shield' in str(w.get('kCGWindowName') or '')]
named  = [w for w in wins if w.get('kCGWindowName')]
print('shield:', shield or 'none', '| readable names:', len(named), '/', len(wins))"
```

- `Display 1 Shield` present → **locked**. Stop, ask the user to unlock.
- Shield absent but captures still black → **still possibly locked.** The shield window disappears once the login screen is fully up. The reliable tell is the menu bar's contents: if a crop shows only input source / keyboard / battery / wifi and no app menus, that's the login window.
- Readable window names ≈ total → Screen Recording permission is fine, so a black capture is *not* a permission problem.

**Hold the display awake before a long build**, because `admin install` takes long enough for an idle lock to land in between:

```bash
nohup caffeinate -i -m -d -u -t 1800 >/dev/null 2>&1 & echo $! > ~/.claude-tmp/caffeinate/manual-$!.pid
```

`caffeinate` *prevents* a lock. It cannot undo one.

### Only one instance may ever run

`CLAUDE.local.md` is strict about this. Always quit before launching, and never start a second `admin dev`:

```bash
osascript -e 'tell application "NTS Radio" to quit'
```

---

## 1. Get a handle

```bash
osascript -e 'tell application "NTS Radio" to quit'
admin install          # builds, signs with the Apple Development identity, replaces /Applications
open -a "/Applications/NTS Radio.app"
```

**Use the installed bundle, not `admin dev`.** A bare binary has no bundle identifier, so media keys and `UNUserNotificationCenter` don't work there. The status item also only appears when the bundle is properly signed — `admin install` handles that via `mac/codesign-local.sh`; look for `✓ codesigned NTS Radio.app` in the log.

Confirm it came up: `pgrep -lf NTSRadio`.

---

## 2. Capture

**Never `screencapture -R x,y,w,h`.** It returns `could not create image from rect` under conditions that have nothing to do with the rect. Capture the whole screen and crop afterwards:

```bash
screencapture -x shot.png
sips -c <height> <width> --cropOffset <top> <left> shot.png    # note: height then width, top then left
sips -z <h> <w> shot.png                                        # upscale to eyeball small UI
```

The main display is **1800×1169 points, captured at 2× → 3600×2338 pixels**. Everything `cliclick` takes is in **points**; everything in a capture is **pixels**. Divide by two.

To capture just the app window (it has a real window id):

```bash
python3 -c "
import Quartz
wins = Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly, Quartz.kCGNullWindowID)
print([(w.get('kCGWindowNumber'), dict(w.get('kCGWindowBounds')))
       for w in wins if 'NTS' in str(w.get('kCGWindowOwnerName',''))])"
screencapture -x -o -l <windowNumber> win.png
```

The **status item is not an enumerable window** — it never shows up in that list. Find it by scanning pixels instead (below).

---

## 3. Drive it

**`cliclick`, never `CGEventPost`.** Synthetic Quartz clicks silently miss.

```bash
/opt/homebrew/bin/cliclick m:<x>,<y> w:400 c:<x>,<y>    # move, settle, click
```

Coordinates observed on the current setup — **re-derive rather than trusting these**, since they move with menu-bar contents and the saved window frame:

| Target | Point | How to re-derive |
|---|---|---|
| Menu-bar status item | `1171,12` | pixel scan below |
| App window | origin `969,40`, size `831×720` | window-bounds query above |
| Channel 1 card | `1102,227` | window origin + card centre from a window capture |
| Play / pause transport | `1003,730` | window origin + bottom-left of the now-playing bar |

Clicking the status item toggles the window. Clicking a channel card *selects* it — the card then reads `● PLAYING`, but that is the channel-is-selected indicator, **not** proof audio is flowing. The transport button still has to be pressed.

### Locating the status item by pixel scan

The NTS mark is a solid bright block, which makes it findable:

```python
import Quartz
src = Quartz.CGImageSourceCreateWithURL(
    Quartz.CFURLCreateWithFileSystemPath(None, 'shot.png', 0, False), None)
cg  = Quartz.CGImageSourceCreateImageAtIndex(src, 0, None)
b   = bytes(Quartz.CGDataProviderCopyData(Quartz.CGImageGetDataProvider(cg)))
bpr = Quartz.CGImageGetBytesPerRow(cg); bpp = Quartz.CGImageGetBitsPerPixel(cg) // 8
cols = [x for x in range(2200, 2500)
        if sum(1 for y in range(14, 70) if b[y*bpr + x*bpp] > 150) > 30]
print('box px', cols[0], cols[-1], '| click point', ((cols[0]+cols[-1])//2)//2, 12)
```

Widen the `range` if it finds nothing. Scan a narrow band — a full-width scan catches the left-hand app menus too.

---

## 4. Measure, don't eyeball

For anything animated or sub-pixel-fussy, read the pixels. Example that proved the menu-bar bars (#6) — bar columns sit at pixel `2366 / 2376 / 2386`, one per bar:

```python
def bar_heights(path):
    src = Quartz.CGImageSourceCreateWithURL(
        Quartz.CFURLCreateWithFileSystemPath(None, path, 0, False), None)
    cg  = Quartz.CGImageSourceCreateImageAtIndex(src, 0, None)
    b   = bytes(Quartz.CGDataProviderCopyData(Quartz.CGImageGetDataProvider(cg)))
    bpr = Quartz.CGImageGetBytesPerRow(cg); bpp = Quartz.CGImageGetBitsPerPixel(cg) // 8
    return [max(sum(1 for y in range(0, 80) if b[y*bpr + x*bpp] > 120)
                for x in range(x0, x0 + 7))
            for x0 in (2366, 2376, 2386)]
```

Take a burst of captures in a shell loop (`for i in 1 2 3 4 5 6; do screencapture -x "f$i.png"; done`) and compare across frames. Identical values across frames = static; varying = animating. Heights come back in pixels — halve for points.

To prove nothing **shifted**, measure the item's pixel extent in each state and compare — identical first/last bright column means neighbouring icons didn't move.

---

## 5. Surfaces by change type

| Change touches | Drive | Watch |
|---|---|---|
| `NTSRadioApp.swift`, `MenuBarIcon.swift` | click the status item; play/pause | menu-bar pixels |
| `DialView.swift`, `ChannelRail.swift`, `CatalogOverlay.swift`, `TopBar.swift` | open the window, click through | window capture by id |
| `PlayerEngine.swift` | press play, pause, switch source | now-playing bar + whether audio state actually tracks |
| `NTSAuth.swift`, `LoginView.swift` | the account popover | requires a paid Supporters account |
| `FirestoreListener`, `TracklistAdapter`, tracklists | play something, open the tracklist overlay | requires sign-in; both feeds are supporter-gated |
| `Catalog.swift`, `ShowIndex.swift`, `Saved.swift` | the catalog overlay tabs | tiles populate, search returns hits |
| `Makefile`, `admin.toml`, packaging | `admin install` | the bundle it produces, not the source tree |

`admin snapshot` renders popover states to PNG in `tmp/claude/design/swift-shots` — handy for static window UI, but it **cannot see the menu bar**, so it never verifies status-item work.

Network is required for playback. Live channel streams need no sign-in; tracklists and mixtape episode titles do.

---

## 6. Push on it

At least one probe past the happy path, at the same surface. Ones that have paid off here:

- **Press play and capture immediately, with no settle.** During buffering AVPlayer sits in `.waitingToPlayAtSpecifiedRate`. This is how you tell a `timeControlStatus` driver from an `isPlaying` one — the latter reacts on frame 1, through silence.
- **Switch source while playing** — listeners are torn down and rebuilt; watch for a stale emit from the old source.
- **Resize the window to `contentMinSize` (720×300)** — dial geometry is derived from `min(w,h)`.
- **Check the shared `MenuBarIcon.logoImage` sites** (`TopBar.swift:28`, `CatalogOverlay.swift:453`, `DialView.swift:256`) whenever menu-bar code changes — mutating that shared object would change all three.
- **Compare against a baseline** when unsure whether something is a regression: `git stash` → `admin install` → capture → `stash pop` → `admin install`. This is what proved the filled-block wordmark (#14) was pre-existing.

---

## 7. Persist the verdict

Write `<repo-root>/tmp/claude/verify/<item>.json` on **every** verdict, `SKIP` included:

```json
{"item": "6", "verdict": "PASS|FAIL|BLOCKED|SKIP",
 "surface": "what you drove", "findings": ["…"],
 "branch": "…", "commit": "…"}
```

**A verdict describes one tree.** Change anything afterwards — a review fix, a tidy-up — and it no longer describes what is about to land: re-run and rewrite the file. This has already caught a real case where a wrap-up review fix landed after a passing verdict.

---

## 8. Report

```
## Verification: <one-line what changed>

**Verdict:** PASS | FAIL | BLOCKED | SKIP
**Claim:** <your read of the diff; note any mismatch with the description>
**Method:** <how you got a handle; what you launched>

### Steps
1. ✅/❌/⚠️/🔍 <what you did to the running app> → <what you observed, with the numbers>

### Findings
<anything that made you pause — friction, surprises, pre-existing breakage, env notes.
 ⚠️ leads the ones worth interrupting for. Every 🔍 probe gets a line even when it held.>
```

Send images with `SendUserFile` — a bare path is not evidence the reader can see.

**No partial pass.** "3 of 4 verified" is FAIL or BLOCKED until the fourth is explained. When in doubt, FAIL — a false PASS ships broken code; a false FAIL costs one more look. **BLOCKED** is for "couldn't reach an observable state" and is not a verdict on the change.
