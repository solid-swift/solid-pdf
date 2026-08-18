# Linux development

The Linux scripts run SolidPDF in a persistent official Swift container without mixing Linux artifacts into the host `.build` directory. The repository is mounted read-only at `/workspace`; SwiftPM dependencies and products live in Docker volumes mounted at `/build` and `/root/.cache`. Benchmark baselines use a writable volume mounted over `/workspace/.benchmarkBaselines`. An ignored writable copy of `Package.resolved` is mounted over the source file so conditional Linux-only dependencies can resolve without modifying the checkout.

The container is created and started automatically by either wrapper:

```shell
Scripts/linux-build
Scripts/linux-test
```

Arguments are forwarded directly to SwiftPM:

```shell
Scripts/linux-build --target SolidPostScriptPlutoVG
Scripts/linux-test --filter PlutoVGImageTargetTests
ENABLE_LINT=1 Scripts/linux-build
Scripts/linux-benchmark-raster.sh --filter "Flat Fill"
Scripts/linux-benchmark-raster-comparison.sh
```

Use `linux-container` to inspect or control the reusable environment:

```shell
Scripts/linux-container status
Scripts/linux-container shell
Scripts/linux-container stop
Scripts/linux-container remove
```

`stop` preserves the container and volumes. `remove` deletes only the replaceable container and preserves its build, dependency, and benchmark caches; the next build recreates and starts it.

The defaults follow the host Docker daemon's architecture and use `swift:6.3.3`. Override them when an explicit architecture or toolchain is required:

```shell
SOLIDPDF_LINUX_PLATFORM=linux/amd64 Scripts/linux-build
SOLIDPDF_LINUX_SWIFT_IMAGE=swift:6.3.3-jammy Scripts/linux-test
```

Each checkout, Swift image, and target platform receives a distinct container and set of volumes, so worktrees and cross-architecture builds do not share incompatible products or baselines.
