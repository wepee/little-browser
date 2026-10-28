#!/bin/bash
# Build Little Browser.app — usage: ./build.sh [install]
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Little Browser.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" Sources/main.swift \
  -o "$APP/Contents/MacOS/LittleBrowser"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP" 2>/dev/null
echo "✓ Built $APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x LittleBrowser 2>/dev/null || true
  rm -rf "/Applications/Little Browser.app"
  cp -R "$APP" /Applications/
  open "/Applications/Little Browser.app"
  echo "✓ Installed in /Applications and launched — press ⌘⌥N"
fi
