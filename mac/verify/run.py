#!/usr/bin/env python3
"""Run the scripted rows of docs/verification against the installed app.

    admin verify                 every check
    admin verify P1              one priority
    admin verify PLAY-05 EXP-01  named rows

Each docs/verification/<area>.md has a mac/verify/<area>.tsv beside this file,
one line per `script` row, keyed by the row's ID:

    ID <tab> steps <tab> check <tab> note

`steps` is a ` ; `-separated list. Every step adds one element to an array, and
`check` is a jq expression over that array that must come out true:

    <drive verb> [args]   any mac/drive.sh verb; its state JSON, or {"value": …}
                          for `get`, or {"error": …, "code": n} when it fails
    osa <applescript>     `tell application "NTS Radio" to <applescript>`, raw
    sleep <s>             null
    until <s> <jq>        `get state` once a second until <jq> holds, or <s> pass
    await <s> <jq>        the same, but the row is blocked when <s> pass first — for
                          waiting on the world (a track change), not on the app
    relaunch              graceful quit, launch, then `get state`
    frontmost             {"frontmost": <name of the frontmost process>}; the row is
                          blocked when System Events will not say
    dictionary            {"sdef": <the installed bundle's dictionary XML>}
    require <jq>          null; when <jq> is false of `get state`, the row is blocked
    burst <s> <cmd> & <cmd> & …
                          every command sent in one osascript without waiting for
                          replies, so they overlap inside the app; then <s> of the
                          `api` log as {"requests": {"<path> ok|failed": count}}

Every element that is an object also carries `_ms`, how long the step took.
No expression inside a step may contain ` ; `, which separates steps.

A row whose steps column reads `manual` is not run: its check column names what
the state would have to report for a script to decide it.

Before each row the app is put back to idle with the catalog, the radio
window and Settings closed; after the run, every preference a row can change
is restored to what it was when the run started. The Result cell of each row run is rewritten
in place, and its replies replace that row's entry in
tmp/claude/verify/checklist.json, which keeps the last run of every row. A row
that fails or is blocked also carries `log`: every app.log line stamped between
the start of its reset and the end of its check, so a failure that will not
reproduce arrives with what the app wrote while it happened. The
exit status is 1 when a row fails, the screen locked, or a preference could
not be restored.

The run holds a display assertion (`caffeinate -d`) for its whole life, because
the idle screensaver locks the screen, and behind the lock screen a scripted
`open window` answers `windowVisible: false`. A screen locked before a row
stops the run there; a lock that lands during a row turns that row's pass into
blocked.

Never add a step that checks for updates: Sparkle's dialog brings the app to
the front, and the runner must never take focus from whoever is typing.
`settings` is safe — a scripted open does not activate the app.
"""

import datetime
import json
import os
import plistlib
import re
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / "docs" / "verification"
HERE = Path(__file__).resolve().parent
DRIVE = ROOT / "mac" / "drive.sh"
REPORT = ROOT / "tmp" / "claude" / "verify" / "checklist.json"
APP = "NTS Radio"
APP_LOG = Path.home() / "Library" / "Logs" / APP / "app.log"
# How long to wait for AppLogMirror, which copies the unified log into app.log
# every 2 s, to reach the end of the run.
MIRROR_WAIT = 10
ERROR = re.compile(r"error: (?:NTS Radio got an error: )?(.*?) \((-?\d+)\)\s*$", re.S)


def log(msg):
    print(msg, flush=True)


def reply(proc):
    """One step's result: the state object it printed, its error and code, or
    anything else it printed — a property's value — as {"value": …}."""
    if proc.returncode != 0:
        text = proc.stderr.strip() or proc.stdout.strip()
        m = ERROR.search(text)
        if m:
            return {"error": m.group(1), "code": int(m.group(2))}
        return {"error": text, "code": None}
    out = proc.stdout.strip()
    try:
        state = json.loads(out)
    except json.JSONDecodeError:
        state = None
    return state if isinstance(state, dict) else {"value": out}


