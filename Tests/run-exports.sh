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
if [[ "${BETTERSHOT_CHECK_EDITOR_SCENES:-0}" == "1" ]]; then
    swiftc -parse-as-library -module-cache-path .build/ExportCheckModules \
        -I ".build/Build/Products/$configuration" Tests/EditorSceneIntegration.swift \
        "${objects[@]}" ".build/Build/Products/$configuration/DockProgress.o" ".build/Build/Products/$configuration/TourKit.o" ".build/Build/Products/$configuration/DynamicNotchKit.o" \
        -o "$out/EditorSceneIntegration"
    for editor in image video; do
        for automatic in 0 1; do
            BETTERSHOT_TESTING=1 "$out/EditorSceneIntegration" "$editor" "$automatic"
        done
    done
    exit 0
fi
swiftc -parse-as-library -module-cache-path .build/ExportCheckModules \
    -I ".build/Build/Products/$configuration" Tests/ExportIntegration.swift Tests/EditorUIIntegration.swift Tests/ImageTransformIntegration.swift Tests/Recording3DIntegration.swift Tests/NotchIntegration.swift \
    "${objects[@]}" ".build/Build/Products/$configuration/DockProgress.o" ".build/Build/Products/$configuration/TourKit.o" ".build/Build/Products/$configuration/DynamicNotchKit.o" \
    -o "$out/ExportIntegration"
# The snapshots instantiate sharing UI; do not read the real R2 Keychain from this test binary.
BETTERSHOT_TESTING=1 "$out/ExportIntegration"
