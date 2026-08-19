import Foundation

/// An error produced while validating or decoding portable font data.
public enum FontError: Error, Sendable, Hashable {
  /// The input does not conform to its declared font format.
  case invalidData
  /// A numeric value or collection is outside the supported range.
  case range
  /// Processing would exceed the configured implementation limits.
  case limitExceeded
  /// The declared font format is not supported by the selected backend.
  case unsupportedFormat
  /// A requested glyph is not present in the font.
  case missingGlyph
}
