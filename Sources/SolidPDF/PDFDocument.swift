import Foundation

/// A lazily resolved PDF document backed by a typed random-access source.
public final class PDFDocument<Source: PDFInputSource>: Sendable {
  /// The version declared by the PDF header.
  public let version: PDFFileVersion
  /// The document catalog reference.
  public let root: PDFObjectReference
  /// The optional document information reference.
  public let info: PDFObjectReference?
  /// The optional two-part file identifier.
  public let identifier: [PDFString]?
  /// The document revisions in chronological order.
  public let revisions: [PDFDocumentRevision]
  /// The latest document revision.
  public var latestRevision: PDFDocumentRevision { revisions[revisions.count - 1] }
  /// Authenticated security metadata, or `nil` for an unencrypted document.
  public let security: PDFDocumentSecurity?
  /// The validated latest document catalog.
  public let catalog: PDFDocumentCatalog
  /// The effective version after applying the catalog's optional `/Version`.
  public var effectiveVersion: PDFFileVersion { catalog.effectiveVersion }
  /// Repairs used to open this document, or `nil` when strict parsing succeeded.
  public let recoveryReport: PDFRecoveryReport?

  let resolver: PDFDocumentResolver<Source.Session>
  private let structure: PDFDocumentStructure<Source.Session>
  let interactiveStructure: PDFDocumentInteractiveStructure<Source.Session>
  private let assets: PDFDocumentAssets<Source.Session>
  let authenticity: PDFDocumentAuthenticity<Source.Session>

  /// Opens and validates one PDF revision without eagerly resolving its objects.
  public init(
    source: Source,
    options: PDFParsingOptions = .init(),
    externalStreamProvider: (any PDFExternalStreamProvider)? = nil,
    passwordProvider: (any PDFPasswordProvider)? = nil
  ) async throws {
    let session = try await source.makeSession()
    do {
      let reader = try await PDFSourceReader(session: session, options: options)
      let openedSourceLength = try await reader.length()
      let index: PDFCrossReferenceIndex
      do {
        let strictIndex = try await PDFCrossReferenceParser(reader: reader, options: options).parse()
        if options.recovery != nil {
          try await PDFRecoveryStrictPreflight.validate(
            index: strictIndex,
            reader: reader,
            limits: options.limits
          )
        }
        index = strictIndex
      } catch let strictError as PDFParsingError {
        guard let recovery = options.recovery, Self.isRecoverable(strictError) else { throw strictError }
        index = try await PDFRecoveryCoordinator(options: recovery).recover(
          reader: reader,
          strictError: strictError,
          parsingOptions: options
        )
      }
      let securityContext = try await PDFSecurityContext.open(
        reader: reader,
        index: index,
        options: options,
        passwordProvider: passwordProvider
      )
      version = index.version
      root = index.root
      info = index.info
      identifier = index.identifier
      revisions = index.revisions
      security = securityContext?.security
      recoveryReport = index.recoveryReport
      let documentResolver = PDFDocumentResolver(
        reader: reader,
        index: index,
        options: options,
        externalStreamProvider: index.recoveryReport == nil ? externalStreamProvider : nil,
        securityContext: securityContext,
        openedSourceLength: openedSourceLength
      )
      let documentStructure = PDFDocumentStructure(
        resolver: documentResolver,
        revisions: index.revisions,
        headerVersion: index.version,
        limits: options.limits
      )
      resolver = documentResolver
      structure = documentStructure
      let documentAssets = PDFDocumentAssets(
        resolver: documentResolver,
        structure: documentStructure,
        revisions: index.revisions,
        limits: options.limits
      )
      assets = documentAssets
      let documentInteractiveStructure = PDFDocumentInteractiveStructure(
        resolver: documentResolver,
        structure: documentStructure,
        assets: documentAssets,
        revisions: index.revisions,
        limits: options.limits
      )
      interactiveStructure = documentInteractiveStructure
      authenticity = PDFDocumentAuthenticity(
        resolver: documentResolver,
        structure: documentStructure,
        interactive: documentInteractiveStructure,
        revisions: index.revisions,
        limits: options.limits
      )
      catalog = try await documentStructure.catalog(in: index.latestRevision.identifier)
    } catch {
      await session.close()
      throw error
    }
  }

  /// Opens a document using one fixed noninteractive password candidate.
  public convenience init(
    source: Source,
    options: PDFParsingOptions = .init(),
    externalStreamProvider: (any PDFExternalStreamProvider)? = nil,
    password: PDFPassword
  ) async throws {
    try await self.init(
      source: source,
      options: options,
      externalStreamProvider: externalStreamProvider,
      passwordProvider: PDFFixedPasswordProvider(password)
    )
  }

