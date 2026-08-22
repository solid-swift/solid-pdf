import Foundation

/// A source capable of creating isolated random-access PDF input sessions.
public protocol PDFInputSource<Session>: Sendable {
  associatedtype Session: PDFInputSourceSession

  /// Creates an independent session for one PDF document.
  func makeSession() async throws -> sending Session
}

/// A random-access session retained for the lifetime of an open PDF document.
public protocol PDFInputSourceSession: AnyObject, Sendable {
  /// Returns the exact byte length of the source.
  func length() async throws -> Int64
  /// Reads exactly the requested range or throws.
  func read(_ range: PDFSourceRange) async throws -> Data
  /// Releases source resources. Repeated calls must be harmless.
  func close() async
}
