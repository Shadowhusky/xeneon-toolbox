#!/bin/bash
# Sign (Developer ID + hardened runtime), notarize, and staple XeneonToolbox.app
# into a distributable zip users can download and run without Gatekeeper warnings.
#
# Requires in the environment (read transiently, never committed):
#   APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, APPLE_TEAM_ID
# and a "Developer ID Application" certificate in the login keychain.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="XeneonToolbox.app"
ZIP="XeneonToolbox.zip"
IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"

: "${APPLE_ID:?set APPLE_ID}"
: "${APPLE_APP_SPECIFIC_PASSWORD:?set APPLE_APP_SPECIFIC_PASSWORD}"
: "${APPLE_TEAM_ID:?set APPLE_TEAM_ID}"
[ -d "$APP" ] || { echo "Build $APP first (./scripts/make-app.sh)"; exit 1; }

echo "▸ Signing nested helpers + app (Developer ID, hardened runtime, timestamp)…"
# Sign inner code (the bundled m1ddc helper) before the outer bundle.
if [ -f "$APP/Contents/Resources/m1ddc" ]; then
  codesign --force --options runtime --timestamp -s "$IDENTITY" "$APP/Contents/Resources/m1ddc"
fi
ENT="$(cd "$(dirname "$0")" && pwd)/entitlements.plist"
codesign --force --options runtime --timestamp --entitlements "$ENT" -s "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "▸ Zipping for notarization…"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▸ Submitting to Apple notary service (this can take a few minutes)…"
xcrun notarytool submit "$ZIP" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait

echo "▸ Stapling the ticket…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "▸ Re-zipping the stapled app for distribution…"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "✓ $ZIP is signed, notarized, and stapled."
spctl -a -vvv -t exec "$APP" || true
