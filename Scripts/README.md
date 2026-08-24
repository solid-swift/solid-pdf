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
Scripts/linux-conformance
```

Use `linux-container` to inspect or control the reusable environment:

```shell
Scripts/linux-container status
Scripts/linux-container shell
Scripts/linux-container stop
Scripts/linux-container remove
```

Each checkout and target platform has one stable container identity. A matching container is reused and restarted as needed. Changing the Swift image, dependency generation, script schema, or expected mounts replaces that stable container in place while preserving its build, dependency, and benchmark volumes. Lifecycle operations are serialized per checkout and platform so concurrent build, test, benchmark, and shell invocations cannot create competing containers.

The first invocation after this lifecycle change removes inactive legacy containers for the exact checkout and platform. It never migrates containers for another worktree, platform, or temporary benchmark checkout, and it refuses to replace a container with an active Docker exec session. Legacy volumes are deliberately preserved; inspect them with `docker volume ls` and remove them manually after confirming they are no longer needed.

`status` reports the requested and installed configuration fingerprints, replacement need, stable mounts, and eligible legacy containers. `stop` preserves the container and volumes. `remove` deletes only the stable container and preserves its build, dependency, and benchmark caches; the next build recreates and starts it.

The defaults follow the host Docker daemon's architecture and use `swift:6.3.3`. Override them when an explicit architecture or toolchain is required:

```shell
SOLIDPDF_LINUX_PLATFORM=linux/amd64 Scripts/linux-build
SOLIDPDF_LINUX_SWIFT_IMAGE=swift:6.3.3-jammy Scripts/linux-test
```

Each checkout and target platform receives distinct stable container and volume names, so worktrees and cross-architecture builds do not share incompatible products or baselines. Swift-image and script updates reuse those volumes after replacing the container. The writable `Package.resolved` mount is refreshed whenever the checkout copy changes. Container creation also installs the FreeType and Fontconfig development packages required by `SolidPostScriptFreeType`, qpdf, MuPDF, and Poppler for generated-PDF interoperability checks, and the compiler utilities needed by the independent conformance reference.

# PostScript conformance

`Scripts/conformance` prepares the checksummed Ghostscript 10.07.1 reference and runs the owned suite. The reference is cached beneath `~/.cache/solidpdf/conformance`; Linux uses the existing persistent dependency-cache volume rather than a separate container. An already installed reference can be selected explicitly:

```shell
SOLIDPDF_GHOSTSCRIPT_EXECUTABLE=/opt/ghostscript/bin/gs Scripts/conformance
SOLIDPDF_CONFORMANCE_REFERENCE=0 Scripts/conformance
Scripts/linux-conformance
```

The first form performs adjudicated differential validation. Setting `SOLIDPDF_CONFORMANCE_REFERENCE=0` runs only checked-in Solid expectations. Reference programs execute as a separate AGPL tool and are never linked into or distributed with SolidPDF.

`Scripts/conformance-discovery` executes an external PS/EPS directory as discovery-only cases. By default it uses
examples extracted from the checksummed Ghostscript source archive and compares them with the reviewed observational
baseline. Exact known outcomes pass while remaining visible in reports; source, reference, or outcome drift exits 2.
Every run stages `candidate-baseline.json`, but never replaces the reviewed baseline. Set
`SOLIDPDF_EXTERNAL_CONFORMANCE_CORPUS` to inspect another directory without a baseline, or also set
`SOLIDPDF_CONFORMANCE_DISCOVERY_BASELINE`, `SOLIDPDF_CONFORMANCE_DISCOVERY_CORPUS_VERSION`, and
`SOLIDPDF_CONFORMANCE_DISCOVERY_ARCHIVE_SHA256` to compare a separately reviewed corpus. External programs remain
outside the repository, and a known observational outcome is not a PLRM-adjudicated accepted difference.

# Graphics API compatibility

After building, `Scripts/check-graphics-api` diagnoses SolidPDF-owned public library products against the
checked-in Swift 6.3 platform baseline. SolidColor, SolidRaster, and SolidRasterPNG are checked by SolidImage.
A deliberate public API change requires
`Scripts/check-graphics-api update`, review of the resulting diff, and an explicit semantic-contract
version decision. Linux baselines are generated and checked through the reusable container so C
system-module availability matches supported Linux builds.
