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

### 1. Complete implicit resource advertisement

The underlying semantics exist for the standard color spaces and type 1 color rendering, but the corresponding
implicit resources are not reported by `resourcestatus` or `resourceforall`. `FMapType` also advertises and implements
types 2 through 9 while the PLRM requires types 1 through 9. This stage should add:

- `ColorSpaceFamily` instances for DeviceGray, DeviceRGB, DeviceCMYK, CIEBasedA/ABC/DEF/DEFG, Indexed, Separation,
  DeviceN, and Pattern.
- `ColorRenderingType` instance 1.
- FMapType 1 mapping semantics and its implicit resource.

### 2. Make accounting parameters authoritative

The Appendix C keys exist, but `FactoryDefaults` lacks its persistent reset lifecycle and several display/source/cache
values are placeholders rather than live measurements. `MaxDisplayList`, `MaxSourceList`,
`MaxDisplayAndSourceList`, `MaxImageBuffer`, and `MaxOutlineCache` likewise do not yet govern the storage named by the
PLRM. These should be connected to the existing display-list, image-stream, and font-program owners rather than
maintaining parallel counters.

### 3. Run an independent exhaustive semantic audit

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
