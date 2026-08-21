# PostScript graphics closeout review guide

This guide indexes the preserved implementation series for the final graphics review. The series is intentionally
not squashed: each subsystem can be reviewed at its original semantic boundary, followed by the shared-library
migration and contract gates.

## Core graphics and targets

- `a42a9eb` through `47d4aa1`: target protocols, CoreGraphics, PlutoVG, native rasterization, and performance work.
- `06f809a` through `b6ce50c`: path derivation, insideness, and user paths.
- `bd1eee0` through `a63305c`: color spaces, color engines, and target realization.
- `13f4457` through `4315c23`: patterns, shadings, forms, sampled images, and masks.

## Devices and print semantics

- `bf2d004` through `ed12fd5`: page devices, page lifecycle, transfer controls, and halftones.
- `583f887` through `3928c13`: separations and overprint.
- `fa6a244` through `15797da`: in-RIP trapping.
- `26efb26` through `32e581e`: device-color remapping.
- `184565d` through `68debb8`: media selection, duplex placement, delivery, and collation.

## Fonts and document output

- `16213f3` through `82a5bda`: portable fonts, text, CID/CMap support, and CoreText/FreeType realization.
- `4a52cb6` through `548b6b6`: DSC/EPS rendering, PNG/PDF output, and native PDF font embedding.
- `0fe973e` through `fd59317`: portable filters, conformance inventory, reusable Linux containers, encrypted Type 1
  execution, implicit resources, and encrypted-font regression closure.

## Audit, accounting, and contract freeze

- `e71b54d` through `67f9364`: Appendix C accounting, lifecycle persistence, and exhaustive semantic corrections.
- `5b47401` through `231f755`: owned conformance harness, Ghostscript differential validation, and compatibility corpus.
- `65c77e2`: Linux time-test stabilization.
- `e1c70bf` through `4548cad`: semantic metadata, extraction guarantees, streaming target, and version 1 contract freeze.

## Shared image-library extraction

- `8974aa7`: adopts SolidImage's Color, Raster, and PNG modules and removes their duplicate SolidPDF ownership.
- `6434de9`: adopts SolidImageIO's DCT, CCITT, and incremental predictor adapters while retaining generic file
  lifecycle in SolidIO.
- The closeout-gate commit removes moved API baselines, enforces all remaining product baselines, and records the
  dependency boundaries used for the clean-checkout review.

The reviewed and merged dependency tips are:

- SolidFoundation `main`: `9bc4c0a88a265af77880e1a72c60cef77a5ea339`
- SolidImage `main`: `bd810d1d8e1c409d008a91f4791db0526242ab92`

The merged SolidPDF SHA is recorded in the closeout pull request after review is complete. Native PDF object parsing
starts only from that merged SolidPDF `main`.
