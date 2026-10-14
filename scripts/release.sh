#!/bin/bash
# Builds Glowdesk, signs it with your Developer ID, notarizes it with Apple and
# produces dist/Glowdesk-<version>.zip, ready to attach to a GitHub release.
#
# One-time setup:
#   1. Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application
#   2. xcrun notarytool store-credentials glowdesk --apple-id <you@example.com> --team-id <TEAMID>
#
# Usage: VERSION=1.0.0 bash scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
PROFILE="${NOTARY_PROFILE:-glowdesk}"
APP="dist/Glowdesk.app"
ZIP="dist/Glowdesk-$VERSION.zip"

IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
if [ -z "$IDENTITY" ]; then
  echo "No 'Developer ID Application' certificate found. Create one in Xcode > Settings > Accounts > Manage Certificates." >&2
  exit 1
fi
echo "Signing as: $IDENTITY"

VERSION="$VERSION" bash scripts/build.sh

# Hardened runtime and a secure timestamp are required for notarization.
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Submitting to Apple for notarization (usually a few minutes)…"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

# Staple the ticket so the app opens offline too, then re-zip the stapled app.
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
spctl --assess --type execute --verbose "$APP"
shasum -a 256 "$ZIP"
echo "Ready: $ZIP"
