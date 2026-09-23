#!/bin/zsh

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
LABEL="${1:-after}"
OUTPUT_DIR="${ROOT}/tmp/codex/performance/${LABEL}"
BUILD_DIR="${ROOT}/tmp/codex/performance/build"
MODULE_CACHE="${ROOT}/tmp/codex/performance/module-cache"
OUTPUT_FILE="${OUTPUT_DIR}/mica-performance.json"

mkdir -p "${OUTPUT_DIR}" "${BUILD_DIR}" "${MODULE_CACHE}"

export CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}"
export SWIFTPM_MODULECACHE_OVERRIDE="${MODULE_CACHE}"
export MICA_RUN_PERFORMANCE_BENCHMARKS=1
export MICA_PERFORMANCE_LABEL="${LABEL}"
export MICA_PERFORMANCE_OUTPUT="${OUTPUT_FILE}"
export MICA_SWIFT_VERSION="$(swift --version | tr '\n' ' ')"

swift test \
  --configuration release \
  --disable-automatic-resolution \
  --scratch-path "${BUILD_DIR}" \
  --filter MicaPerformanceBenchmarkTests

print -r -- "${OUTPUT_FILE}"
