#!/usr/bin/env bash
# Notarize and staple a built .dmg. Requires a Developer ID Application signed
# dmg (see codesign-local.sh) and the App Store Connect API key env vars
# already used for Apple signing project-wide (see ~/.claude/docs/apple-signing.md):
#   APP_STORE_CONNECT_KEY_PATH, APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID
set -euo pipefail

dmg="${1:?usage: notarize.sh <path-to-dmg>}"

: "${APP_STORE_CONNECT_KEY_PATH:?APP_STORE_CONNECT_KEY_PATH not set}"
: "${APP_STORE_CONNECT_KEY_ID:?APP_STORE_CONNECT_KEY_ID not set}"
: "${APP_STORE_CONNECT_ISSUER_ID:?APP_STORE_CONNECT_ISSUER_ID not set}"

echo "Submitting $dmg for notarization…"
xcrun notarytool submit "$dmg" \
  --key "$APP_STORE_CONNECT_KEY_PATH" \
  --key-id "$APP_STORE_CONNECT_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --wait

echo "Stapling ticket…"
xcrun stapler staple "$dmg"
echo "  ✓ notarized and stapled $dmg"
