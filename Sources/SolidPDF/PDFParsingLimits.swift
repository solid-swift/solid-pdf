/// Bounded resource limits for parsing and resolving a PDF document.
public struct PDFParsingLimits: Sendable, Hashable {
  /// Maximum complete input size.
  public var maximumInputBytes: Int64
  /// Maximum declared object count.
  public var maximumObjectCount: Int
  /// Maximum number of incremental revisions.
  public var maximumRevisions: Int
  /// Maximum password candidates requested from a provider.
  public var maximumPasswordAttempts: Int
  /// Maximum named crypt filters in one security dictionary.
  public var maximumCryptFilters: Int
  /// Maximum temporary security-handler storage.
  public var maximumSecurityScratchBytes: Int
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
  /// Maximum filters applied to one stream.
  public var maximumStreamFilters: Int
  /// Maximum temporary bytes retained while decoding one stream.
  public var maximumStreamScratchBytes: Int
  /// Maximum bytes retained by the decoded-stream cache.
  public var maximumCachedDecodedStreamBytes: Int
  /// Maximum decoded-to-encoded expansion after the first decoded MiB.
  public var maximumStreamExpansionRatio: Int
  /// Maximum terminal bytes searched for `startxref` and `%%EOF`.
  public var maximumTailSearchBytes: Int
  /// Maximum number of leaf pages in one page tree.
  public var maximumPages: Int
  /// Maximum temporary storage used while validating one page tree.
  public var maximumPageTreeScratchBytes: Int
  /// Maximum content streams associated with one page.
  public var maximumPageContentStreams: Int
  /// Maximum aggregate decoded content for one page.
  public var maximumDecodedPageContentBytes: Int
  /// Maximum generated page-label text.
  public var maximumGeneratedPageLabelBytes: Int
  /// Maximum optional-content groups in one document configuration.
  public var maximumOptionalContentGroups: Int
  /// Maximum nesting depth of an optional-content visibility expression.
  public var maximumOptionalContentExpressionDepth: Int

  /// Creates parsing limits.
  public init(
    maximumInputBytes: Int64 = 4 * 1_024 * 1_024 * 1_024,
    maximumObjectCount: Int = 1_000_000,
    maximumRevisions: Int = 1_024,
    maximumPasswordAttempts: Int = 8,
    maximumCryptFilters: Int = 64,
    maximumSecurityScratchBytes: Int = 1 * 1_024 * 1_024,
    maximumNesting: Int = 128,
    maximumTokenBytes: Int = 16 * 1_024 * 1_024,
    maximumStringBytes: Int = 64 * 1_024 * 1_024,
    maximumArrayElements: Int = 1_000_000,
    maximumDictionaryEntries: Int = 1_000_000,
    maximumDecodedStreamBytes: Int = 512 * 1_024 * 1_024,
    maximumCachedSourceBytes: Int = 64 * 1_024 * 1_024,
    maximumCachedObjectBytes: Int = 64 * 1_024 * 1_024,
    maximumStreamFilters: Int = 16,
    maximumStreamScratchBytes: Int = 64 * 1_024 * 1_024,
    maximumCachedDecodedStreamBytes: Int = 64 * 1_024 * 1_024,
    maximumStreamExpansionRatio: Int = 1_000,
    maximumTailSearchBytes: Int = 1 * 1_024 * 1_024,
    maximumPages: Int = 1_000_000,
    maximumPageTreeScratchBytes: Int = 64 * 1_024 * 1_024,
    maximumPageContentStreams: Int = 65_536,
    maximumDecodedPageContentBytes: Int = 512 * 1_024 * 1_024,
    maximumGeneratedPageLabelBytes: Int = 1 * 1_024 * 1_024,
    maximumOptionalContentGroups: Int = 65_536,
    maximumOptionalContentExpressionDepth: Int = 128
  ) {
    self.maximumInputBytes = maximumInputBytes
    self.maximumObjectCount = maximumObjectCount
    self.maximumRevisions = maximumRevisions
    self.maximumPasswordAttempts = maximumPasswordAttempts
    self.maximumCryptFilters = maximumCryptFilters
    self.maximumSecurityScratchBytes = maximumSecurityScratchBytes
    self.maximumNesting = maximumNesting
    self.maximumTokenBytes = maximumTokenBytes
    self.maximumStringBytes = maximumStringBytes
    self.maximumArrayElements = maximumArrayElements
    self.maximumDictionaryEntries = maximumDictionaryEntries
    self.maximumDecodedStreamBytes = maximumDecodedStreamBytes
    self.maximumCachedSourceBytes = maximumCachedSourceBytes
    self.maximumCachedObjectBytes = maximumCachedObjectBytes
    self.maximumStreamFilters = maximumStreamFilters
    self.maximumStreamScratchBytes = maximumStreamScratchBytes
    self.maximumCachedDecodedStreamBytes = maximumCachedDecodedStreamBytes
    self.maximumStreamExpansionRatio = maximumStreamExpansionRatio
    self.maximumTailSearchBytes = maximumTailSearchBytes
    self.maximumPages = maximumPages
    self.maximumPageTreeScratchBytes = maximumPageTreeScratchBytes
    self.maximumPageContentStreams = maximumPageContentStreams
    self.maximumDecodedPageContentBytes = maximumDecodedPageContentBytes
    self.maximumGeneratedPageLabelBytes = maximumGeneratedPageLabelBytes
    self.maximumOptionalContentGroups = maximumOptionalContentGroups
    self.maximumOptionalContentExpressionDepth = maximumOptionalContentExpressionDepth
  }
}
