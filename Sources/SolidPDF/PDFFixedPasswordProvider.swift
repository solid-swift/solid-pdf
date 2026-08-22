/// A password provider that supplies one fixed credential.
public struct PDFFixedPasswordProvider: PDFPasswordProvider, Sendable {
  private let password: PDFPassword

  /// Creates a fixed-password provider.
  public init(_ password: PDFPassword) {
    self.password = password
  }

  /// Returns the fixed password on the first request.
  public func password(for request: PDFPasswordRequest) async throws -> PDFPassword? {
    request.attempt == 1 ? password : nil
  }
}
