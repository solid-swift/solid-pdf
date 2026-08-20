import Foundation

/// A binary-safe PDF name value.
public struct PDFName: Sendable, Hashable, Comparable, ExpressibleByStringLiteral {
  /// The unescaped bytes of the name.
  public let bytes: Data

  /// Creates a name from UTF-8 text.
  public init(_ value: String) {
    bytes = Data(value.utf8)
  }

  /// Creates a name from arbitrary bytes.
  public init(bytes: Data) {
    self.bytes = bytes
  }

  /// Creates a name from a string literal.
  public init(stringLiteral value: String) {
    self.init(value)
  }

  public static func < (lhs: PDFName, rhs: PDFName) -> Bool {
    lhs.bytes.lexicographicallyPrecedes(rhs.bytes)
  }
}
