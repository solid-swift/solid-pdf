/// A font-program representation suitable for embedding in a document.
public enum FontEmbeddedProgramFormat: Sendable, Hashable {
  /// An Adobe Type 1 PFA or PFB program.
  case type1
  /// A name-keyed Compact Font Format version 1 program.
  case nameKeyedCFF
  /// A CID-keyed Compact Font Format version 1 program.
  case cidKeyedCFF
  /// A standalone TrueType-flavored sfnt program.
  case trueType
}
