# PDF recovery

SolidPDF parses strictly by default. Recovery is enabled only when a caller supplies
`PDFRecoveryOptions` in `PDFParsingOptions`. Structural recovery accepts a unique repair supported by
source evidence; compatible recovery may choose among otherwise valid alternatives and records that choice as
semantic inference.

Recovery never changes the source bytes. Each built-in pass inspects an immutable snapshot and returns a proposal.
The coordinator applies proposals transactionally, reruns invalidated stages, enforces aggregate budgets, and emits a
`PDFRecoveryReport`. Resolved objects and higher-level document values retain recovery provenance.

## Adding a built-in pass

1. Implement one package-scoped `PDFRecoveryPass` type with a stable descriptor identifier.
2. Select the narrowest stage, minimum policy, and forward-only invalidation set.
3. Return immutable proposals with exact evidence ranges, classification, capability consequences, and no source mutation.
4. Register the pass in `PDFRecoveryRegistry.builtIn`.
5. Add a project-owned malformed fixture and list the identifier in the recovery corpus manifest.
6. Add ambiguity, limit, cancellation, and transactional-rollback tests.

Public recovery plugins are deliberately deferred. Parser windows, candidate indexes, mutable coordinator state, and
source capabilities do not cross the public API.

## Authority and capabilities

Compatibility inference disables incremental writing and authoritative signature-modification analysis. Structural
repairs are also denied writing unless all relevant facts can be validated byte-exactly. Signature cryptography may
still verify original byte ranges, but the result explicitly reports limited recovery authority. External stream
providers, actions, JavaScript, network access, and host file capabilities remain unavailable to recovered documents.

`Tests/Fixtures/PDF/Recovery/manifest.json` is the versioned owned corpus. External qpdf, MuPDF, Poppler, and
Ghostscript outcomes are compatibility evidence only; they do not define SolidPDF recovery behavior.
