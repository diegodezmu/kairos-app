#!/usr/bin/env bash
#
# Kairos — reproducible DMG builder.
#
# Usage:
#   scripts/release-dmg.sh [version]      # version default: 1.0.0
#
# Produces: dist/Kairos-<version>.dmg
#
# Primary path: a BRANDED DMG via `dmgbuild` (custom Figma background + the
# "drag to Applications" layout). dmgbuild writes the window styling directly,
# with no Finder/AppleScript, so it works headless and reproducibly.
#   Install once:  python3 -m pip install dmgbuild
#
# If dmgbuild is missing or fails, it falls back to a plain but fully functional
# DMG via `hdiutil` (app + Applications symlink, no background). Both install the
# same way.
#
# Requirements: Xcode 16+, the Ableton Link submodule (auto-initialised below).

set -euo pipefail

VERSION="${1:-1.0.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VOLNAME="Kairos"
DMG="dist/Kairos-${VERSION}.dmg"
BG_SRC="scripts/assets/dmg-background.png"   # 1320x800 Figma export, used as @2x
DERIVED="build/release"
APP="${DERIVED}/Build/Products/Release/Kairos.app"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Ensuring submodules (Ableton Link)"
git submodule update --init --recursive

echo "==> Building Release"
xcodebuild -scheme Kairos -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" clean build

[ -d "$APP" ] || { echo "ERROR: built app not found at $APP" >&2; exit 1; }

mkdir -p dist
rm -f "$DMG" dist/rw.*.dmg   # clear previous output + any stray create-dmg temps

make_branded() {
  command -v dmgbuild >/dev/null 2>&1 || return 1
  [ -f "$BG_SRC" ] || return 1
  # Crisp retina background: combine a 1x (660x400) + 2x (1320x800) into a HiDPI TIFF.
  local bg1x="$TMP/bg-1x.png" bgtiff="$TMP/bg.tiff"
  sips -z 400 660 "$BG_SRC" --out "$bg1x" >/dev/null
  tiffutil -cathidpicheck "$bg1x" "$BG_SRC" -out "$bgtiff" >/dev/null 2>&1 || return 1
  dmgbuild -s scripts/dmg-settings.py -D app="$APP" -D bg="$bgtiff" "$VOLNAME" "$DMG"
}

make_plain() {
  local stage="$TMP/stage"
  mkdir -p "$stage"
  cp -R "$APP" "$stage/"
  ln -sf /Applications "$stage/Applications"
  hdiutil create -volname "$VOLNAME" -srcfolder "$stage" -ov -format UDZO "$DMG"
}

echo "==> Building DMG"
if make_branded && [ -f "$DMG" ]; then
  echo "==> Branded DMG (dmgbuild) created."
else
  echo "==> dmgbuild unavailable/failed — falling back to a plain DMG (hdiutil)."
  rm -f "$DMG"
  make_plain
fi

echo "==> Done: $DMG"
ls -lh "$DMG"
