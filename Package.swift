// swift-tools-version: 6.3

import PackageDescription
import class Foundation.ProcessInfo

let foundationDependency: Package.Dependency =
  if let path = ProcessInfo.processInfo.environment["SOLIDPDF_FOUNDATION_PATH"] {
    .package(name: "solid-foundation", path: path)
  } else {
    .package(
      url: "https://github.com/solid-swift/solid-foundation.git",
      revision: "c372253a7bcca19d51c5dcc8328825a1c03d3bf5"
    )
  }

let imageDependency: Package.Dependency =
  if let path = ProcessInfo.processInfo.environment["SOLIDPDF_SOLIDIMAGE_PATH"] {
    .package(name: "solid-image", path: path)
  } else {
    .package(
      url: "https://github.com/solid-swift/solid-image.git",
      revision: "f4a1c6a035035768a7a7fb12ca822566244d4ed9"
    )
  }

let package = Package(
  name: "SolidPDF",
  platforms: [
    .macOS("26"),
    .iOS("26"),
    .tvOS("26"),
    .watchOS("26"),
  ],
  products: [
    .library(name: "SolidPDF", targets: ["SolidPDF"]),
    .library(name: "SolidFont", targets: ["SolidFont"]),
    .library(name: "SolidPostScript", targets: ["SolidPostScript"]),
    .library(name: "SolidPostScriptDocument", targets: ["SolidPostScriptDocument"]),
    .library(name: "SolidPostScriptPDF", targets: ["SolidPostScriptPDF"]),
    .library(name: "SolidPostScriptRaster", targets: ["SolidPostScriptRaster"]),
    .library(name: "SolidPostScriptCoreGraphics", targets: ["SolidPostScriptCoreGraphics"]),
    .library(name: "SolidPostScriptCoreText", targets: ["SolidPostScriptCoreText"]),
    .library(name: "SolidPostScriptFreeType", targets: ["SolidPostScriptFreeType"]),
    .library(name: "SolidPostScriptPlutoVG", targets: ["SolidPostScriptPlutoVG"]),
    .executable(name: "solid-ps", targets: ["solid-ps"]),
  ],
  dependencies: [
    foundationDependency,
    imageDependency,
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.0"),
    .package(url: "https://github.com/StarLard/SwiftFormatPlugins.git", from: "1.1.1"),
  ],
  targets: [
    .target(
      name: "SolidPDF",
      dependencies: [
        .product(name: "SolidIO", package: "solid-foundation"),
      ],
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidPDFTests",
      dependencies: ["SolidPDF"],
      plugins: lintPlugins
    ),
    .target(
      name: "SolidFont",
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidFontTests",
      dependencies: ["SolidFont"],
      plugins: lintPlugins
    ),
    .target(
      name: "SolidPostScript",
      dependencies: [
        "SolidFont",
        .product(name: "SolidColor", package: "solid-image"),
        .product(name: "SolidRaster", package: "solid-image"),
        .product(name: "SolidCore", package: "solid-foundation"),
        .product(name: "SolidIO", package: "solid-foundation"),
        .product(name: "SolidTempo", package: "solid-foundation"),
      ],
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidPostScriptTests",
      dependencies: [
        "SolidFont",
        "SolidPostScript",
        .product(name: "SolidColor", package: "solid-image"),
        .product(name: "SolidCore", package: "solid-foundation"),
        .product(name: "SolidIO", package: "solid-foundation"),
        .product(name: "SolidTempo", package: "solid-foundation"),
      ],
      plugins: lintPlugins
    ),
    .target(
      name: "SolidPostScriptCoreGraphics",
      dependencies: [
        "SolidFont",
        "SolidPostScript",
        "SolidPostScriptCoreText",
        .product(name: "SolidRaster", package: "solid-image"),
      ],
      plugins: lintPlugins
    ),
    .target(
      name: "SolidPostScriptCoreText",
      dependencies: ["SolidFont", "SolidPostScript"],
      plugins: lintPlugins
    ),
    .systemLibrary(
      name: "CFreeType",
      pkgConfig: "freetype2",
      providers: [
        .apt(["libfreetype-dev"]),
        .brew(["freetype"]),
      ]
    ),
    .systemLibrary(
      name: "CFontconfig",
      pkgConfig: "fontconfig",
      providers: [
        .apt(["libfontconfig1-dev"]),
        .brew(["fontconfig"]),
      ]
    ),
    .target(
      name: "SolidPostScriptFreeType",
      dependencies: [
        "SolidFont",
        "SolidPostScript",
        .target(name: "CFreeType", condition: .when(platforms: [.linux])),
        .target(name: "CFontconfig", condition: .when(platforms: [.linux])),
      ],
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidPostScriptFontBackendTests",
      dependencies: [
        "SolidPostScript",
        "SolidPostScriptCoreText",
        "SolidPostScriptFreeType",
      ],
      plugins: lintPlugins
    ),
    .target(
      name: "SolidPostScriptRaster",
      dependencies: [
        "SolidPostScript",
        .product(name: "SolidRaster", package: "solid-image"),
      ],
      plugins: lintPlugins
    ),
    .target(
      name: "SolidPostScriptDocument",
      dependencies: [
        "SolidPDF",
        "SolidPostScript",
        "SolidPostScriptPDF",
        "SolidPostScriptRaster",
        .product(name: "SolidRaster", package: "solid-image"),
      ],
      plugins: lintPlugins
    ),
    .target(
      name: "SolidPostScriptPDF",
      dependencies: [
        "SolidFont",
        "SolidPDF",
        "SolidPostScript",
        "SolidPostScriptRaster",
        .product(name: "SolidRaster", package: "solid-image"),
      ],
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidPostScriptPDFTests",
      dependencies: ["SolidFont", "SolidPDF", "SolidPostScript", "SolidPostScriptPDF"],
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidPostScriptDocumentTests",
      dependencies: [
        "SolidPDF",
        "SolidPostScript",
        "SolidPostScriptDocument",
        "SolidPostScriptPDF",
        "SolidPostScriptRaster",
        .product(name: "SolidIO", package: "solid-foundation"),
      ],
      plugins: lintPlugins
    ),
    .target(
      name: "SolidPostScriptConformanceSupport",
      dependencies: [
        "SolidPostScript",
        "SolidPostScriptDocument",
        "SolidPostScriptRaster",
        .product(name: "SolidRaster", package: "solid-image"),
        .product(name: "SolidRasterPNG", package: "solid-image"),
        .product(name: "SolidIO", package: "solid-foundation"),
      ],
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidPostScriptConformanceSupportTests",
      dependencies: ["SolidPostScriptConformanceSupport"],
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidPostScriptRasterTests",
      dependencies: [
        "SolidPostScript",
        "SolidPostScriptPlutoVG",
        "SolidPostScriptRaster",
        .product(name: "SolidColor", package: "solid-image"),
        .product(name: "SolidRaster", package: "solid-image"),
      ],
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidPostScriptCoreGraphicsTests",
      dependencies: ["SolidPostScript", "SolidPostScriptCoreGraphics", "SolidPostScriptCoreText"],
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
      dependencies: [
        "SolidPostScript",
        "SolidPostScriptRaster",
        "CPlutoVG",
        .product(name: "SolidRaster", package: "solid-image"),
      ],
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
    .executableTarget(
      name: "solid-ps",
      dependencies: [
        "SolidPDF",
        "SolidPostScript",
        "SolidPostScriptCoreText",
        "SolidPostScriptDocument",
        "SolidPostScriptFreeType",
        "SolidPostScriptPDF",
        "SolidPostScriptRaster",
        .product(name: "SolidRaster", package: "solid-image"),
        .product(name: "SolidRasterPNG", package: "solid-image"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "SolidIO", package: "solid-foundation"),
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

// Benchmarking
let benchmarkEnableEnvironment = ProcessInfo.processInfo.environment["BENCHMARK_ENABLE"]?.lowercased()
let benchmarkEnabled =
  if let benchmarkEnableEnvironment,
    benchmarkEnableEnvironment == "1"
      || benchmarkEnableEnvironment == "true"
      || benchmarkEnableEnvironment == "t"
  {
    true
  } else {
    false
  }

if benchmarkEnabled {
  package.dependencies += [
    .package(url: "https://github.com/ordo-one/benchmark", .upToNextMajor(from: "1.29.7")),
  ]
  package.targets += [
    .target(
      name: "SolidFontBenchmarkSupport",
      dependencies: ["SolidFont"],
      path: "Benchmarks/SolidFontBenchmarkSupport"
    ),
    .executableTarget(
      name: "SolidFontBenchmark",
      dependencies: [
        "SolidFont",
        "SolidFontBenchmarkSupport",
        .product(name: "Benchmark", package: "benchmark"),
      ],
      path: "Benchmarks/SolidFontBenchmark",
      plugins: [
        .plugin(name: "BenchmarkPlugin", package: "benchmark")
      ]
    ),
    .target(
      name: "SolidRasterBenchmarkSupport",
      dependencies: [
        "SolidPostScript",
        "SolidPostScriptPlutoVG",
        "SolidPostScriptRaster",
        .product(name: "SolidRaster", package: "solid-image"),
      ],
      path: "Benchmarks/SolidRasterBenchmarkSupport"
    ),
    .executableTarget(
      name: "SolidPostScriptRasterBenchmark",
      dependencies: [
        "SolidPostScript",
        "SolidPostScriptPlutoVG",
        "SolidPostScriptRaster",
        "SolidRasterBenchmarkSupport",
        .product(name: "SolidRaster", package: "solid-image"),
        .product(name: "Benchmark", package: "benchmark"),
      ],
      path: "Benchmarks/SolidPostScriptRasterBenchmark",
      plugins: [
        .plugin(name: "BenchmarkPlugin", package: "benchmark")
      ]
    ),
    .executableTarget(
      name: "SolidPostScriptPageDeviceBenchmark",
      dependencies: [
        "SolidPostScript",
        .product(name: "Benchmark", package: "benchmark"),
      ],
      path: "Benchmarks/SolidPostScriptPageDeviceBenchmark",
      plugins: [
        .plugin(name: "BenchmarkPlugin", package: "benchmark")
      ]
    ),
    .testTarget(
      name: "SolidRasterBenchmarkSupportTests",
      dependencies: [
        "SolidPostScript",
        "SolidPostScriptPlutoVG",
        "SolidPostScriptRaster",
        "SolidRasterBenchmarkSupport",
        .product(name: "SolidRaster", package: "solid-image"),
      ],
      path: "Tests/SolidRasterBenchmarkSupportTests",
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidFontBenchmarkSupportTests",
      dependencies: ["SolidFont", "SolidFontBenchmarkSupport"],
      path: "Tests/SolidFontBenchmarkSupportTests",
      plugins: lintPlugins
    ),
  ]
}

// Deterministic sanitizer fuzzing
let fuzzingEnableEnvironment = ProcessInfo.processInfo.environment["FUZZING_ENABLE"]?.lowercased()
let fuzzingEnabled =
  if let fuzzingEnableEnvironment,
    fuzzingEnableEnvironment == "1"
      || fuzzingEnableEnvironment == "true"
      || fuzzingEnableEnvironment == "t"
  {
    true
  } else {
    false
  }

if fuzzingEnabled {
  package.targets += [
    .executableTarget(
      name: "SolidPostScriptFilterFuzz",
      dependencies: [
        "SolidPostScript",
        .product(name: "SolidFuzzSupport", package: "solid-foundation"),
      ],
      path: "Fuzzing/SolidPostScriptFilterFuzz"
    ),
  ]
}

// Independent PostScript conformance validation
let conformanceEnableEnvironment = ProcessInfo.processInfo.environment["CONFORMANCE_ENABLE"]?.lowercased()
let conformanceEnabled =
  if let conformanceEnableEnvironment,
    conformanceEnableEnvironment == "1"
      || conformanceEnableEnvironment == "true"
      || conformanceEnableEnvironment == "t"
  {
    true
  } else {
    false
  }

if conformanceEnabled {
  package.targets += [
    .executableTarget(
      name: "solid-ps-conformance",
      dependencies: [
        "SolidPostScriptConformanceSupport",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Conformance/solid-ps-conformance",
      plugins: lintPlugins
    ),
  ]
}
