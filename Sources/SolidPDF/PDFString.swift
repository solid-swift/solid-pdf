import Foundation

/// A binary-safe PDF string value.
public struct PDFString: Sendable, Hashable, ExpressibleByStringLiteral {
  /// The preferred serialization form.
  public enum Representation: Sendable, Hashable {
    /// Select the most compact deterministic form.
    case automatic
    /// Use PDF literal-string escaping.
    case literal
    /// Use hexadecimal serialization.
    case hexadecimal
  }

  /// The string bytes.
  public let bytes: Data
  /// The preferred serialization form.
  public let representation: Representation

  /// Creates a UTF-8 string.
  public init(_ value: String, representation: Representation = .automatic) {
    bytes = Data(value.utf8)
    self.representation = representation
  }

  /// Creates a binary string.
  public init(bytes: Data, representation: Representation = .automatic) {
    self.bytes = bytes
    self.representation = representation
  }

  /// Creates a string from a string literal.
  public init(stringLiteral value: String) {
    self.init(value)
  }
}