  deinit {
    let resolver = resolver
    let structure = structure
    let interactiveStructure = interactiveStructure
    let assets = assets
    let authenticity = authenticity
    Task {
      await authenticity.close()
      await assets.close()
      await interactiveStructure.close()
      await structure.close()
      await resolver.close()
    }
  }

  private static func isRecoverable(_ error: PDFParsingError) -> Bool {
    switch error {
    case .malformed, .truncated, .unresolvedReference, .referenceCycle:
      true
    default:
      false
    }
  }

  /// Resolves an indirect object on demand.
  public func resolve(_ reference: PDFObjectReference) async throws -> PDFIndirectObject {
    try await resolver.resolve(reference)
  }

  /// Resolves an indirect object as it existed at the end of a selected revision.
  public func resolve(
    _ reference: PDFObjectReference,
    in revision: PDFRevisionIdentifier
  ) async throws -> PDFIndirectObject {
    try await resolver.resolve(reference, in: revision)
  }

  /// Returns the validated catalog as it existed in a selected revision.
  public func catalog(in revision: PDFRevisionIdentifier) async throws -> PDFDocumentCatalog {
    try await structure.catalog(in: revision)
  }

  /// Returns the fully validated page count for the latest revision.
  public func pageCount() async throws -> Int {
    try await structure.pageCount(in: latestRevision.identifier)
  }

  /// Returns the fully validated page count for a selected revision.
  public func pageCount(in revision: PDFRevisionIdentifier) async throws -> Int {
    try await structure.pageCount(in: revision)
  }

  /// Resolves a zero-based page in the latest revision.
  public func page(at index: Int) async throws -> PDFPage {
    try await structure.page(at: index, in: latestRevision.identifier)
  }

  /// Resolves a zero-based page in a selected revision.
  public func page(
    at index: Int,
    in revision: PDFRevisionIdentifier
  ) async throws -> PDFPage {
    try await structure.page(at: index, in: revision)
  }

  /// Opens a single-pass page sequence for the latest revision.
  public func pages() async throws -> PDFPageSequence {
    try await structure.pages(in: latestRevision.identifier)
  }

  /// Opens a single-pass page sequence for a selected revision.
  public func pages(in revision: PDFRevisionIdentifier) async throws -> PDFPageSequence {
    try await structure.pages(in: revision)
  }

  /// Validates the complete latest page tree.
  public func validatePageTree() async throws {
    try await structure.validatePageTree(in: latestRevision.identifier)
  }

  /// Validates the complete page tree in a selected revision.
  public func validatePageTree(in revision: PDFRevisionIdentifier) async throws {
    try await structure.validatePageTree(in: revision)
  }

  /// Returns the explicit page-label ranges for the latest revision.
  public func pageLabelRanges() async throws -> [PDFPageLabelRange]? {
    try await structure.pageLabelRanges(in: latestRevision.identifier)
  }

  /// Returns the explicit page-label ranges for a selected revision.
  public func pageLabelRanges(
    in revision: PDFRevisionIdentifier
  ) async throws -> [PDFPageLabelRange]? {
    try await structure.pageLabelRanges(in: revision)
  }

  /// Returns the optional-content properties in the latest catalog.
  public func optionalContentProperties() async throws -> PDFOptionalContentProperties? {
    try await structure.optionalContentProperties(in: latestRevision.identifier)
  }

  /// Returns the optional-content properties in a selected revision.
  public func optionalContentProperties(
    in revision: PDFRevisionIdentifier
  ) async throws -> PDFOptionalContentProperties? {
    try await structure.optionalContentProperties(in: revision)
  }

  /// Evaluates an optional-content group or membership dictionary.
  public func optionalContentVisibility(
    of object: PDFObject,
    selection: PDFOptionalContentSelection = .documentDefault,
    context: PDFOptionalContentContext = .init(),
    in revision: PDFRevisionIdentifier? = nil
  ) async throws -> PDFOptionalContentVisibility {
    try await structure.optionalContentVisibility(
      of: object,
      selection: selection,
      context: context,
      in: revision ?? latestRevision.identifier
    )
  }

  /// Returns the latest document's logical structure tree, when present.
  public func structureTree() async throws -> PDFStructureTree? {
    try await structure.structureTree(in: latestRevision.identifier)
  }

