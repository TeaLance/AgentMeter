#!/usr/bin/env bash
# Build AgentMeter and wrap the binary in a proper .app bundle so it runs as a
# menu-bar agent (LSUIElement) and can be double-clicked / added to login items.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AgentMeter"
BUNDLE_ID="com.agentmeter.app"
CONFIG="${1:-release}"
VERSION="0.1.0"
MIN_MACOS="14.0"   # keep in sync with Package.swift `platforms`
SDK_VERSION="$(xcrun --show-sdk-version)"
# SwiftPM's default build system (Swift 6.4+) links with the deployment target
# as the SDK version (LC_BUILD_VERSION sdk 14.0), so macOS treats the app as
# built with an old SDK and drops Liquid Glass. Pass the real SDK explicitly.
LINK_SDK=(-Xlinker -platform_version -Xlinker macos -Xlinker "$MIN_MACOS" -Xlinker "$SDK_VERSION")

cd "$ROOT"
swift build -c "$CONFIG" "${LINK_SDK[@]}"
BIN_DIR="$(swift build -c "$CONFIG" "${LINK_SDK[@]}" --show-bin-path)"

APP="$ROOT/dist/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
"$ROOT/Scripts/check-sdk-version.sh" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>${MIN_MACOS}</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS lets it run locally (no Developer ID required for personal use).
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
