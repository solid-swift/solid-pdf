#!/usr/bin/env bash
set -euo pipefail

BENCHMARK_ENABLE=1 swift package benchmark --target SolidRasterBenchmark "$@"
