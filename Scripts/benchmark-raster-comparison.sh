#!/usr/bin/env bash

set -euo pipefail

readonly TARGET="SolidPostScriptRasterBenchmark"
readonly REFERENCE_BASELINE="plutovg-reference"
readonly CANDIDATE_BASELINE="native-candidate"

SWIFT_PACKAGE=(swift package)
SWIFT_TEST=(swift test)
if [[ -n "${SOLIDPDF_BENCHMARK_SCRATCH_PATH:-}" ]]; then
  SWIFT_PACKAGE+=(--scratch-path "${SOLIDPDF_BENCHMARK_SCRATCH_PATH}")
  SWIFT_TEST+=(--scratch-path "${SOLIDPDF_BENCHMARK_SCRATCH_PATH}")
fi

function benchmark() {
  BENCHMARK_ENABLE=1 "${SWIFT_PACKAGE[@]}" "$@"
}

function update_baseline() {
  local backend="$1"
  local baseline="$2"
  SOLIDPDF_RASTER_BENCHMARK_BACKEND="${backend}" benchmark \
    --allow-writing-to-directory .benchmarkBaselines \
    benchmark baseline update "${baseline}" \
    --target "${TARGET}" \
    --no-progress \
    --quiet
}

BENCHMARK_ENABLE=1 "${SWIFT_TEST[@]}" --filter RasterRendererBenchmarkTests

update_baseline plutovg "${REFERENCE_BASELINE}"
update_baseline native "${CANDIDATE_BASELINE}"

set +e
CHECK_OUTPUT="$(SOLIDPDF_RASTER_BENCHMARK_BACKEND=native benchmark \
  benchmark baseline check "${REFERENCE_BASELINE}" "${CANDIDATE_BASELINE}" \
  --target "${TARGET}" \
  --no-progress 2>&1)"
CHECK_STATUS=$?
set -e
printf '%s\n' "${CHECK_OUTPUT}"

if [[ ${CHECK_STATUS} -eq 1 && "${CHECK_OUTPUT}" == *benchmarkThresholdRegression* ]]; then
  CHECK_STATUS=2
fi
readonly CHECK_STATUS

SOLIDPDF_RASTER_BENCHMARK_BACKEND=native benchmark \
  benchmark baseline compare "${REFERENCE_BASELINE}" "${CANDIDATE_BASELINE}" \
  --target "${TARGET}" \
  --no-progress

if [[ -n "${SOLIDPDF_RASTER_BENCHMARK_EXPORT_DIRECTORY:-}" ]]; then
  mkdir -p "${SOLIDPDF_RASTER_BENCHMARK_EXPORT_DIRECTORY}"
  for backend in plutovg native; do
    SOLIDPDF_RASTER_BENCHMARK_BACKEND="${backend}" benchmark \
      --allow-writing-to-directory "${SOLIDPDF_RASTER_BENCHMARK_EXPORT_DIRECTORY}" \
      benchmark run \
      --target "${TARGET}" \
      --format jmh \
      --path "${SOLIDPDF_RASTER_BENCHMARK_EXPORT_DIRECTORY}/${backend}" \
      --no-progress
  done
fi

case "${CHECK_STATUS}" in
  0)
    echo "Raster benchmark gate passed: native p50 is within 2x PlutoVG."
    ;;
  4)
    echo "Raster benchmark gate passed: native is an improvement over PlutoVG."
    ;;
  2)
    echo "Raster benchmark gate failed: native path-heavy p50 exceeds 2x PlutoVG." >&2
    exit 2
    ;;
  *)
    echo "Raster benchmark infrastructure failed with status ${CHECK_STATUS}." >&2
    exit "${CHECK_STATUS}"
    ;;
esac
