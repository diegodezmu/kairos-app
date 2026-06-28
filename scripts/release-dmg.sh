#!/usr/bin/env bash
#
# Kairos — reproducible DMG builder.
#
# Usage:
#   scripts/release-dmg.sh [version]      # version default: 1.0.0
#
# Produces: dist/Kairos-<version>.dmg
#
# It first tries a BRANDED DMG via `create-dmg` (custom Figma background + the
# "drag to Applications" layout). create-dmg drives Finder via AppleScript, so it
# needs an interactive session with Automation permission — run this from Terminal
# and accept the "control Finder" prompt the first time. If create-dmg is missing
# or fails (e.g. run non-interactively / over SSH), it falls back to a plain but
# fully functional DMG via `hdiutil` (app + Applications symlink).
#
# Requirements: Xcode, the Ableton Link submodule (auto-initialised below).
# Optional for branding: `brew install create-dmg`.

set -euo pipefail

VERSION="${1:-1.0.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VOLNAME="Kairos"
DMG="dist/Kairos-${VERSION}.dmg"
BG="scripts/assets/dmg-background.png"
DERIVED="build/release"
APP="${DERIVED}/Build/Products/Release/Kairos.app"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> Ensuring submodules (Ableton Link)"
git submodule update --init --recursive

echo "==> Building Release"
xcodebuild -scheme Kairos -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" clean build

[ -d "$APP" ] || { echo "ERROR: built app not found at $APP" >&2; exit 1; }

echo "==> Staging app"
cp -R "$APP" "$STAGE/"

mkdir -p dist
rm -f "$DMG"

build_branded() {
  command -v create-dmg >/dev/null 2>&1 || return 1
  [ -f "$BG" ] || return 1
  create-dmg \
    --volname "$VOLNAME" \
    --background "$BG" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 128 \
    --icon "Kairos.app" 165 185 \
    --hide-extension "Kairos.app" \
    --app-drop-link 495 185 \
    --no-internet-enable \
    "$DMG" "$STAGE"
}

build_plain() {
  ln -sf /Applications "$STAGE/Applications"
  hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
}

echo "==> Building DMG (branded if create-dmg + Finder Automation are available)"
if build_branded && [ -f "$DMG" ]; then
  echo "==> Branded DMG created."
else
  echo "==> Falling back to a plain functional DMG (hdiutil)."
  rm -f "$DMG"
  build_plain
fi

echo "==> Done: $DMG"
ls -lh "$DMG"
