#!/usr/bin/env bash
set -euo pipefail

iterations="${FUZZ_ITERATIONS:-1000}"
seed="${FUZZ_SEED:-6003092301531665754}"
timeout="${FUZZ_TIMEOUT:-60}"

for sanitizer in address undefined; do
  FUZZING_ENABLE=1 swift run --sanitize "$sanitizer" SolidPostScriptFilterFuzz \
    --seed "$seed" \
    --iterations "$iterations" \
    --timeout "$timeout" \
    --artifacts ".fuzz-artifacts/$sanitizer/SolidPostScriptFilterFuzz"
done
