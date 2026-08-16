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

## LanguageLevel target

`languagelevel` reports 3 as the implementation target. This is aspirational roadmap metadata, not a
claim of complete LanguageLevel 3 conformance. Unsupported operators are not represented by stubs and
continue to resolve as `undefined` until they are implemented.

## Numeric implementation profile

`SolidPostScript` uses signed 32-bit PostScript integers and finite IEEE-754 binary64 real numbers.
Integer arithmetic promotes results outside the integer range to real values where required by the
PostScript Language Reference. Numeric overflow, underflow, invalid domains, and division by zero are
reported through the PostScript error environment; NaN and infinity are not representable VM values.

## DCT/JPEG implementation profile

On Apple platforms, `DCTDecode` supports the common baseline JPEG profiles used by PostScript jobs,
including grayscale, RGB/YCbCr, CMYK, and YCCK data with common 4:4:4, 4:2:2, and 4:2:0 sampling.
The interpreter validates JPEG structure and PostScript parameters before delegating pixel conversion
to ImageIO. Progressive, abbreviated, two-component, and separate-scan JPEG data remains deferred and
fails deterministically with `ioerror` rather than being accepted with partial semantics.

See [PostScript conformance](Documentation/PostScriptConformance.md) for the detailed support matrix and
the remaining portability boundary.

## License

SolidPDF is available under the MIT License. See [LICENSE](LICENSE).
