#!/bin/zsh
# Builds Onyx.app (release) and installs it to /Applications.
set -euo pipefail
cd "${0:A:h}/.."
source scripts/env.sh

swift build -c release
BIN=$(swift build -c release --show-bin-path)

APP=build/Onyx.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Onyx" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"

# Icon: render once, then build every size iconutil wants.
ICONSET=build/Onyx.iconset
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
swift scripts/make-icon.swift build/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Onyx.icns"

codesign --force --deep -s - "$APP"
rm -rf /Applications/Onyx.app
ditto "$APP" /Applications/Onyx.app
echo "Installed /Applications/Onyx.app"
