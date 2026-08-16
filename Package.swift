// swift-tools-version: 6.2

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
    .library(name: "SolidPostScript", targets: ["SolidPostScript"])
  ],
  dependencies: [
    .package(
      url: "https://github.com/solid-swift/solid-foundation.git",
      revision: "8c7e40c7b98e700e6c8dc35e46ccfc57898abb33"
    ),
    .package(url: "https://github.com/StarLard/SwiftFormatPlugins.git", from: "1.1.1"),
  ],
  targets: [
    .target(
      name: "SolidPostScript",
      dependencies: [
        .product(name: "SolidCore", package: "solid-foundation"),
        .product(name: "SolidIO", package: "solid-foundation"),
      ],
      plugins: lintPlugins
    ),
    .testTarget(
      name: "SolidPostScriptTests",
      dependencies: [
        "SolidPostScript",
        .product(name: "SolidCore", package: "solid-foundation"),
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