def drive(*args):
    return reply(subprocess.run([str(DRIVE), *args], capture_output=True, text=True))


def osa(script):
    return reply(subprocess.run(["osascript", "-e", script], capture_output=True, text=True))


API_LINE = re.compile(r"^\S+ (\S+) (ok|failed)\b")


def burst(secs, commands):
    """Send `commands` in one osascript inside `ignoring application responses`
    and count the requests the app logs in the next `secs` seconds. Separate
    osascript calls would each wait for their reply, so a request could land
    before the next command arrived and nothing would overlap."""
    stream = subprocess.Popen(
        ["log", "stream", "--style", "ndjson", "--level", "debug", "--predicate",
         'subsystem == "live.nts.desktop" AND category == "api"'],
        stdout=subprocess.PIPE, text=True)
    lines = []
    reader = threading.Thread(target=lambda: lines.extend(stream.stdout), daemon=True)
    try:
        # `log stream` prints its filter line before it is attached; give it a
        # second so the first request is not missed.
        stream.stdout.readline()
        reader.start()
        time.sleep(1)
        args = ["osascript", "-e", f'tell application "{APP}"', "-e", "ignoring application responses"]
        for cmd in commands:
            args += ["-e", cmd]
        args += ["-e", "end ignoring", "-e", "end tell"]
        sent = reply(subprocess.run(args, capture_output=True, text=True))
        if "error" in sent:
            return sent
        time.sleep(secs)
    finally:
        stream.terminate()
        stream.wait()
    reader.join(2)
    requests = {}
    for line in lines:
        try:
            m = API_LINE.match(json.loads(line).get("eventMessage", ""))
        except json.JSONDecodeError:
            continue
        if m:
            key = f"{m[1]} {m[2]}"
            requests[key] = requests.get(key, 0) + 1
    return {"requests": requests}


def jq(expr, data):
    """True when `expr` holds of `data`; a jq error counts as false."""
    proc = subprocess.run(["jq", "-e", expr], input=json.dumps(data),
                          capture_output=True, text=True)
    return proc.returncode == 0, proc.stderr.strip()


def screen_locked():
    """True while the console shows the lock screen, read from IOKit's root
    entry so the answer does not depend on the app."""
    proc = subprocess.run(["ioreg", "-n", "Root", "-d1", "-a"], capture_output=True, check=True)
    return plistlib.loads(proc.stdout)["IOConsoleLocked"]


def now():
    return datetime.datetime.now().astimezone()


def stamped_lines():
    """(timestamp, line) for every app.log line, oldest first, reading the
    rotated app.log.1 too in case the log rolled mid-run."""
    lines = []
    for path in (APP_LOG.with_name("app.log.1"), APP_LOG):
        try:
            text = path.read_text(errors="replace")
        except OSError:
            continue
        for line in text.splitlines():
            try:
                lines.append((datetime.datetime.fromisoformat(line.partition("\t")[0]), line))
            except ValueError:
                continue
    return lines


def app_log(spans):
    """{row id: the app.log lines stamped inside its (start, end)}. The mirror
    writes in time order, so once app.log holds a line stamped after the last
    span — restore()'s window close logs one — it holds every line before it."""
    last = max(end for _, end in spans.values())
    deadline = time.monotonic() + MIRROR_WAIT
    lines = stamped_lines()
    while not any(at > last for at, _ in lines) and time.monotonic() < deadline:
        time.sleep(0.5)
        lines = stamped_lines()
    return {row: [line for at, line in lines if start <= at <= end]
            for row, (start, end) in spans.items()}


class Blocked(Exception):
    pass


