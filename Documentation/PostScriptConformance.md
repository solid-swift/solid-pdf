# PostScript conformance

`SolidPostScript` targets PostScript LanguageLevel 3. The authoritative project inventory is
[`PLRMConformance.json`](PLRMConformance.json); it is checked against the runtime registrations by
`PLRMConformanceInventoryTests` so newly added operators, resource categories, filters, interpreter parameters, and
errors cannot remain undocumented.

This report is an implementation inventory and semantic audit ledger, not an Adobe certification. The surface
inventory proves that advertised names are registered. The `languageLevelRequirements` ledger separately records
audited behaviors, their implementation points, and the focused tests that exercise them. Neither claim replaces
independent validation with external conformance programs and device-provider combinations.

## Current inventory

| Surface | Inventoried result |
| --- | --- |
| `systemdict` operators and compatibility aliases | All 327 implemented |
| LanguageLevel 3 ProcSet operators | 33 implemented across five ProcSets |
| Resource categories | 36 advertised, including the environment-selected `CIDFontType` category and `Generic` |
| Standard filters | 17 implemented and advertised as implicit Filter resources |
| Standard implicit color resources | 11 `ColorSpaceFamily` instances and `ColorRenderingType` 1 advertised |
| User parameters | All 17 Appendix C parameters registered |
| System parameters | All 34 Appendix C parameters registered with authoritative accounting and persistence |
| Supported page-device parameters | 46, negotiated by provider capabilities and `Policies` |
| Standard files | `%stdin`, `%stdout`, `%stderr`, `%lineedit`, and `%statementedit` implemented |
| Standard errors | All 27 registered, plus `invalidcontext` and `invalidid` extensions |

The machine-readable inventory separately identifies product-conditional behavior. In particular, `exitserver` and
the executive bindings depend on the selected execution environment; sfnt-backed FontType 42 and CIDFontType 2 are
advertised only with a capable font provider.

## Semantic audit status

The first exhaustive PLRM semantic audit is complete. Its 18 findings are represented by focused vectors covering:

- text positioning, composite-font callback identity, name and CID `glyphshow`, Type 3 cache-device rules,
  `charpath`, and protected outline access;
- current-path construction, clipping, graphics restoration, saved page-device activation, `copypage`, and
  device-rendered `erasepage`;
- the valid Type 1 and Type 2 charstring operator sets, including flex and deprecated composite forms; and
- language-visible composite color queries plus degenerate sampled and stitching function domains.

The audit also found 34 registered operators that lacked a direct test mention. `PLRMSemanticOperatorTests` now runs
one executable semantic vector for every one of those operators, and the JSON ledger records the exact set. A runtime
registration check alone can no longer be mistaken for semantic evidence.

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

### 1. Run independent external conformance validation

The internal category-by-category audit is closed. The next validation stage should run published PostScript
conformance programs, external resource-provider combinations, and physical device matrices against the same ledger.
New discrepancies should be recorded as evidence-bearing semantic requirements before implementation changes begin.

Appendix C accounting is authoritative: display/source/image reservations are shared across contexts in an
environment, provider outlines use their own bounded LRU, and lowering live limits blocks growth or evicts cacheable
entries as applicable. Mutable installation parameters use a host-selected generation-checked store. `FactoryDefaults`
is applied on the next environment power-on only when its setting job remained the last installation activity, while
`PageCount` is preserved.

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
