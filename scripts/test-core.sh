#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n "${SWIFT_BIN:-}" ]]; then
    fitness_swift="$SWIFT_BIN"
elif command -v swift >/dev/null 2>&1; then
    fitness_swift="$(command -v swift)"
else
    fitness_swift="/workspace/.fitness-tools/swift-6.0.3/usr/bin/swift"
fi
if [[ ! -x "$fitness_swift" ]]; then
    echo "Swift not found. Install Swift 5.9+ or set SWIFT_BIN to its executable." >&2
    exit 1
fi
# Cloud home directories are read-only. Keep compiler and package caches writable.
fitness_cache="${TMPDIR:-/tmp}/leanlog-swift-cache"
mkdir -p "$fitness_cache"/{clang,packages,config,security}
export CLANG_MODULE_CACHE_PATH="$fitness_cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$fitness_cache/clang"
"$fitness_swift" test --cache-path "$fitness_cache/packages" --config-path "$fitness_cache/config" \
    --security-path "$fitness_cache/security" --jobs 2
