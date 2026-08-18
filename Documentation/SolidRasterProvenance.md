# SolidRaster provenance

The scan converter, fixed-point helpers, and stroker in `SolidRaster` are independent Swift ports of
the FreeType-derived implementations shipped by PlutoVG 1.3.3, commit
`bbd91f0d06a71491691b36330f29dffa4af87ccf`:

- `GrayRasterizer.swift` derives from `plutovg-ft-raster.c` (`ftgrays.c`).
- `FreeTypeFixedMath.swift` derives from `plutovg-ft-math.c` (`fttrigon.c`).
- `PathStroker.swift` derives from `plutovg-ft-stroker.c` (`ftstroke.c`).

The Swift ports replace C allocation, pointer-linked cells, `setjmp`/`longjmp`, and callback storage
with checked Swift collections, typed errors, and value-oriented spans. Numeric widths are explicit
so behavior does not depend on the platform C `long` representation.

Portions of this software are copyright The FreeType Project (www.freetype.org). All rights reserved.
The derived files are distributed under the FreeType License in `Vendor/PlutoVG/source/FTL.TXT`.
