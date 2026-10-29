#!/bin/bash
# Run after make test. Custom builds can set BETTERSHOT_DERIVED_DATA.
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp -d)"
program="ExportIntegration-$$"
trap 'rm -rf "$out"; defaults delete "$program" >/dev/null 2>&1 || true; rm -f "$HOME/Library/Preferences/$program.plist"' EXIT
arch="$(uname -m)"
configuration="${BETTERSHOT_BUILD_CONFIGURATION:-Debug}"
test_compile_flags=()
if [[ "$configuration" == "Debug" ]]; then test_compile_flags+=(-DDEBUG); fi
derived="${BETTERSHOT_DERIVED_DATA:-.build/tests}"
objects=()
for object in "$derived"/Build/Intermediates.noindex/BetterShot.build/"$configuration"/BetterShot.build/Objects-normal/"$arch"/*.o; do
    [[ "$object" == */BetterShotApp.o ]] || objects+=("$object")
done
package_objects=("$derived"/Build/Products/"$configuration"/*.o)
module_flags=()
for map in "$derived"/SourcePackages/checkouts/*/Sources/*/include/module.modulemap \
           "$derived"/Build/Intermediates.noindex/GeneratedModuleMaps/CNIO*.modulemap; do
    [[ -f "$map" ]] && module_flags+=(-Xcc "-fmodule-map-file=$map")
done
if [[ "${BETTERSHOT_CHECK_SCROLL_CAPTURE:-0}" == "1" ]]; then
    swiftc -parse-as-library -module-cache-path .build/ExportCheckModules \
        -I "$derived/Build/Products/$configuration" "${module_flags[@]}" Tests/ScrollCaptureIntegration.swift \
        "${objects[@]}" "${package_objects[@]}" \
        -o "$out/ScrollCaptureIntegration"
    BETTERSHOT_TESTING=1 "$out/ScrollCaptureIntegration"
    exit 0
fi
if [[ "${BETTERSHOT_CHECK_WINDOW_CAPTURE:-0}" == "1" ]]; then
    swiftc -parse-as-library -module-cache-path .build/ExportCheckModules \
        -I "$derived/Build/Products/$configuration" "${module_flags[@]}" Tests/WindowCaptureIntegration.swift \
        "${objects[@]}" "${package_objects[@]}" \
        -o "$out/WindowCaptureIntegration"
    BETTERSHOT_TESTING=1 "$out/WindowCaptureIntegration"
    exit 0
fi
if [[ "${BETTERSHOT_CHECK_EDITOR_SCENES:-0}" == "1" ]]; then
    swiftc -parse-as-library -module-cache-path .build/ExportCheckModules \
        -I "$derived/Build/Products/$configuration" "${module_flags[@]}" Tests/EditorSceneIntegration.swift \
        "${objects[@]}" "${package_objects[@]}" \
        -o "$out/EditorSceneIntegration"
    for editor in image video; do
        for automatic in 0 1; do
            BETTERSHOT_TESTING=1 "$out/EditorSceneIntegration" "$editor" "$automatic"
        done
    done
    exit 0
fi
swiftc -parse-as-library -module-name ExportIntegration "${test_compile_flags[@]+"${test_compile_flags[@]}"}" -module-cache-path .build/ExportCheckModules \
    -I "$derived/Build/Products/$configuration" "${module_flags[@]}" Tests/ExportIntegration.swift Tests/EditorUIIntegration.swift Tests/RecordingAgentAccessIntegration.swift Tests/RecordingMultiSourceRenderingIntegration.swift Tests/RecordingMultiSourceCompositorIntegration.swift Tests/RecordingMultiSourceModelIntegration.swift Tests/RecordingMultiSourceUIIntegration.swift Tests/RecordingNestedImportIntegration.swift Tests/RecordingAgentEffectsIntegration.swift Tests/RecordingAgentMultiSourceIntegration.swift Tests/ImageTransformIntegration.swift Tests/Recording3DIntegration.swift \
    "${objects[@]}" "${package_objects[@]}" \
    -o "$out/$program"
executable="$out/$program"
if [[ "${BETTERSHOT_CHECK_MULTI_SOURCE_WINDOWS:-0}" == "1" ]]; then
    bundle="$out/$program.app"
    mkdir -p "$bundle/Contents/MacOS"
    mv "$executable" "$bundle/Contents/MacOS/$program"
    cat > "$bundle/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$program</string>
    <key>CFBundleIdentifier</key><string>$program</string>
    <key>CFBundleName</key><string>$program</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
    executable="$bundle/Contents/MacOS/$program"
    printf 'INFO displayed fixture app=%s bundleId=%s\n' "$bundle" "$program"
fi
# The snapshots instantiate sharing UI; do not read the real R2 Keychain from this test binary.
BETTERSHOT_TESTING=1 "$executable"