def step(text):
    verb, _, rest = text.strip().partition(" ")
    rest = rest.strip()
    if verb == "osa":
        return osa(f'tell application "{APP}" to {rest}')
    if verb == "sleep":
        time.sleep(float(rest))
        return None
    if verb in ("until", "await"):
        secs, _, expr = rest.partition(" ")
        deadline = time.monotonic() + float(secs)
        while True:
            state = drive("state")
            if jq(expr, state)[0]:
                return state
            if time.monotonic() >= deadline:
                if verb == "await":
                    raise Blocked(f"{expr} did not happen within {secs}s")
                return state
            time.sleep(1)
    if verb == "relaunch":
        drive("quit")
        drive("launch")
        return drive("state")
    if verb == "frontmost":
        r = osa('tell application "System Events" to get name of first process whose frontmost is true')
        if "value" not in r:
            raise Blocked(f"frontmost: {r['error']}")
        return {"frontmost": r["value"]}
    if verb == "dictionary":
        proc = subprocess.run(["sdef", f"/Applications/{APP}.app"], capture_output=True, text=True)
        return {"sdef": proc.stdout}
    if verb == "burst":
        secs, _, cmds = rest.partition(" ")
        return burst(float(secs), [c.strip() for c in cmds.split(" & ")])
    if verb == "require":
        if not jq(rest, drive("state"))[0]:
            raise Blocked(f"requires {rest}")
        return None
    return drive(verb, *rest.split())


def run_row(steps):
    replies = []
    for text in steps.split(" ; "):
        start = time.monotonic()
        r = step(text)
        if isinstance(r, dict):
            r["_ms"] = round((time.monotonic() - start) * 1000)
        replies.append(r)
    return replies


def reset():
    """Idle, catalog closed, radio window and Settings closed — the state every
    row starts from."""
    drive("stop")
    drive("close-catalog")
    drive("window", "close")
    drive("close-settings")


def restore(base):
    """Put back every preference a row can change; returns what could not be."""
    log("restoring the preferences the run started with")
    reset()
    calls = [
        ("set", "volume", str(base["volume"])),
        ("set", "muted", str(base["muted"]).lower()),
        ("set", "auto-checks-for-updates", str(base["autoChecksForUpdates"]).lower()),
        ("set", "track-lead", base["trackLead"]),
    ]
    args = ["filter"]
    if base["exploreMood"]:
        args += ["mood", base["exploreMood"]]
    for g in base["exploreGenres"]:
        args += ["genre", g]
    if base["exploreMusicOnly"]:
        args.append("music-only")
    if base["exploreFocused"]:
        args.append("focused")
    calls += [
        tuple(args),
        ("catalog", "schedule", str(base["scheduleChannel"])),
        ("catalog", base["catalogTab"]),
        ("close-catalog",),
    ]
    if base["windowVisible"]:
        calls.append(("window", "open"))
    if base["settingsVisible"]:
        calls.append(("settings", base["settingsPane"]))
    failed = []
    for call in calls:
        r = drive(*call)
        if "error" in r:
            failed.append(f"{' '.join(call)}: {r['error']}")
            log(f"could not restore — {failed[-1]}")
    return failed


def load_checks():
    """{id: (area, steps, check, note)} from every TSV."""
    checks = {}
    for tsv in sorted(HERE.glob("*.tsv")):
        for n, line in enumerate(tsv.read_text().splitlines(), 1):
            if not line.strip() or line.startswith("#"):
                continue
            cols = line.split("\t")
            if len(cols) < 3:
                sys.exit(f"{tsv.name}:{n}: want ID, steps, check[, note]")
            cols += [""] * (4 - len(cols))
            checks[cols[0]] = (tsv.stem, cols[1], cols[2], cols[3])
    return checks


ROW = re.compile(r"^\| (?P<id>[A-Z]+-\d+) \| (?P<p>P\d) \|")


def priorities():
    """{id: priority} from the checklist tables."""
    found = {}
    for md in DOCS.glob("*.md"):
        for line in md.read_text().splitlines():
            m = ROW.match(line)
            if m:
                found[m["id"]] = m["p"]
    return found


