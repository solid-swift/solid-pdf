# `solid-ps`

`solid-ps` renders PostScript and EPS programs through the portable native Swift raster target and writes deterministic PNG files.

```console
solid-ps render artwork.eps --output artwork.png
solid-ps render document.ps --output pages --dpi 144 --pages 1,3-5
cat artwork.eps | solid-ps render - --output - > artwork.png
```

EPS input is validated as DSC 3.0 by default and cropped outward to its resolved bounding box. Ordinary PostScript uses its negotiated page-device bounds. A PNG file or standard output requires exactly one selected runtime page; a directory receives numbered files for every selected page and copy.

PostScript cannot access the host filesystem by default. Repeat `--allow-read DIRECTORY` to expose read-only rooted directories. The implementation rejects traversal and symbolic-link escapes, writes, deletion, and renaming. This is an interpreter capability boundary rather than an operating-system sandbox; run hostile input inside the project's Linux container or another OS sandbox as well.

Use `--lenient-dsc` to retain recoverable DSC diagnostics as warnings, `--timeout` to bound wall-clock execution, `--no-host-fonts` for portable embedded fonts only, and `--force` to replace only generated output paths. Diagnostics and PostScript standard output are sent to process standard error so PNG standard output remains uncorrupted.
