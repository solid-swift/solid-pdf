# SolidPDF

SolidPDF is a Swift package for PDF and related document-language implementations. `SolidPostScript`
provides a Swift PostScript interpreter, while `SolidPDF` and `SolidPostScriptPDF` provide deterministic
PDF writing and vector-preserving PostScript rendering.

## Requirements

- Swift 6.3+
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

### PS/EPS to PDF

`PostScriptDocument` renders DSC PostScript and EPS directly to PDF 2.0 or PDF 1.7. Native paths,
images, reusable graphics, named colors, overprint, and portable outline glyphs remain PDF graphics.
Effects that PDF cannot reproduce exactly are rasterized in isolation when composition permits it;
cross-effect dependencies trigger an explicit page fallback and diagnostic.

```swift
import SolidPostScriptDocument

let document = try PostScriptDocument(contentsOf: inputURL)
let result = try await document.renderPDF(to: outputURL)
print(result.output)
```

The command-line renderer infers PDF and PNG from the output extension:

```sh
solid-ps render artwork.eps --output artwork.pdf
solid-ps render document.ps --output pages --format png --dpi 144
solid-ps render document.ps --output - --format pdf --pdf-version 1.7
```

Use `--no-raster-fallback` when a job must remain entirely native PDF graphics. PDF output is composite;
physical separation plates and in-RIP trapping remain available through `RasterSeparationTarget`.

## Compatibility baseline

`SolidPostScript` was migrated from `TPPostScript` at TPPackages commit
`a574257dbc01f555a28cd995e3b20009b36266d6`. The initial migration preserves that implementation's
public API and execution behavior while replacing shared TPPackages utilities with `SolidCore`.

The preserved migration history is followed by the complete LanguageLevel 3 implementation, semantic audit,
owned compatibility corpus, and frozen graphics contract. This remains an implementation claim rather than Adobe
certification; conformance evidence and accepted reference differences are maintained in the checked-in ledger.

## LanguageLevel target

`languagelevel` reports 3. Standard operators and advertised resources are inventoried and linked to owned semantic
cases. Product-specific, proprietary, and intentionally unavailable facilities remain absent instead of being
represented by approximate stubs.

## Numeric implementation profile

`SolidPostScript` uses signed 32-bit PostScript integers and finite IEEE-754 binary64 real numbers.
Integer arithmetic promotes results outside the integer range to real values where required by the
PostScript Language Reference. Numeric overflow, underflow, invalid domains, and division by zero are
reported through the PostScript error environment; NaN and infinity are not representable VM values.

## DCT/JPEG implementation profile

`DCTEncode` and `DCTDecode` use the owned portable baseline-sequential codec from
[`solid-swift/solid-image`](https://github.com/solid-swift/solid-image). Raw one- through four-component data,
sampling layouts, abbreviated tables, restart intervals, interleaved and separate scans, and PostScript color
transforms remain interpreter-controlled. ImageIO is selected only for equivalent whole-codec operations.

See [PostScript conformance](Documentation/PostScriptConformance.md) for the detailed support matrix and
the remaining portability boundary.

## License

SolidPDF is available under the MIT License. See [LICENSE](LICENSE). The vendored PlutoVG implementation contains
code derived from the FreeType Project under the FreeType License; see
[Vendor/PlutoVG/source/FTL.TXT](Vendor/PlutoVG/source/FTL.TXT). SolidRaster provenance is maintained by SolidImage.
