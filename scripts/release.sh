#!/bin/bash
set -euo pipefail

# BetterShot Release Script
# Builds, signs, notarizes, and creates DMGs for both architectures.
#
# Prerequisites:
#   1. Developer ID Application certificate in keychain
#   2. Notarization credentials stored:
#      xcrun notarytool store-credentials "bettershot-notary" --apple-id YOUR_APPLE_ID --team-id 8JL39GK2DC
#
# Usage:
#   ./scripts/release.sh          # Uses version from version.json
#   ./scripts/release.sh 0.4.0    # Override version

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

VERSION="${1:-$(python3 -c "import json; print(json.load(open('version.json'))['version'])")}"
SIGNING_IDENTITY="Developer ID Application: Kartik Labhshetwar (8JL39GK2DC)"
TEAM_ID="8JL39GK2DC"
NOTARY_PROFILE="bettershot-notary"
ENTITLEMENTS="Resources/BetterShot.entitlements"
RELEASE_DIR="$PROJECT_DIR/release"

echo "=== BetterShot v$VERSION Release Build ==="
echo ""

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

build_arch() {
    local ARCH=$1
    local LABEL=$2
    local BUILD_DIR="$RELEASE_DIR/build-$ARCH"

    echo "[$LABEL] Building..."
    xcodebuild -scheme BetterShot \
        -configuration Release \
        -arch "$ARCH" \
        -derivedDataPath "$BUILD_DIR" \
        ONLY_ACTIVE_ARCH=NO \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        build 2>&1 | tail -1

    local APP_PATH="$BUILD_DIR/Build/Products/Release/BetterShot.app"

    echo "[$LABEL] Signing..."
    codesign --deep --force --options runtime \
        --sign "$SIGNING_IDENTITY" \
        --entitlements "$ENTITLEMENTS" \
        "$APP_PATH"

    codesign --verify --deep --strict "$APP_PATH"
    echo "[$LABEL] Signature verified."

    local DMG_NAME="BetterShot-${VERSION}_${ARCH}.dmg"
    local DMG_PATH="$RELEASE_DIR/$DMG_NAME"
    local STAGING="$RELEASE_DIR/staging-$ARCH"

    mkdir -p "$STAGING"
    cp -R "$APP_PATH" "$STAGING/"
    ln -sf /Applications "$STAGING/Applications"

    echo "[$LABEL] Creating DMG..."
    hdiutil create -volname "BetterShot" \
        -srcfolder "$STAGING" \
        -ov -format UDZO \
        "$DMG_PATH" 2>/dev/null

    codesign --sign "$SIGNING_IDENTITY" "$DMG_PATH"

    echo "[$LABEL] Notarizing..."
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    echo "[$LABEL] Stapling..."
    xcrun stapler staple "$DMG_PATH"

    rm -rf "$STAGING" "$BUILD_DIR"
    echo "[$LABEL] Done: $DMG_NAME"
}

build_arch "arm64" "Apple Silicon"
echo ""
build_arch "x86_64" "Intel"

echo ""
echo "=== Release Complete ==="
ls -lh "$RELEASE_DIR"/*.dmg
echo ""
echo "Next steps:"
echo "  git add -A && git commit -m 'release: v$VERSION'"
echo "  git tag v$VERSION"
echo "  git push origin main && git push origin v$VERSION"
