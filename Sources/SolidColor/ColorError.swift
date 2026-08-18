/// An error produced while validating or converting portable color values.
public enum ColorError: Error, Sendable, Hashable {
  /// A component, matrix, or table value is outside its permitted range.
  case invalidValue
  /// A matrix required by the conversion is singular.
  case singularMatrix
  /// A color has the wrong number of components for its model.
  case componentCount
  /// A lookup table would exceed its declared or implementation bounds.
  case tableSize
}
