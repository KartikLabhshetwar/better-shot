#!/bin/bash
set -euo pipefail

if [[ $# != 2 || ! -d "$1/Contents" || "$2" != *.dmg ]]; then
    echo "Usage: bash scripts/create-dmg.sh BetterShot.app output.dmg" >&2
    exit 1
fi
if ! command -v create-dmg >/dev/null; then
    echo "DMG packaging requires create-dmg: brew install create-dmg" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$(cd "$1" && pwd)"
mkdir -p "$(dirname "$2")"
OUTPUT_DIR="$(cd "$(dirname "$2")" && pwd)"
OUTPUT_PATH="$OUTPUT_DIR/$(basename "$2")"
# Stage beside the destination so the final move is atomic, including rebuilds.
WORK_DIR="$(mktemp -d "$OUTPUT_DIR/.dmg-build.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
mkdir "$WORK_DIR/staging"
ditto "$APP_PATH" "$WORK_DIR/staging/BetterShot.app"
xcrun swift "$SCRIPT_DIR/dmg-background.swift" "$WORK_DIR/background.tiff"

create-dmg \
    --volname "BetterShot" \
    --volicon "$APP_PATH/Contents/Resources/AppIcon.icns" \
    --background "$WORK_DIR/background.tiff" \
    --window-pos 200 140 \
    --window-size 660 468 \
    --icon-size 128 \
    --text-size 14 \
    --icon "BetterShot.app" 180 230 \
    --hide-extension "BetterShot.app" \
    --app-drop-link 480 230 \
    "$WORK_DIR/BetterShot.dmg" "$WORK_DIR/staging"

hdiutil verify "$WORK_DIR/BetterShot.dmg"
mv -f "$WORK_DIR/BetterShot.dmg" "$OUTPUT_PATH"
echo "Created $OUTPUT_PATH"
