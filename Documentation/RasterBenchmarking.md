# Raster benchmarking

Raster performance tests use [Ordo One Benchmark](https://github.com/ordo-one/benchmark) and are excluded from ordinary dependency resolution, builds, and tests. Set `BENCHMARK_ENABLE=1` whenever invoking Benchmark directly.

## Native microbenchmarks

Run the direct `RasterCanvas` workloads with:

```shell
Scripts/benchmark-raster.sh
```

The suite covers flat fills, one thousand cubic segments, dashed strokes, deep clipping, and nearest and bilinear 8-megapixel images. It reports elapsed and CPU time, throughput, allocation count, and peak resident-memory delta. Fixtures are constructed before measurement, while each iteration includes fresh canvas creation, drawing, output allocation, and finalization.

## Native versus PlutoVG

Run the complete same-checkout comparison and acceptance gate with:

```shell
Scripts/benchmark-raster-comparison.sh
```

The wrapper first runs the renderer-fixture differential tests, records a `plutovg-reference` baseline, records a `native-candidate` baseline, checks configured thresholds, and prints the percentile comparison. Both runs register identical target and benchmark names. `SOLIDPDF_RASTER_BENCHMARK_BACKEND` selects `native` or `plutovg`; an omitted value defaults to `native`, and any unknown value fails during benchmark registration.

The acceptance threshold applies only to `Combined Path-Heavy Page`: native Swift's wall-clock p50 must not exceed 200 percent of PlutoVG's p50. The individual workloads are diagnostic and do not independently fail the gate.

Benchmark's baseline-check statuses are interpreted as follows:

- `0`: within tolerance; pass.
- `4`: improvement; pass.
- `2`: regression; fail the 2x gate.
- Any other nonzero value: benchmark infrastructure failure.

SwiftPM can collapse a Benchmark plugin status to `1`; the wrapper recognizes Benchmark's `benchmarkThresholdRegression` diagnostic and preserves it as gate failure `2`, while treating other status-1 failures as infrastructure errors.

Baselines under `.benchmarkBaselines` are transient and intentionally untracked because Benchmark does not guarantee their internal format. To retain supported JMH exports, provide a destination:

```shell
SOLIDPDF_RASTER_BENCHMARK_EXPORT_DIRECTORY=/tmp/solidpdf-raster-results \
  Scripts/benchmark-raster-comparison.sh
```

Only compare runs made on the same otherwise-idle machine, checkout, build configuration, power policy, and target architecture. Dependable automated comparisons require a dedicated runner; these benchmarks deliberately do not run in ordinary CI.

## Linux

The persistent Swift container provides writable build, dependency-cache, and benchmark-baseline volumes while keeping source files read-only. It mounts an ignored writable `Package.resolved` copy so Benchmark's Linux-only dependencies can resolve without changing the checkout:

```shell
Scripts/linux-benchmark-raster.sh
Scripts/linux-benchmark-raster-comparison.sh
```

Future renderer cases such as CoreGraphics, Accelerate, or Metal should add a backend-specific generic registration branch while preserving the existing workload and benchmark names.
