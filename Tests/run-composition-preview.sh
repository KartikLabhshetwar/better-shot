#!/bin/bash
# Build an isolated native UI fixture; launch its .app manually afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."
derived="${BETTERSHOT_DERIVED_DATA:-.build/tests}"
arch="$(uname -m)"
objects=()
for object in "$derived"/Build/Intermediates.noindex/BetterShot.build/Debug/BetterShot.build/Objects-normal/"$arch"/*.o; do
    [[ "$object" == */BetterShotApp.o ]] || objects+=("$object")
done
bundle=".build/CompositionPreview.app/Contents"
mkdir -p "$bundle/MacOS"
swiftc -parse-as-library -module-cache-path .build/ExportCheckModules \
    -I "$derived/Build/Products/Debug" Tests/CompositionPreview.swift \
    "${objects[@]}" "$derived/Build/Products/Debug/DockProgress.o" \
    -o "$bundle/MacOS/CompositionPreview"
cat > "$bundle/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.bettershot.CompositionPreview</string>
<key>CFBundleName</key><string>CompositionPreview</string>
<key>CFBundleExecutable</key><string>CompositionPreview</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
codesign --force --sign - ".build/CompositionPreview.app"
echo "Built .build/CompositionPreview.app (isolated test preferences and storage)"