  /// Returns the logical structure tree in a selected revision, when present.
  public func structureTree(in revision: PDFRevisionIdentifier) async throws -> PDFStructureTree? {
    try await structure.structureTree(in: revision)
  }

  /// Returns the annotations associated with a page in array order.
  public func annotations(on page: PDFPage) async throws -> [PDFAnnotation] {
    try await interactiveStructure.annotations(on: page, in: latestRevision.identifier)
  }

  /// Returns the annotations associated with a historical page in array order.
  public func annotations(
    on page: PDFPage,
    in revision: PDFRevisionIdentifier
  ) async throws -> [PDFAnnotation] {
    try await interactiveStructure.annotations(on: page, in: revision)
  }

  /// Resolves one annotation in the latest revision.
  public func annotation(_ identifier: PDFAnnotationIdentifier) async throws -> PDFAnnotation {
    try await interactiveStructure.annotation(identifier, in: latestRevision.identifier)
  }

  /// Resolves one annotation in a selected revision.
  public func annotation(
    _ identifier: PDFAnnotationIdentifier,
    in revision: PDFRevisionIdentifier
  ) async throws -> PDFAnnotation {
    try await interactiveStructure.annotation(identifier, in: revision)
  }

  /// Resolves a named destination in the latest revision.
  public func destination(named name: PDFDestinationName) async throws -> PDFDestination? {
    try await interactiveStructure.destination(named: name, in: latestRevision.identifier)
  }

  /// Resolves a named destination in a selected revision.
  public func destination(
    named name: PDFDestinationName,
    in revision: PDFRevisionIdentifier
  ) async throws -> PDFDestination? {
    try await interactiveStructure.destination(named: name, in: revision)
  }

  /// Audits all annotation arrays and relationships in the latest revision.
  public func validateAnnotations() async throws {
    try await interactiveStructure.validateAnnotations(in: latestRevision.identifier)
  }

  /// Audits all annotation arrays and relationships in a selected revision.
  public func validateAnnotations(in revision: PDFRevisionIdentifier) async throws {
    try await interactiveStructure.validateAnnotations(in: revision)
  }

  /// Returns the latest document's interactive form, when present.
  public func acroForm() async throws -> PDFAcroForm? {
    try await interactiveStructure.acroForm(in: latestRevision.identifier)
  }

  /// Returns the interactive form in a selected revision, when present.
  public func acroForm(in revision: PDFRevisionIdentifier) async throws -> PDFAcroForm? {
    try await interactiveStructure.acroForm(in: revision)
  }

  /// Resolves one field in the latest document revision.
  public func formField(_ identifier: PDFFormFieldIdentifier) async throws -> PDFFormField {
    try await interactiveStructure.formField(identifier, in: latestRevision.identifier)
  }

  /// Resolves one field in a selected document revision.
  public func formField(
    _ identifier: PDFFormFieldIdentifier,
    in revision: PDFRevisionIdentifier
  ) async throws -> PDFFormField {
    try await interactiveStructure.formField(identifier, in: revision)
  }

  /// Returns all fields in the latest document revision.
  public func formFields() async throws -> [PDFFormField] {
    try await interactiveStructure.formFields(in: latestRevision.identifier)
  }

  /// Returns all fields in a selected document revision.
  public func formFields(in revision: PDFRevisionIdentifier) async throws -> [PDFFormField] {
    try await interactiveStructure.formFields(in: revision)
  }

  /// Audits the complete latest AcroForm field tree and widget membership.
  public func validateAcroForm() async throws {
    try await interactiveStructure.validateAcroForm(in: latestRevision.identifier)
  }

  /// Audits an AcroForm field tree in a selected revision.
  public func validateAcroForm(in revision: PDFRevisionIdentifier) async throws {
    try await interactiveStructure.validateAcroForm(in: revision)
  }

  /// Returns reconciled Info and XMP metadata for the latest revision.
  public func metadata() async throws -> PDFMetadata {
    try await assets.metadata(in: latestRevision.identifier)
  }

  /// Returns reconciled Info and XMP metadata for a selected revision.
  public func metadata(in revision: PDFRevisionIdentifier) async throws -> PDFMetadata {
    try await assets.metadata(in: revision)
  }

  /// Parses an inert file specification in the latest revision.
  public func fileSpecification(_ object: PDFObject) async throws -> PDFFileSpecification {
    try await assets.fileSpecification(object, in: latestRevision.identifier)
  }

