#!/bin/zsh
# Builds Onyx.app (release) and installs it to /Applications.
set -euo pipefail
cd "${0:A:h}/.."

if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Swift not found. Install Apple's Command Line Tools (xcode-select --install) or Xcode, then run this again." >&2
  exit 1
fi
if [[ "$(sw_vers -productVersion | cut -d. -f1)" -lt 14 ]]; then
  echo "Onyx needs macOS 14 (Sonoma) or newer." >&2
  exit 1
fi
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

# Sign with the local certificate when there is one (scripts/make-signing-cert.sh), so every
# rebuild keeps one identity and macOS keeps Onyx's permissions (microphone, folders).
if security find-certificate -c "Onyx Local Signing" >/dev/null 2>&1; then
  codesign --force -s "Onyx Local Signing" "$APP"
else
  codesign --force -s - "$APP"
fi
rm -rf /Applications/Onyx.app
ditto "$APP" /Applications/Onyx.app
# Leave only the installed copy, so Spotlight and launchers list one Onyx.
rm -rf build
echo "Installed /Applications/Onyx.app"

# Pin to the Dock once (skip with ONYX_NO_DOCK=1); never adds a second icon.
if [[ -z "${ONYX_NO_DOCK:-}" ]] && ! defaults read com.apple.dock persistent-apps 2>/dev/null | grep -q "file:///Applications/Onyx.app/"; then
  defaults write com.apple.dock persistent-apps -array-add \
    '<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>file:///Applications/Onyx.app/</string><key>_CFURLStringType</key><integer>15</integer></dict></dict><key>tile-type</key><string>file-tile</string></dict>'
  killall Dock
  echo "Pinned Onyx to the Dock"
fi
