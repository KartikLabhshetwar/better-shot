#!/bin/bash
# Run after: xcodebuild -project BetterShot.xcodeproj -scheme BetterShot \
#   -configuration Debug -derivedDataPath .build CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES build
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
arch="$(uname -m)"
objects=()
for object in .build/Build/Intermediates.noindex/BetterShot.build/Debug/BetterShot.build/Objects-normal/"$arch"/*.o; do
    [[ "$object" == */BetterShotApp.o ]] || objects+=("$object")
done
swiftc -parse-as-library -module-cache-path .build/ExportCheckModules \
    -I .build/Build/Products/Debug Tests/ExportIntegration.swift Tests/EditorUIIntegration.swift \
    "${objects[@]}" .build/Build/Products/Debug/DockProgress.o \
    -o "$out/ExportIntegration"
# The snapshots instantiate sharing UI; do not read the real R2 Keychain from this test binary.
BETTERSHOT_TESTING=1 "$out/ExportIntegration"
