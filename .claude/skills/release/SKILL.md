---
name: release
description: Cut a new NTS Radio release — bump the version, roll CHANGELOG.md's Unreleased section, tag, and push. The v*.*.* tag push is what triggers .github/workflows/ci-cd.yml (build, sign, notarize, staple, GitHub Release, homebrew-nts tap bump). Use whenever the user asks to release, ship, cut a version, or publish a new build.
---

# Release — NTS Radio

A release is a git tag. Everything downstream — building the dmg, signing with
the Developer ID Application cert, notarizing, stapling, creating the GitHub
Release, bumping the `McBrideMusings/homebrew-nts` cask — happens in
`.github/workflows/ci-cd.yml` once a `v*.*.*` tag lands on `origin`. This skill
does the part before that: decide the version, make the repo match it, tag,
push.

## Steps

1. **Check for uncommitted work.** `git status` — this repo commits straight to
   `main` (own repo), so if there's anything uncommitted, ask whether to
   include it in the release commit or stash it. Don't silently fold in
   unrelated in-progress changes.

2. **Read `CHANGELOG.md`'s `## [Unreleased]` section.** If it's empty, ask the
   user what shipped since the last tag (or read `git log` since the last tag
   to reconstruct it) before proceeding — an empty release note is a worse
   default than asking.

3. **Decide the version.** Current version is the last `## [x.y.z]` heading in
   `CHANGELOG.md` (also mirrored in `mac/Info.plist`'s
   `CFBundleShortVersionString`, which CI overwrites from the tag anyway — the
   changelog is the source of truth here). Semantic Versioning: patch for
   fixes, minor for additive features, major for breaking changes. If it's
   ambiguous from the Unreleased content, ask — don't guess between minor and
   patch.

4. **Roll the changelog.** In `CHANGELOG.md`:
   - Rename `## [Unreleased]` to `## [x.y.z] - YYYY-MM-DD` (today's date).
   - Insert a fresh empty `## [Unreleased]` above it.

5. **Bump `mac/Info.plist`.** Set `CFBundleShortVersionString` to the new
   version (belt-and-suspenders with the CI step that does the same from the
   tag — keeps a local `admin build`/`admin dev` accurate between releases
   too).

6. **Commit.** `chore(release): vX.Y.Z` — no body needed, the changelog entry
   is the detail.

7. **Tag and push.** `git tag vX.Y.Z`, then `git push origin main` and
   `git push origin vX.Y.Z` — two pushes, not `--tags`, so nothing else
   unexpected goes along for the ride.

8. **Report where to watch it.** Point at
   `https://github.com/McBrideMusings/nts-desktop/actions` — don't poll it
   yourself. The pipeline: build → sign (falls back to ad-hoc if the
   `MACOS_CERT_*`/`ASC_API_KEY_*` secrets are ever missing) → notarize → staple
   → GitHub Release with `NTS-Radio.dmg` → `homebrew-nts` cask bump. Mention
   that once the tap updates, `brew install --cask mcbridemusings/nts/nts-radio`
   (or a `brew upgrade` for existing installs) picks it up.

## What this skill does NOT do

- Doesn't reinstall `/Applications/NTS Radio.app` — that's `admin deploy`,
  unrelated to a tagged public release.
- Doesn't wait for CI or verify the release artifact — the tag push is a
  fire-and-forget trigger. If the user wants the pipeline watched, that's a
  separate ask (e.g. `gh run watch`).
- Doesn't touch `admin.toml`'s `distribute` command — that stays the local
  ad-hoc dmg build for dev use, deliberately unrelated to this signed/notarized
  path.
