/// The credential class accepted by a PDF standard security handler.
public enum PDFAuthenticationKind: Sendable, Hashable {
  /// The document accepted the automatically attempted empty user password.
  case defaultUser
  /// The document accepted a supplied user password.
  case user
  /// The document accepted a supplied owner password.
  case owner
}
