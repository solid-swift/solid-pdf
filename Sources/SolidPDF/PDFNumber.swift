/// A finite PDF numeric value.
public enum PDFNumber: Sendable, Hashable {
  /// A signed integer.
  case integer(Int64)
  /// A finite real number.
  case real(Double)
}
