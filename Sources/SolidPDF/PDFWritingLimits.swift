/// Bounded resource limits for PDF construction.
public struct PDFWritingLimits: Sendable, Hashable {
  /// Maximum number of indirect objects.
  public var maximumObjectCount: Int
  /// Maximum direct-object nesting depth.
  public var maximumObjectNesting: Int
  /// Maximum uncompressed bytes accepted for one stream.
  public var maximumStreamBytes: Int
  /// Maximum emitted document bytes.
  public var maximumOutputBytes: Int
  /// Maximum temporary bytes retained by the writer.
  public var maximumTemporaryBytes: Int

  /// Creates writer limits.
  public init(
    maximumObjectCount: Int = 1_000_000,
    maximumObjectNesting: Int = 256,
    maximumStreamBytes: Int = 512 * 1_024 * 1_024,
    maximumOutputBytes: Int = 2 * 1_024 * 1_024 * 1_024,
    maximumTemporaryBytes: Int = 512 * 1_024 * 1_024
  ) {
    self.maximumObjectCount = maximumObjectCount
    self.maximumObjectNesting = maximumObjectNesting
    self.maximumStreamBytes = maximumStreamBytes
    self.maximumOutputBytes = maximumOutputBytes
    self.maximumTemporaryBytes = maximumTemporaryBytes
  }
}
