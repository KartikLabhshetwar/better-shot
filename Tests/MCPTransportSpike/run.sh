#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
package_path="$repo_root/Tests/MCPTransportSpike"
scratch_path="$(mktemp -d "${TMPDIR:-/private/tmp}/bettershot-mcp-spike.XXXXXX")"
trap 'rm -rf -- "$scratch_path"' EXIT

mkdir -p "$scratch_path/clang" "$scratch_path/swift"
export CLANG_MODULE_CACHE_PATH="$scratch_path/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$scratch_path/swift"
export BETTERSHOT_TESTING=1

swift_flags=(
    --package-path "$package_path"
    --cache-path "$scratch_path/packages"
    --scratch-path "$scratch_path/build"
    --manifest-cache local
    --force-resolved-versions
)
if [[ "${BETTERSHOT_MCP_SPIKE_DISABLE_SANDBOX:-0}" == "1" ]]; then
    swift_flags+=(--disable-sandbox)
fi

swift run "${swift_flags[@]}" MCPTransportSpike
swift build "${swift_flags[@]}" --target MCPAppSettingsCheck
echo "PASS: SDK consumer compiled with BetterShot Swift settings"