  /// Parses an inert file specification in a selected revision.
  public func fileSpecification(
    _ object: PDFObject,
    in revision: PDFRevisionIdentifier
  ) async throws -> PDFFileSpecification {
    try await assets.fileSpecification(object, in: revision)
  }

  /// Opens deterministic metadata-only enumeration of the latest embedded files.
  public func embeddedFiles() async throws -> PDFEmbeddedFileSequence {
    PDFEmbeddedFileSequence(files: try await assets.embeddedFiles(in: latestRevision.identifier))
  }

  /// Opens deterministic metadata-only enumeration of embedded files in a selected revision.
  public func embeddedFiles(in revision: PDFRevisionIdentifier) async throws -> PDFEmbeddedFileSequence {
    PDFEmbeddedFileSequence(files: try await assets.embeddedFiles(in: revision))
  }

  /// Returns every catalog and annotation associated-file declaration in the latest revision.
  public func associatedFiles() async throws -> [PDFAssociatedFile] {
    try await associatedFiles(in: latestRevision.identifier)
  }

  /// Returns every catalog and annotation associated-file declaration in a selected revision.
  public func associatedFiles(in revision: PDFRevisionIdentifier) async throws -> [PDFAssociatedFile] {
    var result = try await assets.catalogAssociatedFiles(in: revision)
    let pageCount = try await structure.pageCount(in: revision)
    for pageIndex in 0..<pageCount {
      let page = try await structure.page(at: pageIndex, in: revision)
      for annotation in try await interactiveStructure.annotations(on: page, in: revision) {
        guard let specification = annotation.details.payload.fileSpecification else { continue }
        let relationship: PDFAssociatedFileRelationship
        if case .dictionary(let dictionary) = specification.rawObject {
          relationship = .init(dictionary.pdfName(named: "AFRelationship"))
        } else { relationship = .unspecified }
        result.append(.init(
          fileSpecification: specification,
          relationship: relationship,
          owner: .annotation(annotation.identifier),
          revision: revision
        ))
      }
    }
    return result
  }

  /// Returns inert portable-collection metadata for the latest revision.
  public func collection() async throws -> PDFCollection? {
    try await assets.collection(in: latestRevision.identifier)
  }

  /// Returns inert portable-collection metadata for a selected revision.
  public func collection(in revision: PDFRevisionIdentifier) async throws -> PDFCollection? {
    try await assets.collection(in: revision)
  }

  /// Returns every signature visible in the latest document revision.
  public func signatures() async throws -> [PDFSignature] {
    try await authenticity.signatures(in: latestRevision.identifier)
  }

  /// Returns every signature visible in a selected document revision.
  public func signatures(in revision: PDFRevisionIdentifier) async throws -> [PDFSignature] {
    try await authenticity.signatures(in: revision)
  }

  /// Validates a signature against the latest document revision.
  public func validate(
    signature: PDFSignature,
    options: PDFSignatureValidationOptions = .init()
  ) async throws -> PDFSignatureValidationResult {
    try await authenticity.validate(signature, in: latestRevision.identifier, options: options)
  }

  /// Validates a signature and its later modifications as of a selected revision.
  public func validate(
    signature: PDFSignature,
    in revision: PDFRevisionIdentifier,
    options: PDFSignatureValidationOptions = .init()
  ) async throws -> PDFSignatureValidationResult {
    try await authenticity.validate(signature, in: revision, options: options)
  }

  /// Produces an authenticity report for the latest document revision.
  public func authenticityReport(
    options: PDFSignatureValidationOptions = .init()
  ) async throws -> PDFDocumentAuthenticityReport {
    try await authenticityReport(in: latestRevision.identifier, options: options)
  }

  /// Produces an authenticity report as of a selected document revision.
  public func authenticityReport(
    in revision: PDFRevisionIdentifier,
    options: PDFSignatureValidationOptions = .init()
  ) async throws -> PDFDocumentAuthenticityReport {
    let signatures = try await authenticity.signatures(in: revision)
    var results = [PDFSignatureValidationResult]()
    results.reserveCapacity(signatures.count)
    for signature in signatures {
      results.append(try await authenticity.validate(signature, in: revision, options: options))
    }
    return PDFDocumentAuthenticityReport(
      revision: revision,
      signatures: signatures,
      validationResults: results,
      documentPermissions: security?.effectivePermissions,
      diagnostics: results.flatMap(\.diagnostics)
    )
  }

  /// Produces a metadata-only inventory of the latest document's inert assets.
  public func assetInventory() async throws -> PDFDocumentAssetInventory {
    try await assetInventory(in: latestRevision.identifier)
  }

