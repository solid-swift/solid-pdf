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
  /// Abandons staged output.
  func abort()
}
