#!/bin/bash
# Run after: xcodebuild -project BetterShot.xcodeproj -scheme BetterShot \
#   -configuration Debug -derivedDataPath .build CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES build
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
arch="$(uname -m)"
configuration="${BETTERSHOT_BUILD_CONFIGURATION:-Debug}"
objects=()
for object in .build/Build/Intermediates.noindex/BetterShot.build/"$configuration"/BetterShot.build/Objects-normal/"$arch"/*.o; do
    [[ "$object" == */BetterShotApp.o ]] || objects+=("$object")
done
swiftc -parse-as-library -module-cache-path .build/ExportCheckModules \
    -I ".build/Build/Products/$configuration" Tests/ExportIntegration.swift Tests/EditorUIIntegration.swift \
    "${objects[@]}" ".build/Build/Products/$configuration/DockProgress.o" \
    -o "$out/ExportIntegration"
# The standalone binary uses the same bundled cursor resources as the app.
cp -R ".build/Build/Products/$configuration/BetterShot.app/Contents/Resources/Cursors" "$out/Cursors"
# The snapshots instantiate sharing UI; do not read the real R2 Keychain from this test binary.
BETTERSHOT_TESTING=1 "$out/ExportIntegration"
