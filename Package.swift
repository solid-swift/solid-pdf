// swift-tools-version: 6.3

import PackageDescription
import class Foundation.ProcessInfo

let package = Package(
  name: "SolidPDF",
  platforms: [
    .macOS("26"),
    .iOS("26"),
    .tvOS("26"),
    .watchOS("26"),
  ],
  products: [
    .executable(name: "SolidRasterBenchmark", targets: ["SolidRasterBenchmark"]),
    .library(name: "SolidRaster", targets: ["SolidRaster"]),
    .library(name: "SolidPostScript", targets: ["SolidPostScript"]),
    .library(name: "SolidPostScriptRaster", targets: ["SolidPostScriptRaster"]),
    .library(name: "SolidPostScriptCoreGraphics", targets: ["SolidPostScriptCoreGraphics"]),
    .library(name: "SolidPostScriptPlutoVG", targets: ["SolidPostScriptPlutoVG"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/solid-swift/solid-foundation.git",
      revision: "0d229d759279998ca1e865a7ab654cea16275819"
    ),
    .package(url: "https://github.com/StarLard/SwiftFormatPlugins.git", from: "1.1.1"),
  ],
  targets: [
    .executableTarget(
      name: "SolidRasterBenchmark",
      dependencies: ["SolidRaster"]
    ),
    .target(
      name: "SolidRaster",
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidRasterTests",
      dependencies: ["SolidRaster"],
      plugins: lintPlugins
    ),
    .target(
      name: "SolidPostScript",
      dependencies: [
        .product(name: "SolidCore", package: "solid-foundation"),
        .product(name: "SolidIO", package: "solid-foundation"),
        .product(name: "SolidTempo", package: "solid-foundation"),
      ],
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidPostScriptTests",
      dependencies: [
        "SolidPostScript",
        .product(name: "SolidCore", package: "solid-foundation"),
        .product(name: "SolidIO", package: "solid-foundation"),
        .product(name: "SolidTempo", package: "solid-foundation"),
      ],
      plugins: lintPlugins
    ),
    .target(
      name: "SolidPostScriptCoreGraphics",
      dependencies: ["SolidPostScript"],
      plugins: lintPlugins
    ),
    .target(
      name: "SolidPostScriptRaster",
      dependencies: ["SolidPostScript", "SolidRaster"],
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidPostScriptRasterTests",
      dependencies: ["SolidPostScript", "SolidPostScriptRaster", "SolidRaster"],
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidPostScriptCoreGraphicsTests",
      dependencies: ["SolidPostScript", "SolidPostScriptCoreGraphics"],
      plugins: lintPlugins
    ),
    .target(
      name: "CPlutoVG",
      path: "Vendor/PlutoVG",
      sources: [
        "source/plutovg-blend.c",
        "source/plutovg-canvas.c",
        "source/plutovg-font.c",
        "source/plutovg-ft-math.c",
        "source/plutovg-ft-raster.c",
        "source/plutovg-ft-stroker.c",
        "source/plutovg-matrix.c",
        "source/plutovg-paint.c",
        "source/plutovg-path.c",
        "source/plutovg-rasterize.c",
        "source/plutovg-surface.c",
      ],
      publicHeadersPath: "include",
      cSettings: [
        .define("PLUTOVG_BUILD_STATIC"),
        .define("PLUTOVG_DISABLE_FONT_FACE_CACHE_LOAD"),
        .headerSearchPath("source"),
      ],
      linkerSettings: [.linkedLibrary("m")]
    ),
    .target(
      name: "SolidPostScriptPlutoVG",
      dependencies: ["SolidPostScript", "SolidRaster", "CPlutoVG"],
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidPostScriptPlutoVGTests",
      dependencies: [
        "SolidPostScript",
        "SolidPostScriptCoreGraphics",
        "SolidPostScriptPlutoVG",
      ],
      plugins: lintPlugins
    ),
  ],
  swiftLanguageModes: [.v6]
)

let lintEnableEnvironment = ProcessInfo.processInfo.environment["ENABLE_LINT"]?.lowercased()
let lintEnabled =
  if let lintEnableEnvironment,
    lintEnableEnvironment == "1" || lintEnableEnvironment == "true" || lintEnableEnvironment == "t"
  {
    true
  } else {
    false
  }
let lintPlugins: [Target.PluginUsage] =
  lintEnabled
  ? [.plugin(name: "Lint", package: "swiftformatplugins")]
  : []
