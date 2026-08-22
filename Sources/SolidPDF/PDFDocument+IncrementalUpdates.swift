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
    let signatures = try await signatures()
    let authorization = PDFFormUpdateAuthorization(
      security: security,
      signatures: signatures,
      fields: fields
    )
    try authorization.validate(transaction)
    let valuePlan = try PDFFormUpdatePlanner(
      form: form,
      fields: fields,
      transaction: transaction,
      limits: options.limits
    ).plan()
    var annotations = [PDFAnnotationIdentifier: PDFAnnotation]()
    for field in fieldValues {
      for widget in field.widgets {
        annotations[widget.annotationIdentifier] = try await annotation(widget.annotationIdentifier)
      }
    }
    let plan = try await PDFFormAppearancePlanner(
      resolver: resolver,
      form: form,
      catalog: catalog,
      fields: fields,
      annotations: annotations,
      transaction: transaction,
      revision: latestRevision,
      base: valuePlan,
      limits: options.limits
    ).plan()
    let original = try await resolver.originalSourceData(
      maximumBytes: options.limits.maximumStagedDocumentBytes
    )
    let securityContext = try await resolver.securityContextForWriting()
    let encoded = try PDFIncrementalWriter(
      original: original,
      revision: latestRevision,
      objects: plan.objects,
      limits: options.limits,
      securityContext: securityContext
    ).encode()
    let validation = try await PDFIncrementalUpdateValidator.validate(
      encoded.data,
      expectedRevisionCount: revisions.count + 1,
      securityContext: securityContext,
      limits: options.limits
    )
    do {
      let session = try sink.makeSession()
      do {
        try session.write(encoded.data)
        let output = try session.finishIncrementalUpdate(
          fileVersion: effectiveVersion,
          pageCount: validation.pageCount,
          diagnostics: plan.diagnostics.map {
            PDFDiagnostic(kind: .rendering, message: $0.message)
          }
        )
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
          newReferences: plan.newReferences,
          effectiveVersion: effectiveVersion,
          diagnostics: plan.diagnostics + signatures.compactMap { signature in
            signature.identifier.map { _ in
              PDFIncrementalUpdateDiagnostic(
                kind: .signatureModification,
                message: "The update appends a revision after an existing signature."
              )
            }
          },
          signatureModifications: validation.signatureModifications
        )
      } catch {
        session.abort()
        throw error
      }
    } catch { throw error }
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
