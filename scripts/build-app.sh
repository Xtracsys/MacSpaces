#!/bin/bash
# Builds MacSpaces.app (and optionally a DMG) from the SwiftPM package.
#
# Usage:
#   ./scripts/build-app.sh                 # native-arch .app → build/
#   ./scripts/build-app.sh --universal     # arm64 + x86_64 fat binary
#   ./scripts/build-app.sh --dmg           # also produce a drag-to-Applications DMG
#   ./scripts/build-app.sh --install       # also copy to /Applications
#   ./scripts/build-app.sh --universal --dmg --install
#
# Distribution (other Macs) needs a notarized build — see scripts/notarize.sh.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
CONFIG="${CONFIG:-release}"
APP_NAME="MacSpaces"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"

UNIVERSAL=0
MAKE_DMG=0
INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --universal) UNIVERSAL=1 ;;
        --dmg) MAKE_DMG=1 ;;
        --install) INSTALL=1 ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

# This CLT ships the 27.0 SDK whose SwiftUI needs the SwiftUIMacros plugin
# that CLT forgot to install; fall back to the last macro-free SDK.
if [[ -z "${SDKROOT:-}" ]] && [[ ! -f "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib" ]] && [[ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk" ]]; then
    export SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
    echo "==> Using SDKROOT=$SDKROOT (SwiftUIMacros plugin missing in CLT)"
fi

echo "==> swift build -c $CONFIG (universal=$UNIVERSAL)"
ARCH_ARGS=()
if [[ "$UNIVERSAL" == 1 ]]; then
    ARCH_ARGS=(--arch arm64 --arch x86_64)
fi
# The ${ARR[@]+"${ARR[@]}"} guard: bash 3.2 (macOS default) treats empty
# arrays as unbound under set -u.
swift build -c "$CONFIG" --product MacSpaces ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"}
BIN="$(swift build -c "$CONFIG" --product MacSpaces --show-bin-path)"
if [[ ! -e "$BIN/$APP_NAME" ]]; then
    echo "Binary missing at $BIN/$APP_NAME" >&2
    exit 1
fi

if [[ "$UNIVERSAL" == 1 ]]; then
    echo "==> Architectures: $(lipo -archs "$BIN/$APP_NAME")"
fi

echo "==> Assembling $APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>com.macspaces.app</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.1</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSMinimumSystemVersionByArchitecture</key>
    <dict>
        <key>arm64</key><string>13.0</string>
        <key>x86_64</key><string>13.0</string>
    </dict>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

cp "$BIN/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"

# App icon (best effort — failure leaves the app with the default icon).
if [[ ! -f "$CONTENTS/Resources/AppIcon.icns" ]]; then
    echo "==> Generating app icon"
    if swift "scripts/make-icon.swift" "$CONTENTS/Resources" 2>/dev/null; then
        echo "Icon generated."
    else
        echo "Icon generation skipped (non-fatal)."
        # Remove icon reference if no icon was produced
        /usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$CONTENTS/Info.plist" 2>/dev/null || true
    fi
fi

echo "==> Ad-hoc codesigning"
xattr -cr "$APP_DIR" 2>/dev/null || true
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || echo "codesign failed (non-fatal)"

if [[ "$MAKE_DMG" == 1 ]]; then
    echo "==> Building $DMG_PATH"
    STAGING="$BUILD_DIR/dmg-staging"
    rm -rf "$STAGING" "$DMG_PATH"
    mkdir -p "$STAGING"
    cp -R "$APP_DIR" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null
    rm -rf "$STAGING"
    echo "DMG: $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"
fi

if [[ "$INSTALL" == 1 ]]; then
    echo "==> Installing to /Applications"
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_DIR" /Applications/
    echo "Installed /Applications/$APP_NAME.app"
fi

echo "Done: $APP_DIR"
echo "Launch with: open \"$APP_DIR\""
[[ "$MAKE_DMG" == 1 ]] && echo "Distribute with: scripts/notarize.sh (needs a Developer ID certificate)"
exit 0
