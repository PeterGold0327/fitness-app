#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Linux setup validates the portable core. iOS compilation still requires macOS/Xcode.
if ! command -v swift >/dev/null 2>&1 && [[ ! -x /workspace/.fitness-tools/swift-6.0.3/usr/bin/swift ]]; then
    if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
        echo "Install Swift 5.9+ for this platform, then rerun scripts/test-core.sh." >&2
        exit 1
    fi
    fitness_download_dir="$(mktemp -d)"
    trap 'rm -rf "$fitness_download_dir"' EXIT
    curl --fail --location --retry 2 \
        https://download.swift.org/swift-6.0.3-release/ubuntu2204/swift-6.0.3-RELEASE/swift-6.0.3-RELEASE-ubuntu22.04.tar.gz \
        -o "$fitness_download_dir/swift.tar.gz"
    # Pin the artifact obtained from Apple's official HTTPS download endpoint.
    printf '%s  %s\n' '09d0a53fbddf2878673dd12c1504e7143c788f195caec9f2329740946eba525c' "$fitness_download_dir/swift.tar.gz" | sha256sum --check -
    mkdir -p /workspace/.fitness-tools
    tar -xzf "$fitness_download_dir/swift.tar.gz" -C "$fitness_download_dir"
    mv "$fitness_download_dir/swift-6.0.3-RELEASE-ubuntu22.04" /workspace/.fitness-tools/swift-6.0.3
fi
bash scripts/test-core.sh
