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

  private let resolver: PDFDocumentResolver<Source.Session>

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
      let index = try await PDFCrossReferenceParser(reader: reader, options: options).parse()
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
      resolver = PDFDocumentResolver(
        reader: reader,
        index: index,
        options: options,
        externalStreamProvider: externalStreamProvider,
        securityContext: securityContext
      )
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
    Task { await resolver.close() }
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
    await resolver.close()
  }
}
