import Foundation

extension PDFDocument {
  /// Applies a semantic form transaction and publishes one appended revision.
  public func writeIncrementalUpdate<Sink: PDFOutputSink>(
    _ transaction: PDFFormUpdateTransaction,
    to sink: Sink,
    options: PDFIncrementalWritingOptions = .init()
  ) async throws -> PDFIncrementalUpdateResult<Sink.Session.Output>
  where Sink.Session.Output: Sendable {
    let form = try await acroForm()
    guard let form else { throw PDFIncrementalUpdateError.missingAcroForm }
    let fieldValues = try await formFields()
    let fields = Dictionary(uniqueKeysWithValues: fieldValues.map { ($0.identifier, $0) })
    let plan = try PDFFormUpdatePlanner(
      form: form,
      fields: fields,
      transaction: transaction,
      limits: options.limits
    ).plan()
    let original = try await resolver.originalSourceData(
      maximumBytes: options.limits.maximumStagedDocumentBytes
    )
    let encoded = try PDFIncrementalWriter(
      original: original,
      revision: latestRevision,
      objects: plan.objects,
      limits: options.limits
    ).encode()
    let validated = try await PDFDocument<PDFDataInputSource>(
      source: PDFDataInputSource(encoded.data)
    )
    do {
      guard validated.revisions.count == revisions.count + 1 else {
        throw PDFIncrementalUpdateError.validationFailed
      }
      try await validated.validateAcroForm()
      let pageCount = try await validated.pageCount()
      let session = try sink.makeSession()
      do {
        try session.write(encoded.data)
        let output = try session.finish(
          version: effectiveVersion == .v2_0 ? .v2_0 : .v1_7,
          pageCount: pageCount,
          diagnostics: plan.diagnostics.map {
            PDFDiagnostic(kind: .rendering, message: $0.message)
          }
        )
        await validated.close()
        return PDFIncrementalUpdateResult(
          output: output,
          sourceRevision: latestRevision.identifier,
          appendedRevision: .init(
            ordinal: revisions.count,
            startCrossReferenceOffset: encoded.startCrossReferenceOffset,
            representation: encoded.representation
          ),
          appendedByteCount: encoded.appendedByteCount,
          changedReferences: plan.changedReferences,
          newReferences: [],
          effectiveVersion: effectiveVersion,
          diagnostics: plan.diagnostics
        )
      } catch {
        session.abort()
        throw error
      }
    } catch {
      await validated.close()
      throw error
    }
  }

  /// Returns an in-memory document containing one appended form revision.
  public func incrementallyUpdatedData(
    _ transaction: PDFFormUpdateTransaction,
    options: PDFIncrementalWritingOptions = .init()
  ) async throws -> PDFIncrementalUpdateResult<PDFEncodedDocument> {
    try await writeIncrementalUpdate(transaction, to: PDFDataOutputSink(), options: options)
  }

  /// Atomically writes a document containing one appended form revision.
  public func writeIncrementalUpdate(
    _ transaction: PDFFormUpdateTransaction,
    to destination: URL,
    replacingExisting: Bool = false,
    options: PDFIncrementalWritingOptions = .init()
  ) async throws -> PDFIncrementalUpdateResult<URL> {
    try await writeIncrementalUpdate(
      transaction,
      to: PDFAtomicFileOutputSink(
        destination: destination,
        replacingExisting: replacingExisting
      ),
      options: options
    )
  }
}
