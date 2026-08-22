import Foundation

/// Creates an isolated output session for one PDF document.
public protocol PDFOutputSink<Session>: Sendable {
  associatedtype Session: PDFOutputSinkSession

  /// Creates an output session.
  func makeSession() throws -> sending Session
}

/// Receives deterministic PDF bytes and publishes a typed result.
public protocol PDFOutputSinkSession<Output>: AnyObject {
  associatedtype Output

  /// Appends encoded bytes.
  func write(_ data: borrowing Data) throws
  /// Publishes the completed document.
  func finish(
    version: PDFVersion,
    pageCount: Int,
    diagnostics: [PDFDiagnostic]
  ) throws -> sending Output
  /// Publishes an incremental update while preserving the input file's exact version.
  ///
  /// The default adapter maps PDF 1.0 through 1.7 to the existing PDF 1.7 compatibility
  /// bucket and maps PDF 2.0 exactly. Sinks that retain file metadata may override this
  /// requirement to preserve every declared file version.
  func finishIncrementalUpdate(
    fileVersion: PDFFileVersion,
    pageCount: Int,
    diagnostics: [PDFDiagnostic]
  ) throws -> sending Output
  /// Abandons staged output.
  func abort()
}

extension PDFOutputSinkSession {
  public func finishIncrementalUpdate(
    fileVersion: PDFFileVersion,
    pageCount: Int,
    diagnostics: [PDFDiagnostic]
  ) throws -> sending Output {
    try finish(
      version: fileVersion == .v2_0 ? .v2_0 : .v1_7,
      pageCount: pageCount,
      diagnostics: diagnostics
    )
  }
}
