# PostScript Semantic Graphics Contract

`GraphicsSemanticContractVersion.v2` is the stable document-processing boundary emitted by
SolidPostScript. `SemanticGraphicsTarget` is the bounded streaming interface;
`RecordingGraphicsTarget` is its materialized counterpart. Neither interface exposes PostScript VM
objects, executable callbacks, renderer sessions, or platform-native handles.

The contract is frozen at the PostScript graphics closeout milestone. Native PDF parsing is the next
product stage. A parser may consume this contract and the shared SolidImage products, but it may not
change version 2 coordinate, identity, ordering, text, or lifetime semantics without the major-version
process described below.

## Coordinates

Effect geometry, paths, clips, image transforms, and glyph origins are authoritative in device
space. A recorded or transmitted page supplies `GraphicsPageCoordinateMapping`, whose page space is
PostScript default user space measured in points. Its inverse is absent when the installed default
matrix is singular; consumers must not approximate an inverse. The captured CTM recovers current
user space at each event.

## Identity and lifetime

`GraphicsResourceIdentifier` correlates repeated references for the lifetime of one interpreter
environment and render. Its opaque value has no document meaning. `GraphicsResourceStableKey` is
present only when XUID, UniqueID, or content evidence permits cross-instance correlation. Canonical
serialization replaces opaque values with deterministic first-use ordinals.

Semantic callback values are immutable and `Sendable`. Retaining a value retains its copy-on-write
backing. No value retains interpreter VM ownership or a target context. Font identities describe the
language-visible root and selected descendant; glyph-program identity is distinct from any
device-specific realization.

## Text extraction

A glyph placement preserves its interpreter-selected selector, resolved index when known, complete
metrics and bounds, device origin, glyph-to-device transform, user-space advance, descendant font,
and exact byte range in the run. The run retains the complete source bytes. Unicode scalars are
optional extraction metadata paired with an explicit provenance; they never affect selection,
positioning, callbacks, or rendering. Styling is the placement plus the captured graphics state,
including paint, original color space and components, color realization, overprint, device-rendering
controls, clipping, CTM, and device snapshot.

Version 2 adds the exact PDF text rendering mode and independent nonstroking and stroking paints to
each run. It also records PDF Encoding, CMap, and `/ToUnicode` provenance and any provider
substitution evidence. These values reproduce PDF fill, stroke, fill-stroke, invisible, and clipping
text without using Unicode or a platform layout engine to select or position glyphs. Version 1
symbols and default initializers remain available for legacy producers.

Every event may additionally identify a format-neutral source origin. An origin correlates a source
resource and one or more exact byte segments without changing operation semantics. PDF content uses
this additive metadata to retain page, content-stream, and nested-resource provenance. Captured
graphics state also preserves rendering intent and device-rendering state preserves halftone phase;
legacy producers receive the documented defaults.

Type 6 and Type 7 shadings retain their exact reconstructed source patches, including the original
continuation flags, ordered control points, and corner components before function or color-space
realization. The accompanying triangle mesh is a deterministic portable fallback and does not
replace the authoritative patch representation.

## Streaming order

Device activation precedes its events. Every image event is followed by one begin callback, ordered
color and mask row callbacks, and exactly one completion or abandonment. Page transmission follows
all marks for that logical page and carries copies as metadata rather than duplicated effects.
Device identities distinguish suspended and reactivated devices. A sink failure aborts the render
and is exposed to PostScript as `ioerror`.

## Compatibility policy

Changing a coordinate meaning, identity rule, required sink callback, or semantic enum case requires
a major package version and a new semantic-contract version. New optional struct metadata must use
defaulted initializer parameters. Protocol requirements may be introduced only with an adapter that
preserves the complete existing semantics; required data never receives a silent no-op default.
Exhaustive third-party enum consumers are covered by the major-version rule.

The machine-readable companion, `GraphicsSemanticContract.json`, is checked against the public case
inventory and canonicalizer tests. API-digester checks guard public signatures independently of the
semantic manifest.