def write_result(area, row_id, result):
    md = DOCS / f"{area}.md"
    lines = md.read_text().split("\n")
    for i, line in enumerate(lines):
        if line.startswith(f"| {row_id} |"):
            cells = re.split(r"(?<!\\)\|", line.rstrip())
            cells[-2] = " " + result.replace("|", "\\|") + " "
            lines[i] = "|".join(cells)
            md.write_text("\n".join(lines))
            return
    sys.exit(f"{row_id}: no row in {md.relative_to(ROOT)}")


def write_report(rows):
    """Replace each run row's entry in the report, keeping every other row's."""
    kept = {}
    if REPORT.exists():
        kept = {r["id"]: r for r in json.loads(REPORT.read_text())}
    kept.update({r["id"]: r for r in rows})
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(sorted(kept.values(), key=lambda r: r["id"]),
                                 indent=2, ensure_ascii=False))


def main(argv):
    checks = load_checks()
    prio = priorities()
    missing = sorted(set(checks) - set(prio))
    if missing:
        sys.exit(f"checks for rows that do not exist: {', '.join(missing)}")

    want_p = {a for a in argv if re.fullmatch(r"P[123]", a)}
    want_id = [a for a in argv if a not in want_p]
    unknown = [a for a in want_id if a not in checks]
    if unknown:
        sys.exit(f"no check for: {', '.join(unknown)}")
    order = {"P1": 1, "P2": 2, "P3": 3}
    ids = want_id or sorted(
        (i for i in checks if not want_p or prio[i] in want_p),
        key=lambda i: (order[prio[i]], i))

    base = drive("state")
    if "error" in base:
        sys.exit(f"the app does not answer get state: {base['error']}")
    # Exits with this process, so the assertion lasts exactly as long as the run.
    subprocess.Popen(["caffeinate", "-d", "-w", str(os.getpid())])

    today = datetime.date.today().isoformat()
    report, tally, locked = [], {}, False
    spans = {}  # row id: (start, end) of each failed or blocked row
    try:
        for n, row_id in enumerate(ids):
            area, steps, check, note = checks[row_id]
            if steps == "manual":
                log(f"{row_id:9} manual   {check}")
                tally["manual"] = tally.get("manual", 0) + 1
                continue
            if screen_locked():
                locked = True
                log(f"the screen is locked; stopping before {row_id}")
                tally["not run"] = len(ids) - n
                break
            start = now()
            reset()
            replies, detail = [], ""
            try:
                replies = run_row(steps)
                ok, err = jq(check, replies)
                verdict = "pass" if ok else "fail"
                detail = err
            except Blocked as e:
                verdict, detail = "blocked", str(e)
            # A pass behind the lock screen proves nothing; a fail keeps its own reason.
            if verdict == "pass" and screen_locked():
                locked = True
                verdict, detail = "blocked", "the screen locked during the row"
            if verdict != "pass":
                spans[row_id] = (start, now())
            tally[verdict] = tally.get(verdict, 0) + 1
            result = f"{verdict} (scripted {today}"
            result += f"; {note})" if note else ")"
            if verdict == "blocked":
                result += f" — {detail}"
            write_result(area, row_id, result)
            log(f"{row_id:9} {verdict:8} {detail}")
            report.append({"id": row_id, "priority": prio[row_id], "verdict": verdict,
                           "date": today,
                           "steps": steps, "check": check, "detail": detail,
                           "replies": replies})
    finally:
        unrestored = restore(base)
        if spans:
            lines = app_log(spans)
            for entry in report:
                if entry["id"] in lines:
                    entry["log"] = lines[entry["id"]]
        write_report(report)

    log(", ".join(f"{n} {k}" for k, n in sorted(tally.items())) + f" — replies in {REPORT}")
    return 1 if tally.get("fail") or locked or unrestored else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
