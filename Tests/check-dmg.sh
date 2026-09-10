#!/bin/bash
set -euo pipefail
export BETTERSHOT_TESTING=1

if [[ $# != 2 ]]; then
    echo "Usage: bash Tests/check-dmg.sh installer.dmg source/BetterShot.app" >&2
    exit 1
fi
MOUNT_DIR="$(mktemp -d)"
trap 'hdiutil detach "$MOUNT_DIR" >/dev/null; rmdir "$MOUNT_DIR"' EXIT
hdiutil verify "$1" >/dev/null
hdiutil attach "$1" -readonly -nobrowse -noautoopen -mountpoint "$MOUNT_DIR" >/dev/null
test "$(readlink "$MOUNT_DIR/Applications")" = /Applications
test -s "$MOUNT_DIR/.DS_Store"
cmp "$MOUNT_DIR/.VolumeIcon.icns" "$2/Contents/Resources/AppIcon.icns"
diff -qr "$MOUNT_DIR/BetterShot.app" "$2"

python3 - "$MOUNT_DIR/.DS_Store" <<'PY'
import pathlib, plistlib, struct, sys
data = pathlib.Path(sys.argv[1]).read_bytes()

def blob(key):
    offset = data.index(key + b'blob') + len(key) + 4
    length = struct.unpack_from('>I', data, offset)[0]
    return data[offset + 4:offset + 4 + length]

window = plistlib.loads(blob(b'bwsp'))
assert not window['ShowToolbar'] and not window['ShowStatusBar'] and not window['ShowSidebar']
assert '{660, 468}' in window['WindowBounds']
icons = plistlib.loads(blob(b'icvp'))
assert icons['iconSize'] == 128 and icons['arrangeBy'] == 'none'
assert icons['backgroundType'] == 2
for name, position in [('BetterShot.app', (180, 230)), ('Applications', (480, 230))]:
    location = blob(name.encode('utf-16be') + b'Iloc')
    assert struct.unpack_from('>II', location) == position, name
PY

xcrun swift - "$MOUNT_DIR/.background/background.tiff" <<'SWIFT'
import AppKit
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let reps = NSBitmapImageRep.imageReps(with: data).compactMap { $0 as? NSBitmapImageRep }
assert(reps.count == 2, "Missing Retina or standard background")
for rep in reps {
    assert(rep.size == NSSize(width: 660, height: 440))
    assert([660, 1320].contains(rep.pixelsWide))
    assert(rep.pixelsHigh * 3 == rep.pixelsWide * 2)
    // Catch double scaling: the arrow must stay between the two native icons.
    let scale = rep.pixelsWide / 660
    let arrow = rep.colorAt(x: 320 * scale, y: 230 * scale)!.usingColorSpace(.sRGB)!
    assert(arrow.redComponent < 0.7 && arrow.blueComponent > 0.6,
           "Arrow missing from the center of the installation row")
}
SWIFT
echo "PASS: DMG integrity, unchanged app, Applications link, Finder layout file, volume icon, and 1×/2× artwork"
