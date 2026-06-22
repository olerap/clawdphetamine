#!/bin/bash
# Build & install clawdphetamine.app into ~/Applications. Re-run after editing the
# Swift source or Info.plist. Requires the Xcode Command Line Tools (swiftc).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="clawdphetamine"
BUNDLE_ID="nl.olerap.clawdphetamine"
APP="$HOME/Applications/${APP_NAME}.app"

echo "==> rebuilding ${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

echo "==> compiling ${APP_NAME}.swift"
swiftc -O -swift-version 5 -framework Cocoa \
    -o "$APP/Contents/MacOS/${APP_NAME}" "$HERE/${APP_NAME}.swift"

echo "==> installing Info.plist"
cp "$HERE/Info.plist" "$APP/Contents/Info.plist"

echo "==> chmod hook"
chmod +x "$HERE/claude-hook.sh"

echo "==> ad-hoc code signing (required to run on Apple Silicon)"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
codesign --verify --verbose=1 "$APP"

echo "==> installed: $APP"
