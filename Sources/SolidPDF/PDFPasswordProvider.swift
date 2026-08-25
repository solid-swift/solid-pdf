/// Supplies bounded password candidates while an encrypted PDF is opened.
public protocol PDFPasswordProvider: Sendable {
  /// Returns the next password candidate, or `nil` to stop authentication.
  func password(for request: PDFPasswordRequest) async throws -> PDFPassword?
}
