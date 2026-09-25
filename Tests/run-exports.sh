#!/bin/bash
# Run after make test. Custom builds can set BETTERSHOT_DERIVED_DATA.
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
arch="$(uname -m)"
configuration="${BETTERSHOT_BUILD_CONFIGURATION:-Debug}"
derived="${BETTERSHOT_DERIVED_DATA:-.build/tests}"
objects=()
for object in "$derived"/Build/Intermediates.noindex/BetterShot.build/"$configuration"/BetterShot.build/Objects-normal/"$arch"/*.o; do
    [[ "$object" == */BetterShotApp.o ]] || objects+=("$object")
done
if [[ "${BETTERSHOT_CHECK_SCROLL_CAPTURE:-0}" == "1" ]]; then
    swiftc -parse-as-library -module-cache-path .build/ExportCheckModules \
        -I "$derived/Build/Products/$configuration" Tests/ScrollCaptureIntegration.swift \
        "${objects[@]}" "$derived/Build/Products/$configuration/DockProgress.o" "$derived/Build/Products/$configuration/TourKit.o" "$derived/Build/Products/$configuration/DynamicNotchKit.o" \
        -o "$out/ScrollCaptureIntegration"
    BETTERSHOT_TESTING=1 "$out/ScrollCaptureIntegration"
    exit 0
fi
if [[ "${BETTERSHOT_CHECK_WINDOW_CAPTURE:-0}" == "1" ]]; then
    swiftc -parse-as-library -module-cache-path .build/ExportCheckModules \
        -I "$derived/Build/Products/$configuration" Tests/WindowCaptureIntegration.swift \
        "${objects[@]}" "$derived/Build/Products/$configuration/DockProgress.o" "$derived/Build/Products/$configuration/TourKit.o" "$derived/Build/Products/$configuration/DynamicNotchKit.o" \
        -o "$out/WindowCaptureIntegration"
    BETTERSHOT_TESTING=1 "$out/WindowCaptureIntegration"
    exit 0
fi
if [[ "${BETTERSHOT_CHECK_EDITOR_SCENES:-0}" == "1" ]]; then
    swiftc -parse-as-library -module-cache-path .build/ExportCheckModules \
        -I "$derived/Build/Products/$configuration" Tests/EditorSceneIntegration.swift \
        "${objects[@]}" "$derived/Build/Products/$configuration/DockProgress.o" "$derived/Build/Products/$configuration/TourKit.o" "$derived/Build/Products/$configuration/DynamicNotchKit.o" \
        -o "$out/EditorSceneIntegration"
    for editor in image video; do
        for automatic in 0 1; do
            BETTERSHOT_TESTING=1 "$out/EditorSceneIntegration" "$editor" "$automatic"
        done
    done
    exit 0
fi
swiftc -parse-as-library -module-cache-path .build/ExportCheckModules \
    -I "$derived/Build/Products/$configuration" Tests/ExportIntegration.swift Tests/EditorUIIntegration.swift Tests/ImageTransformIntegration.swift Tests/Recording3DIntegration.swift Tests/NotchIntegration.swift \
    "${objects[@]}" "$derived/Build/Products/$configuration/DockProgress.o" "$derived/Build/Products/$configuration/TourKit.o" "$derived/Build/Products/$configuration/DynamicNotchKit.o" \
    -o "$out/ExportIntegration"
# The snapshots instantiate sharing UI; do not read the real R2 Keychain from this test binary.
BETTERSHOT_TESTING=1 "$out/ExportIntegration"
