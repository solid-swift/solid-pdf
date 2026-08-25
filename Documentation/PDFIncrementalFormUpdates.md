# PDF incremental form updates

SolidPDF updates AcroForm values through semantic transactions. It does not expose arbitrary PDF
object replacement. A successful transaction preserves every original source byte and appends one
strictly validated revision containing the field, widget, appearance, and AcroForm changes required
to keep the document internally consistent.

```swift
let document = try await PDFDocument(source: PDFFileInputSource(url: sourceURL))
let field = try await document.formFields().first { $0.fullyQualifiedName == "Customer.Name" }!
let transaction = PDFFormUpdateTransaction(updates: [
  PDFFormFieldUpdate(field: field.identifier, value: .text("Renée Example"))
])
let result = try await document.writeIncrementalUpdate(
  transaction,
  to: destinationURL,
  replacingExisting: true
)
```

Transactions are latest-revision-only and all-or-nothing. The complete request is checked before
publication for field type and flags, required values, maximum lengths, choice options, button
states, available font encodings, appearance resources, authenticated permissions, DocMDP, and
FieldMDP. JavaScript calculation, validation, and formatting actions remain inert; diagnostics note
when such actions may leave dependent fields stale.

Every affected widget receives synchronized appearance data. Existing variable-text appearances
retain unrelated custom artwork while their `/Tx` marked-content region is replaced. Missing
standard text and button appearances are generated deterministically from embedded AcroForm
resources. Writing never discovers or substitutes host fonts, and a transaction fails if exact text
encoding or appearance generation is unavailable.

Encrypted R2 through R6 documents retain their original security handler. Rewritten strings and
streams use the authenticated file key and the containing object's number and generation. AES uses
fresh initialization vectors, so encrypted output is intentionally nondeterministic. Signature
dictionaries and signed source bytes are never rewritten. The result reports each existing
signature's later-revision modification status independently of its cryptographic validity.

The file convenience writes through a same-directory temporary file and publishes only after the
staged revision has been reparsed strictly. Failure, cancellation, limit exhaustion, or a changed
source leaves an existing destination untouched. `replacingExisting` controls only the exact
destination path.

`PDFIncrementalWritingLimits` bounds transaction changes, appended objects, each generated
appearance, appended bytes, validation scratch, and staged output. A custom `PDFOutputSink` can
stream the validated result elsewhere. Its incremental-finalization callback receives the exact
inherited `PDFFileVersion`; older sinks remain compatible through the PDF 1.7/2.0 adapter.

Use `Scripts/pdf-form-update-interop UPDATED.pdf` to check a generated document with qpdf, MuPDF,
Poppler, `pdfinfo`, and `pdfsig`. Those tools are differential validators; ISO 32000-2 and its errata
remain authoritative.
