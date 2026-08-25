# PDF Security Fixtures

The deterministic fixtures exercised by `PDFSecurityTests` are authored in the test source so
their identifiers, salts, initialization vectors, object numbers, revisions, and expected plaintext
remain reviewable. They cover Standard Security Handler revisions 2 through 6, RC4, AES-128,
AES-256, object streams, explicit crypt filters, external streams, and incremental updates.

`Scripts/generate-pdf-security-oracles` creates independent qpdf files for the shared algorithm
subset. qpdf intentionally generates fresh random security material, so those files are validation
artifacts rather than checked-in golden bytes. The script records the qpdf version and encryption
description beside each generated file. It uses the project-owned source PDF supplied by the caller
and the fixed test-only passwords `user` and `owner`.

The deterministic salts and initialization vectors in `PDFSecurityTests` are test construction data
only. They are not available to production PDF writing code.

The compact R4 RC4 and R6 AES fixtures embedded in `PDFParsingBenchmarkFixtures.swift` were
generated from the project-owned `writer-1.7.pdf` interoperability document with qpdf 11.9.0 and
the same script. Their fixed bytes make benchmark and parser acceptance independent of installed
tools; qpdf and MuPDF regenerate separate oracle files during Linux interoperability validation.
