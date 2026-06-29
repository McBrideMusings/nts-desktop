#!/usr/bin/env bash
# Stable-sign a built binary or .app so macOS Keychain / TCC grants survive
# rebuilds.
#
# Why: `swift build` produces an ad-hoc-signed binary whose code-signing
# "designated requirement" is its raw cdhash — which changes on EVERY build. The
# Keychain item NTSAuth stores is bound to that requirement, so macOS treats each
# rebuild as a brand-new app and re-prompts for access. Signing with a stable
# identity and a FIXED identifier makes the designated requirement constant
# (identifier + Team ID), so the grant persists across rebuilds.
#
# Identity selection:
#   - $CODE_SIGN_IDENTITY set        → use it verbatim ("-" forces ad-hoc, which
#                                       the public dmg uses so it never ships a
#                                       personal cert).
#   - unset                          → auto-pick this machine's Apple Development
#                                       identity; fall back to ad-hoc if none
#                                       exists (e.g. CI).
# The identity is resolved at build time from the local keychain — no team id or
# cert hash is ever written into a committed file.
set -uo pipefail

target="${1:?usage: codesign-local.sh <path-to-binary-or-app>}"
identifier="live.nts.desktop"

id="${CODE_SIGN_IDENTITY:-}"
if [ -z "$id" ]; then
  id=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/{print $2; exit}')
  [ -z "$id" ] && id="-"
fi

codesign --force --deep --identifier "$identifier" --sign "$id" "$target" 2>/dev/null \
  || codesign --force --deep --sign "$id" "$target"

printf '  ✓ codesigned %s (%s)\n' "$(basename "$target")" "${id:0:14}"