  /// Produces a metadata-only inventory of inert assets in a selected revision.
  public func assetInventory(in revision: PDFRevisionIdentifier) async throws -> PDFDocumentAssetInventory {
    let embedded = try await assets.embeddedFiles(in: revision)
    let signatures = try await authenticity.signatures(in: revision)
    return PDFDocumentAssetInventory(
      metadata: try await assets.metadata(in: revision),
      embeddedFiles: embedded.map { file in
        PDFEmbeddedFileSummary(
          identifier: file.fileSpecification.identifier,
          nameTreeKey: file.nameTreeKey,
          filename: file.fileSpecification.unicodeFilename,
          subtype: file.subtype,
          declaredSize: file.declaredSize,
          checksum: file.checksum,
          revision: file.definingRevision
        )
      },
      associatedFiles: try await associatedFiles(in: revision),
      collection: try await assets.collection(in: revision),
      signatures: signatures.map { signature in
        PDFSignatureDescriptor(
          identifier: signature.identifier,
          kind: signature.kind,
          subfilter: signature.subfilter,
          signedRevision: signature.signedRevision,
          signerSubjects: signature.signers.compactMap(\.certificate?.subject),
          transforms: signature.transforms
        )
      }
    )
  }

  /// Opens a validated, bounded stream over an embedded file's decoded bytes.
  public func decodedStream(of file: PDFEmbeddedFile) async throws -> PDFDecodedStream {
    let stream = try await resolver.decodedStream(file.stream)
    return PDFDecodedStream(state: PDFEmbeddedFileStreamState(
      stream: stream,
      declaredSize: file.declaredSize,
      checksum: file.checksum
    ))
  }

  /// Materializes and validates an embedded file within the configured stream limit.
  public func decodedBytes(of file: PDFEmbeddedFile) async throws -> Data {
    let stream = try await decodedStream(of: file)
    var result = Data()
    do {
      for try await chunk in stream {
        let (size, overflow) = result.count.addingReportingOverflow(chunk.count)
        guard !overflow, size <= resolver.parsingLimits.maximumDecodedStreamBytes else {
          throw PDFParsingError.limitExceeded(.init(offset: 0, message: "An embedded file exceeds its decoded byte limit."))
        }
        result.append(chunk)
      }
      return result
    } catch {
      await stream.close()
      throw error
    }
  }

  /// Resolves one logical structure element in the latest revision.
  public func structureElement(
    _ identifier: PDFStructureElementIdentifier
  ) async throws -> PDFStructureElement {
    try await structure.structureElement(identifier, in: latestRevision.identifier)
  }

  /// Resolves one logical structure element in a selected revision.
  public func structureElement(
    _ identifier: PDFStructureElementIdentifier,
    in revision: PDFRevisionIdentifier
  ) async throws -> PDFStructureElement {
    try await structure.structureElement(identifier, in: revision)
  }

  /// Audits the complete latest logical structure tree and its parent and ID trees.
  public func validateStructureTree() async throws {
    try await structure.validateStructureTree(in: latestRevision.identifier)
  }

  /// Audits the complete logical structure tree in a selected revision.
  public func validateStructureTree(in revision: PDFRevisionIdentifier) async throws {
    try await structure.validateStructureTree(in: revision)
  }

  /// Opens the exact ordered concatenation of a page's decoded content streams.
  public func decodedContent(of page: PDFPage) -> PDFDecodedPageContent {
    PDFDecodedPageContent(
      state: PDFDecodedPageContentState(
        streams: page.contentStreams,
        maximumBytes: resolver.parsingLimits.maximumDecodedPageContentBytes,
        open: { [resolver] stream in try await resolver.decodedStream(stream) }
      )
    )
  }

  /// Reads the exact encoded bytes of a resolved stream.
  public func encodedBytes(of stream: PDFStreamObject) async throws -> Data {
    try await resolver.readStream(stream)
  }

  /// Opens a bounded, single-pass decoder for a resolved stream.
  public func decodedStream(of stream: PDFStreamObject) async throws -> PDFDecodedStream {
    try await resolver.decodedStream(stream)
  }

  /// Materializes the decoded bytes of a resolved stream within configured limits.
  public func decodedBytes(of stream: PDFStreamObject) async throws -> Data {
    try await resolver.decodedBytes(stream)
  }

  /// Releases the source and all document-owned caches.
  public func close() async {
    await authenticity.close()
    await assets.close()
    await interactiveStructure.close()
    await structure.close()
    await resolver.close()
  }
}
