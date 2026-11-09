#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="${TIME_TRACKER_BUILD_DIR:-$ROOT/../../work/swift-build}"
export CLANG_MODULE_CACHE_PATH="$SCRATCH/module-cache"
swift test --disable-xctest --disable-sandbox --cache-path "$SCRATCH/cache" --config-path "$SCRATCH/config" --security-path "$SCRATCH/security" --package-path "$ROOT" --scratch-path "$SCRATCH"
