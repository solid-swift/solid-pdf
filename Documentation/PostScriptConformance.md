# PostScript conformance

`SolidPostScript` targets LanguageLevel 3. The reported `languagelevel` is roadmap metadata while the
implementation is being completed, not a certification that every LanguageLevel 3 facility is present.

## DCT/JPEG filters

The Apple implementation uses a package-owned JPEG marker parser and profile validator around an
ImageIO codec backend. The validator owns PostScript-visible structure, sampling, color-transform,
end-of-data, parameter, and decoded-size behavior; ImageIO supplies pixel coding and conversion.

| Capability | Status |
| --- | --- |
| Baseline sequential grayscale | Supported |
| Baseline sequential RGB and YCbCr | Supported |
| Baseline sequential CMYK and YCCK | Supported |
| 4:4:4, 4:2:2, and 4:2:0 sampling | Supported |
| Restart markers | Supported |
| Adobe APP14 `ColorTransform` | Supported and validated |
| Exact EOI and trailing source bytes | Supported |
| Progressive JPEG | Deferred; rejected with `ioerror` |
| Two-component JPEG | Deferred; rejected with `ioerror` |
| Abbreviated streams and external tables | Deferred; rejected with `ioerror` |
| Separate baseline scans | Deferred; rejected with `ioerror` |
| Custom encode tables or non-default `QFactor` | Deferred; rejected with `ioerror` when encoding starts |
| Non-Apple DCT coding | Deferred; the recognized filter fails with `ioerror` when used |

Decoded images are bounded by the remaining capacity of the filter's retained PostScript VM domain.
Exceeding that budget raises `limitcheck`. Malformed data and unsupported JPEG profiles raise `ioerror`.
Filter construction remains lazy, so stream errors occur at the read, scan, or flush operation that
first requires decoded bytes and participate in the normal `errordict` and `stopped` lifecycle.

Progressive decoding may be available in ImageIO, but it is intentionally outside this profile. Keeping
the boundary explicit avoids depending on undocumented backend behavior and leaves room for a portable
codec backend without changing PostScript-visible results.
