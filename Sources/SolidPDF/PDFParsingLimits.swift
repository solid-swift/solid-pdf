/// Bounded resource limits for parsing and resolving a PDF document.
public struct PDFParsingLimits: Sendable, Hashable {
  public var maximumInputBytes: Int64
  public var maximumObjectCount: Int
  public var maximumNesting: Int
  public var maximumTokenBytes: Int
  public var maximumStringBytes: Int
  public var maximumArrayElements: Int
  public var maximumDictionaryEntries: Int
  public var maximumDecodedStreamBytes: Int
  public var maximumCachedSourceBytes: Int
  public var maximumCachedObjectBytes: Int
  public var maximumTailSearchBytes: Int

  /// Creates parsing limits.
  public init(
    maximumInputBytes: Int64 = 4 * 1_024 * 1_024 * 1_024,
    maximumObjectCount: Int = 1_000_000,
    maximumNesting: Int = 128,
    maximumTokenBytes: Int = 16 * 1_024 * 1_024,
    maximumStringBytes: Int = 64 * 1_024 * 1_024,
    maximumArrayElements: Int = 1_000_000,
    maximumDictionaryEntries: Int = 1_000_000,
    maximumDecodedStreamBytes: Int = 512 * 1_024 * 1_024,
    maximumCachedSourceBytes: Int = 64 * 1_024 * 1_024,
    maximumCachedObjectBytes: Int = 64 * 1_024 * 1_024,
    maximumTailSearchBytes: Int = 1 * 1_024 * 1_024
  ) {
    self.maximumInputBytes = maximumInputBytes
    self.maximumObjectCount = maximumObjectCount
    self.maximumNesting = maximumNesting
    self.maximumTokenBytes = maximumTokenBytes
    self.maximumStringBytes = maximumStringBytes
    self.maximumArrayElements = maximumArrayElements
    self.maximumDictionaryEntries = maximumDictionaryEntries
    self.maximumDecodedStreamBytes = maximumDecodedStreamBytes
    self.maximumCachedSourceBytes = maximumCachedSourceBytes
    self.maximumCachedObjectBytes = maximumCachedObjectBytes
    self.maximumTailSearchBytes = maximumTailSearchBytes
  }
}
