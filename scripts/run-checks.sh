#!/bin/bash
set -u
out="$(mktemp -d)"
failed=0

for src in Tests/*Check.swift; do
    name="$(basename "$src" .swift)"
    extra=()
    if [ -f "Tests/$name.sources" ]; then
        while IFS= read -r dep; do
            [ -n "$dep" ] && extra+=("$dep")
        done < "Tests/$name.sources"
    fi
    if ! swiftc -swift-version 6 -enable-actor-data-race-checks -o "$out/$name" "$src" "${extra[@]+"${extra[@]}"}" 2>"$out/$name.build"; then
        echo "FAIL (build) $name"
        cat "$out/$name.build"
        failed=1
        continue
    fi
    if BETTERSHOT_TESTING=1 "$out/$name" >"$out/$name.run" 2>&1; then
        echo "PASS $name: $(tail -1 "$out/$name.run")"
    else
        echo "FAIL (run, exit $?) $name"
        cat "$out/$name.run"
        failed=1
    fi
done

if command -v node >/dev/null 2>&1 && [ -f bettershot-landing/scripts/share-check.mts ]; then
    if (cd bettershot-landing && node scripts/share-check.mts) >"$out/ShareOriginCheck.run" 2>&1; then
        echo "PASS ShareOriginCheck: $(tail -1 "$out/ShareOriginCheck.run")"
    else
        echo "FAIL (run) ShareOriginCheck"
        cat "$out/ShareOriginCheck.run"
        failed=1
    fi
fi

rm -rf "$out"
exit $failed
