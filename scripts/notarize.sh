#!/bin/bash
# Signs and notarizes MacSpaces.app for distribution to other Macs.
#
# Prerequisites:
#   - Apple Developer Program membership
#   - "Developer ID Application" certificate in the login keychain
#   - App Store Connect API key (or notarytool keychain profile), see
#     https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution
#
# Usage:
#   export MACSPACES_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   export MACSPACES_KEYCHAIN_PROFILE="AC_PASSWORD"     # notarytool profile name
#   ./scripts/notarize.sh [path/to/MacSpaces.app]
#
# Without the env vars the script prints setup instructions and exits.
set -euo pipefail

APP="${1:-build/MacSpaces.app}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -z "${MACSPACES_SIGN_IDENTITY:-}" || -z "${MACSPACES_KEYCHAIN_PROFILE:-}" ]]; then
    cat <<EOF
Notarization needs two environment variables:

  export MACSPACES_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
  export MACSPACES_KEYCHAIN_PROFILE="AC_PASSWORD"

The identity comes from your keychain (check: security find-identity -v -p codesigning).
The keychain profile is created once with:

  xcrun notarytool store-credentials AC_PASSWORD \\
      --apple-id you@example.com --team-id TEAMID --password APP-SPECIFIC-PASSWORD

Then re-run: $0 $APP
EOF
    exit 1
fi

cd "$SCRIPT_DIR/.."
[[ -d "$APP" ]] || { echo "App bundle not found: $APP (run scripts/build-app.sh first)" >&2; exit 1; }

echo "==> Signing with $MACSPACES_SIGN_IDENTITY"
xattr -cr "$APP"
codesign --force --deep --sign "$MACSPACES_SIGN_IDENTITY" \
    --options runtime --timestamp "$APP"

echo "==> Verifying signature"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Zipping for submission"
ZIP="$(mktemp -d)/MacSpaces.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Submitting for notarization (this can take several minutes)"
xcrun notarytool submit "$ZIP" --keychain-profile "$MACSPACES_KEYCHAIN_PROFILE" --wait

echo "==> Stapling ticket"
xcrun stapler staple "$APP"

echo "==> Final check"
codesign --verify --strict --verbose=2 "$APP"
spctl -a -vv -t install "$APP" || true

echo "Notarized: $APP"
echo "Zip for distribution: ditto -c -k --keepParent \"$APP\" MacSpaces.zip"
