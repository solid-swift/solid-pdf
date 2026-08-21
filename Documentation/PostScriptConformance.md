# PostScript conformance

`SolidPostScript` targets PostScript LanguageLevel 3. The authoritative project inventory is
[`PLRMConformance.json`](PLRMConformance.json); it is checked against the runtime registrations by
`PLRMConformanceInventoryTests` so newly added operators, resource categories, filters, interpreter parameters, and
errors cannot remain undocumented.

This report is an implementation inventory, not an Adobe certification. An `implemented` classification means that
the language surface is registered and has focused coverage. It does not replace independent conformance testing of
every semantic combination in the PLRM.

## Current inventory

| Surface | Inventoried result |
| --- | --- |
| `systemdict` operators and compatibility aliases | All 327 implemented |
| LanguageLevel 3 ProcSet operators | 33 implemented across five ProcSets |
| Resource categories | 36 advertised, including the environment-selected `CIDFontType` category and `Generic` |
| Standard filters | 17 implemented and advertised as implicit Filter resources |
| Standard implicit color resources | 11 `ColorSpaceFamily` instances and `ColorRenderingType` 1 advertised |
| User parameters | All 17 Appendix C parameters registered |
| System parameters | All 34 Appendix C parameters registered; nine accounting/lifecycle semantics remain nonconforming |
| Supported page-device parameters | 46, negotiated by provider capabilities and `Policies` |
| Standard files | `%stdin`, `%stdout`, `%stderr`, `%lineedit`, and `%statementedit` implemented |
| Standard errors | All 27 registered, plus `invalidcontext` and `invalidid` extensions |

The machine-readable inventory separately identifies product-conditional behavior. In particular, `exitserver` and
the executive bindings depend on the selected execution environment; sfnt-backed FontType 42 and CIDFontType 2 are
advertised only with a capable font provider.

## Portable filter status

The postponed filter tranche is complete at the portable runtime boundary:

- `DCTEncode` and `DCTDecode` use the project-owned native `SolidJPEG` baseline sequential codec. It supports one
  through four raw components, legal baseline sampling layouts, interleaved and separate scans, restart intervals,
  abbreviated streams, caller-supplied tables, `QFactor`, and PostScript color transforms. Unsupported JPEG coding
  processes fail explicitly.
- `CCITTFaxEncode` and `CCITTFaxDecode` use the portable Group 3/Group 4 codec, including mixed two-dimensional rows,
  byte alignment, EOL/RTC/EOFB termination, damaged-row recovery, polarity, and bounded storage.
- TIFF and PNG predictors operate incrementally. Flate, LZW, RunLength, ASCII85, and predictor compositions no longer
  require avoidable whole-stream buffering.
- Filter files share the contextual logical cursor. They preserve trailing upstream data, distinguish encoded EOD
  from physical EOF, apply close propagation once, defer `DCTEncode` EOD until close, and abandon failed transfers
  without corrupting PostScript error snapshots.
- ImageIO remains an optional, capability-selected Apple fast path. The portable codecs are authoritative and are
  always available on Linux. Differential libraries are test oracles, not production dependencies.

## Remaining conformance stages

### 1. Make accounting parameters authoritative

The Appendix C keys exist, but `FactoryDefaults` lacks its persistent reset lifecycle and several display/source/cache
values are placeholders rather than live measurements. `MaxDisplayList`, `MaxSourceList`,
`MaxDisplayAndSourceList`, `MaxImageBuffer`, and `MaxOutlineCache` likewise do not yet govern the storage named by the
PLRM. These should be connected to the existing display-list, image-stream, and font-program owners rather than
maintaining parallel counters.

### 2. Run an independent exhaustive semantic audit

Registration coverage now prevents surface drift, but it cannot prove every error precedence, callback boundary,
save/restore interaction, external-resource load, or provider capability matrix. The next audit should consume the
JSON ledger category by category, add missing semantic vectors, and create focused implementation tranches only after
the complete read-only report is finished.

## Intentionally unavailable facilities

- `banddevice`, `framedevice`, and `renderbands` are obsolete LanguageLevel 1 device operators that Appendix G says
  should never be used.
- `internaldict` is optional and undocumented; SolidPostScript does not expose an unstable implementation ABI.
- FontType 14 Chameleon fonts are unavailable unless a future provider explicitly implements them.
- Proprietary HalftoneTypes 9 and 100 are product-dependent and remain unavailable.

No filter remains classified as postponed. Product-specific emulators, proprietary resources, and device capabilities
are reported as unavailable rather than advertised and approximated.

## Composite-font mapping note

`FMapType` advertises exactly types 2 through 9. PLRM Table 5.9 defines those eight mappings, and Adobe's
[LanguageLevel 3 supplement](https://ftp.icm.edu.pl/packages/lprng/RESOURCES/ADOBE/PS2017.Supplement.pdf) likewise
lists types 2 through 9. The isolated statement in PLRM section 3.9 that describes types 1 through 9 conflicts with
both normative lists and is treated as an editorial error. Type 1 therefore remains unavailable: its resource lookup
produces `undefinedresource`, and a Type 0 font that declares it produces `invalidfont`.
