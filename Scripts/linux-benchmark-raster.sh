#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIRECTORY

exec "${SCRIPT_DIRECTORY}/linux-container" exec \
  env BENCHMARK_ENABLE=1 \
  swift package --scratch-path /build benchmark --target SolidRasterBenchmark "$@"
