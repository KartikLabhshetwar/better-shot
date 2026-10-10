#!/usr/bin/env python3
"""Fails when a Swift source names an SF Symbol that is missing or newer than version.json's minimumOS."""
import json
import plistlib
import re
import sys
from pathlib import Path

AVAILABILITY = Path("/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist")
SOURCE_ROOTS = ("Sources", "Vendor/TourKit/Sources")
SYMBOL_ARGUMENT = re.compile(r"\b(systemName|systemImage|systemSymbolName)\s*:")
LITERAL = re.compile(r'"([a-z0-9]+(?:\.[a-z0-9]+)*)"')


def version_tuple(version):
    return tuple(int(part) for part in version.split("."))


def main(root):
    minimum = version_tuple(json.loads((root / "version.json").read_text())["minimumOS"])
    catalog = plistlib.loads(AVAILABILITY.read_bytes())
    introduced = {
        name: catalog["year_to_release"][year]["macOS"]
        for name, year in catalog["symbols"].items()
    }
    problems = []
    for source_root in SOURCE_ROOTS:
        for path in sorted((root / source_root).rglob("*.swift")):
            for number, line in enumerate(path.read_text().splitlines(), 1):
                in_symbol_argument = bool(SYMBOL_ARGUMENT.search(line))
                for name in LITERAL.findall(line):
                    location = f"{path.relative_to(root)}:{number}"
                    if name in introduced:
                        if version_tuple(introduced[name]) > minimum:
                            problems.append(f"{location}: '{name}' needs macOS {introduced[name]}")
                    elif in_symbol_argument:
                        problems.append(f"{location}: '{name}' is not an SF Symbol on this system")
    for problem in problems:
        print(problem)
    if problems:
        return 1
    print(f"SF Symbols available on macOS {'.'.join(map(str, minimum))}")
    return 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1] if len(sys.argv) > 1 else ".")))
