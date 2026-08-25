# Native PDF graphics interpretation

`SolidPDFGraphics` interprets PDF page graphics into graphics semantic contract version 3. Device space
remains authoritative, and each event carries PDF source provenance. The bridge supports paths and clipping,
separate stroking and nonstroking color state, images and masks, forms, tiling and shading patterns, shading
types 1 through 7, PDF functions, rendering controls, PDF halftone types 1, 5, 6, 10, and 16, native PDF
fonts and CMaps, exact text positioning, Type 3 fonts, marked content, optional-content visibility, and logical
structure trees.

Inline images use their declared raw row size or the exact end-of-data condition of their filter chain. The
interpreter does not search for an `EI` byte pattern inside image data. Explicit masks are decoded through the
same authenticated stream pipeline as their parent image and are delivered within the parent's transactional
image operation.

Type 6 and Type 7 shadings retain their reconstructed source patches in addition to a bounded deterministic
triangle fallback. Continuation flags and shared edge colors are resolved before either representation is sent
to a target.

Text extraction can follow physical content order or logical structure order. It preserves exact source bytes,
glyph selectors, font identity, placement, style, Unicode provenance, marked-content ancestry, optional-content
visibility, artifacts, and replacement text without using Unicode to alter glyph selection.

Portable ICC realization currently uses a structurally validated profile's `Alternate` color space and reports
the fallback as a diagnostic. PostScript XObjects are standards-defined no-ops for non-PostScript output and
also produce a diagnostic. Nonidentity transparency, reference XObjects, JPX, JBIG2, and overprint mode 1 still
fail explicitly; none are silently skipped or approximated. Native transparency and compositing are the next
graphics implementation boundary.
