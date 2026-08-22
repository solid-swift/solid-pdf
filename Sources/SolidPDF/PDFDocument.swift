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

  private let resolver: PDFDocumentResolver<Source.Session>

  /// Opens and validates one PDF revision without eagerly resolving its objects.
  public init(
    source: Source,
    options: PDFParsingOptions = .init(),
    externalStreamProvider: (any PDFExternalStreamProvider)? = nil
  ) async throws {
    let session = try await source.makeSession()
    do {
      let reader = try await PDFSourceReader(session: session, options: options)
      let index = try await PDFCrossReferenceParser(reader: reader, options: options).parse()
      version = index.version
      root = index.root
      info = index.info
      identifier = index.identifier
      resolver = PDFDocumentResolver(
        reader: reader,
        index: index,
        options: options,
        externalStreamProvider: externalStreamProvider
      )
    } catch {
      await session.close()
      throw error
    }
  }

  deinit {
    let resolver = resolver
    Task { await resolver.close() }
  }

  /// Resolves an indirect object on demand.
  public func resolve(_ reference: PDFObjectReference) async throws -> PDFIndirectObject {
    try await resolver.resolve(reference)
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
