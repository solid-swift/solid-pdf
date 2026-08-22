/// Bounded resource limits for parsing and resolving a PDF document.
public struct PDFParsingLimits: Sendable, Hashable {
  /// Maximum complete input size.
  public var maximumInputBytes: Int64
  /// Maximum declared object count.
  public var maximumObjectCount: Int
  /// Maximum nested array, dictionary, or string depth.
  public var maximumNesting: Int
  /// Maximum lexical token size.
  public var maximumTokenBytes: Int
  /// Maximum decoded string size.
  public var maximumStringBytes: Int
  /// Maximum elements in one array.
  public var maximumArrayElements: Int
  /// Maximum entries in one dictionary.
  public var maximumDictionaryEntries: Int
  /// Maximum bytes in one decoded structural stream.
  public var maximumDecodedStreamBytes: Int
  /// Maximum bytes retained by the source-window cache.
  public var maximumCachedSourceBytes: Int
  /// Maximum bytes retained by object and object-stream caches.
  public var maximumCachedObjectBytes: Int
  /// Maximum terminal bytes searched for `startxref` and `%%EOF`.
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
