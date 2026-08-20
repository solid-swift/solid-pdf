/// A PNG validation or output failure.
public enum PNGEncodingError: Swift.Error, Sendable, Equatable {
  case invalidOptions
  case invalidImage
  case outputExists
  case outputFailure
  case compressionFailure
}
