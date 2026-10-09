#!/bin/bash
# Builds "Teams Bridge <version>.pkg" — a standard macOS installer package.
#
# What the package installs:
#   /Applications/Teams Bridge.app           universal (Apple silicon + Intel) menu bar
#                                            app: the daemon, its icon, and the Stream
#                                            Deck plugin bundled inside
#   /Library/LaunchAgents/com.teams-bridge.daemon.plist
#                                            starts the app at login
# and, once installed, hands the Stream Deck plugin to Stream Deck.
#
#   ./package.sh                 build with the default version
#   VERSION=1.3.0 ./package.sh   build a specific version
#
# The result is unsigned (no Developer ID certificate), so the first time it's
# opened on another Mac Gatekeeper asks you to approve it (System Settings >
# Privacy & Security > Open Anyway). The app inside is ad-hoc signed.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-1.3.0}"
BUILD="$(date +%Y%m%d%H%M)"
WORK="dist/.pkg-build"
PKG_PATH="dist/Teams Bridge ${VERSION}.pkg"
SD_PLUGIN_DIR="streamdeck-plugin/com.teams-bridge.streamdeck.sdPlugin"

rm -rf "$WORK"
mkdir -p "$WORK/payload/Applications" "$WORK/payload/Library/LaunchAgents"

echo "==> Building universal daemon (arm64 + x86_64)..."
(cd daemon && swift build -c release --arch arm64 --arch x86_64 2>&1 | grep -E "error|Build complete" || true)
DAEMON_BIN="daemon/.build/apple/Products/Release/teams-bridge-daemon"
[ -f "$DAEMON_BIN" ] || DAEMON_BIN="daemon/.build/out/Products/Release/teams-bridge-daemon"
[ -f "$DAEMON_BIN" ] || { echo "Couldn't find the built daemon binary." >&2; exit 1; }
echo "    $(lipo -archs "$DAEMON_BIN")"

echo "==> Rendering icons from SF Symbols..."
swiftc tools/render-icons.swift -o "$WORK/render-icons"
"$WORK/render-icons" "$SD_PLUGIN_DIR" "$WORK/AppIcon.iconset" >/dev/null
iconutil -c icns "$WORK/AppIcon.iconset" -o "$WORK/AppIcon.icns"

echo "==> Packing Stream Deck plugin..."
(
    cd streamdeck-plugin
    [ -d node_modules ] || npm install --silent
    npm run build --silent
    npx --yes @elgato/cli pack com.teams-bridge.streamdeck.sdPlugin --force >/dev/null
)
PLUGIN_PKG="streamdeck-plugin/com.teams-bridge.streamdeck.streamDeckPlugin"
[ -f "$PLUGIN_PKG" ] || { echo "Couldn't find the packed Stream Deck plugin." >&2; exit 1; }

echo "==> Assembling Teams Bridge.app..."
APP="$WORK/payload/Applications/Teams Bridge.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$DAEMON_BIN" "$APP/Contents/MacOS/teams-bridge-daemon"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" package/Info.plist.template > "$APP/Contents/Info.plist"
cp "$WORK/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$PLUGIN_PKG" "$APP/Contents/Resources/Teams Bridge.streamDeckPlugin"
# Drop what extended attributes can be dropped (e.g. quarantine). The OS-managed
# com.apple.provenance can't be removed, and shows up as "._*" entries in the
# payload — that's just how xattrs are stored; Installer merges them back as
# attributes on install, it doesn't create files (verified: the app's
# signature is valid after extracting the package).
xattr -cr "$WORK/payload"
codesign --force --deep --sign - --identifier com.teams-bridge.daemon "$APP"
codesign --verify --deep --strict "$APP"

cp package/com.teams-bridge.daemon.plist "$WORK/payload/Library/LaunchAgents/"
chmod 644 "$WORK/payload/Library/LaunchAgents/com.teams-bridge.daemon.plist"
xattr -cr "$WORK/payload"
chmod 755 package/scripts/postinstall

echo "==> Building installer package..."
# The login agent points at /Applications/Teams Bridge.app, so the app must
# not be relocated to wherever Installer finds another copy of the same bundle.
pkgbuild --analyze --root "$WORK/payload" "$WORK/components.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$WORK/components.plist"
pkgbuild --root "$WORK/payload" \
    --component-plist "$WORK/components.plist" \
    --identifier com.teams-bridge.pkg \
    --version "$VERSION" \
    --install-location / \
    --ownership recommended \
    --scripts package/scripts \
    "$WORK/TeamsBridge-component.pkg" >/dev/null

sed "s/__VERSION__/$VERSION/" package/distribution.xml.template > "$WORK/distribution.xml"
mkdir -p dist
productbuild --distribution "$WORK/distribution.xml" \
    --resources package/resources \
    --package-path "$WORK" \
    "$PKG_PATH" >/dev/null

rm -rf "$WORK"

echo ""
echo "Built: $PKG_PATH ($(du -h "$PKG_PATH" | cut -f1))"
echo "Copy it to the other Mac and double-click. Unsigned: if macOS blocks it,"
echo "approve it under System Settings > Privacy & Security > Open Anyway."
