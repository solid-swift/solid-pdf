# SolidPDF

SolidPDF is a Swift package for PDF and related document-language implementations. Its first library,
`SolidPostScript`, provides a Swift PostScript interpreter that will support later PDF parsing work.

## Requirements

- Swift 6.2+
- macOS 26+, iOS 26+, tvOS 26+, watchOS 26+, or Linux

## Installation

Add SolidPDF to your package dependencies and depend on the `SolidPostScript` product:

```swift
dependencies: [
  .package(url: "https://github.com/solid-swift/solid-pdf.git", from: "0.1.0")
]

.target(
  name: "YourTarget",
  dependencies: [
    .product(name: "SolidPostScript", package: "solid-pdf")
  ]
)
```

## Usage

```swift
import SolidPostScript

let result: IntegerValue = try await Interpreter.result(content: "20 10 add")
print(result.value) // 30
```

Callers migrating from the archived implementation should replace `import TPPostScript` with
`import SolidPostScript`. This package does not provide a `TPPostScript` compatibility module.

## Compatibility baseline

`SolidPostScript` was migrated from `TPPostScript` at TPPackages commit
`a574257dbc01f555a28cd995e3b20009b36266d6`. The initial migration preserves that implementation's
public API and execution behavior while replacing shared TPPackages utilities with `SolidCore`.

This baseline is not a claim of complete PostScript conformance. Scanner hardening, ASCII85 edge cases,
file-reset semantics, and further language-conformance work remain follow-up work.

## License

SolidPDF is available under the MIT License. See [LICENSE](LICENSE).
