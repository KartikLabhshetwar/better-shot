#!/bin/bash
# Opens the actual editor with a private copy of bundled practice media.
# Capture this window with macOS screencapture; quit before changing editor kinds.
set -euo pipefail
cd "$(dirname "$0")/../../.."
kind="${1:-image}"
[[ "$kind" == image || "$kind" == video ]]
out="$(mktemp -d /private/tmp/bettershot-media-XXXXXX)"
app="$out/BetterShot Media.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp -R .build/Build/Products/Debug/BetterShot.app/Contents/Resources/. "$app/Contents/Resources/"
arch="$(uname -m)"
objects=()
for object in .build/Build/Intermediates.noindex/BetterShot.build/Debug/BetterShot.build/Objects-normal/"$arch"/*.o; do
    [[ "$object" == */BetterShotApp.o ]] || objects+=("$object")
done
swiftc -parse-as-library -module-cache-path .build/ExportCheckModules \
    -I .build/Build/Products/Debug bettershot-landing/media/native/CaptureEditors.swift \
    "${objects[@]}" .build/Build/Products/Debug/DockProgress.o -o "$app/Contents/MacOS/BetterShotMedia"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>BetterShotMedia</string><key>CFBundleIdentifier</key><string>com.bettershot.media-preview</string><key>CFBundleName</key><string>BetterShot Media</string><key>CFBundlePackageType</key><string>APPL</string><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
if [[ "$kind" == video ]]; then
    ffmpeg -v error -loop 1 -i Resources/Onboarding/coast.png -vf "scale=1440:900:force_original_aspect_ratio=increase,crop=1440:900,zoompan=z='1+0.0002*on':x='iw/2-iw/zoom/2':y='ih/2-ih/zoom/2':d=1:s=1280x800:fps=30" -t 20 -c:v libx264 -pix_fmt yuv420p -crf 20 "$out/Coastal walkthrough.mp4"
    source="$out/Coastal walkthrough.mp4"
else
    cp Resources/Onboarding/screenshot-demo.png "$out/Coastal walkthrough.png"
    source="$out/Coastal walkthrough.png"
fi
printf 'Preview app: %s\n' "$app"
BETTERSHOT_TESTING=1 BETTERSHOT_MEDIA_KIND="$kind" BETTERSHOT_MEDIA_SOURCE="$source" "$app/Contents/MacOS/BetterShotMedia" -bs_editorOpensFullScreen NO
