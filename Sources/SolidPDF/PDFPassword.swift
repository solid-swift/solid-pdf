import Foundation

/// A password candidate supplied to a PDF standard security handler.
///
/// Password values deliberately provide no textual or debugging representation.
public struct PDFPassword: Sendable, Hashable {
  package enum Storage: Sendable, Hashable {
    case unicode(String)
    case bytes(Data)
  }

  package let storage: Storage

  /// Creates a password from Unicode text.
  public init(_ value: String) {
    storage = .unicode(value)
  }

  /// Creates a compatibility password from the exact supplied bytes.
  public init(exactBytes: Data) {
    storage = .bytes(exactBytes)
  }
}

extension PDFPassword: CustomStringConvertible, CustomDebugStringConvertible {
  /// A redacted description that never reveals password content.
  public var description: String { "<redacted PDF password>" }
  /// A redacted debugging description that never reveals password content.
  public var debugDescription: String { description }
}
