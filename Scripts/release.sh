#!/usr/bin/env bash
# Build, sign (Developer ID), notarize, staple and package AgentMeter for distribution.
#
# Prerequisites (one-time, see README "Releasing"):
#   1. A "Developer ID Application" certificate in your login keychain.
#   2. A notarytool keychain profile:
#        xcrun notarytool store-credentials AgentMeter-notary \
#          --apple-id <id> --team-id <TEAMID> --password <app-specific-password>
#
# Usage: Scripts/release.sh <version>        e.g. Scripts/release.sh 0.1.0
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AgentMeter"
BUNDLE_ID="com.agentmeter.app"
VERSION="${1:?usage: Scripts/release.sh <version, e.g. 0.1.0>}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AgentMeter-notary}"
cd "$ROOT"

echo "==> Universal release build"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"

echo "==> Assemble .app"
APP="$ROOT/dist/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> Locate Developer ID identity"
IDENTITY="$(security find-identity -v -p codesigning | grep -m1 'Developer ID Application' | sed -E 's/.*"(.*)"$/\1/')"
if [ -z "$IDENTITY" ]; then
    echo "ERROR: no 'Developer ID Application' certificate in the keychain."
    echo "Create one in Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application."
    exit 1
fi
echo "    using: $IDENTITY"

echo "==> Sign (hardened runtime + secure timestamp)"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

ZIP="$ROOT/dist/$APP_NAME-$VERSION.zip"
echo "==> Notarize"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Staple + re-package"
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo
echo "==> Done. Distributable (notarized + stapled):"
echo "    $ZIP"
echo "    sha256: $(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo
echo "Verify Gatekeeper acceptance:"
echo "    spctl -a -vvv -t install \"$APP\""