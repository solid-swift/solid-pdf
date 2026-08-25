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
  /// Maximum structure elements in one logical structure tree.
  public var maximumStructureElements: Int
  /// Maximum logical structure-tree depth.
  public var maximumStructureDepth: Int
  /// Maximum children retained by one structure element.
  public var maximumStructureChildren: Int
  /// Maximum scratch retained while auditing logical structure.
  public var maximumStructureScratchBytes: Int
  /// Maximum annotations associated with one page.
  public var maximumAnnotationsPerPage: Int
  /// Maximum fields in one AcroForm field tree.
  public var maximumFormFields: Int
  /// Maximum AcroForm field-tree depth.
  public var maximumFormFieldDepth: Int
  /// Maximum actions reachable through one `/Next` chain.
  public var maximumActionChainLength: Int
  /// Maximum named states in one annotation appearance dictionary.
  public var maximumAnnotationAppearanceStates: Int
  /// Maximum pairs in one signature byte range.
  public var maximumSignatureByteRanges: Int
  /// Maximum scratch retained while resolving annotations and forms.
  public var maximumInteractiveStructureScratchBytes: Int
  /// Maximum decoded bytes in one XMP metadata packet.
  public var maximumMetadataPacketBytes: Int
  /// Maximum element nesting in one XMP packet.
  public var maximumXMPNesting: Int
  /// Maximum retained properties in one XMP packet.
  public var maximumXMPProperties: Int
  /// Maximum file specifications retained by one revision inventory.
  public var maximumFileSpecifications: Int
  /// Maximum embedded-file name-tree entries in one revision.
  public var maximumEmbeddedFileEntries: Int
  /// Maximum fields in one portable-collection schema.
  public var maximumCollectionFields: Int
  /// Maximum discovered signatures in one document revision.
  public var maximumSignatures: Int
  /// Maximum signer records in one CMS container.
  public var maximumCMSSigners: Int
  /// Maximum certificates retained for one signature.
  public var maximumCertificates: Int
  /// Maximum nesting in one ASN.1 container.
  public var maximumASN1Nesting: Int
  /// Maximum timestamp tokens associated with one signature.
  public var maximumTimestamps: Int
  /// Maximum revocation-evidence objects associated with one validation.
  public var maximumRevocationObjects: Int
  /// Maximum temporary storage used by asset and authenticity processing.
  public var maximumAuthenticityScratchBytes: Int

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
    maximumOptionalContentExpressionDepth: Int = 128,
    maximumStructureElements: Int = 1_000_000,
    maximumStructureDepth: Int = 256,
    maximumStructureChildren: Int = 1_000_000,
    maximumStructureScratchBytes: Int = 64 * 1_024 * 1_024,
    maximumAnnotationsPerPage: Int = 65_536,
    maximumFormFields: Int = 1_000_000,
    maximumFormFieldDepth: Int = 256,
    maximumActionChainLength: Int = 1_024,
    maximumAnnotationAppearanceStates: Int = 4_096,
    maximumSignatureByteRanges: Int = 1_024,
    maximumInteractiveStructureScratchBytes: Int = 64 * 1_024 * 1_024,
    maximumMetadataPacketBytes: Int = 64 * 1_024 * 1_024,
    maximumXMPNesting: Int = 128,
    maximumXMPProperties: Int = 1_000_000,
    maximumFileSpecifications: Int = 1_000_000,
    maximumEmbeddedFileEntries: Int = 1_000_000,
    maximumCollectionFields: Int = 65_536,
    maximumSignatures: Int = 65_536,
    maximumCMSSigners: Int = 64,
    maximumCertificates: Int = 1_024,
    maximumASN1Nesting: Int = 128,
    maximumTimestamps: Int = 64,
    maximumRevocationObjects: Int = 4_096,
    maximumAuthenticityScratchBytes: Int = 512 * 1_024 * 1_024
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
    self.maximumStructureElements = maximumStructureElements
    self.maximumStructureDepth = maximumStructureDepth
    self.maximumStructureChildren = maximumStructureChildren
    self.maximumStructureScratchBytes = maximumStructureScratchBytes
    self.maximumAnnotationsPerPage = maximumAnnotationsPerPage
    self.maximumFormFields = maximumFormFields
    self.maximumFormFieldDepth = maximumFormFieldDepth
    self.maximumActionChainLength = maximumActionChainLength
    self.maximumAnnotationAppearanceStates = maximumAnnotationAppearanceStates
    self.maximumSignatureByteRanges = maximumSignatureByteRanges
    self.maximumInteractiveStructureScratchBytes = maximumInteractiveStructureScratchBytes
    self.maximumMetadataPacketBytes = maximumMetadataPacketBytes
    self.maximumXMPNesting = maximumXMPNesting
    self.maximumXMPProperties = maximumXMPProperties
    self.maximumFileSpecifications = maximumFileSpecifications
    self.maximumEmbeddedFileEntries = maximumEmbeddedFileEntries
    self.maximumCollectionFields = maximumCollectionFields
    self.maximumSignatures = maximumSignatures
    self.maximumCMSSigners = maximumCMSSigners
    self.maximumCertificates = maximumCertificates
    self.maximumASN1Nesting = maximumASN1Nesting
    self.maximumTimestamps = maximumTimestamps
    self.maximumRevocationObjects = maximumRevocationObjects
    self.maximumAuthenticityScratchBytes = maximumAuthenticityScratchBytes
  }

  /// Creates limits using the API surface that predates document-asset accounting.
  @_disfavoredOverload
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
    maximumOptionalContentExpressionDepth: Int = 128,
    maximumStructureElements: Int = 1_000_000,
    maximumStructureDepth: Int = 256,
    maximumStructureChildren: Int = 1_000_000,
    maximumStructureScratchBytes: Int = 64 * 1_024 * 1_024,
    maximumAnnotationsPerPage: Int = 65_536,
    maximumFormFields: Int = 1_000_000,
    maximumFormFieldDepth: Int = 256,
    maximumActionChainLength: Int = 1_024,
    maximumAnnotationAppearanceStates: Int = 4_096,
    maximumSignatureByteRanges: Int = 1_024,
    maximumInteractiveStructureScratchBytes: Int = 64 * 1_024 * 1_024
  ) {
    self.init(
      maximumInputBytes: maximumInputBytes,
      maximumObjectCount: maximumObjectCount,
      maximumRevisions: maximumRevisions,
      maximumPasswordAttempts: maximumPasswordAttempts,
      maximumCryptFilters: maximumCryptFilters,
      maximumSecurityScratchBytes: maximumSecurityScratchBytes,
      maximumNesting: maximumNesting,
      maximumTokenBytes: maximumTokenBytes,
      maximumStringBytes: maximumStringBytes,
      maximumArrayElements: maximumArrayElements,
      maximumDictionaryEntries: maximumDictionaryEntries,
      maximumDecodedStreamBytes: maximumDecodedStreamBytes,
      maximumCachedSourceBytes: maximumCachedSourceBytes,
      maximumCachedObjectBytes: maximumCachedObjectBytes,
      maximumStreamFilters: maximumStreamFilters,
      maximumStreamScratchBytes: maximumStreamScratchBytes,
      maximumCachedDecodedStreamBytes: maximumCachedDecodedStreamBytes,
      maximumStreamExpansionRatio: maximumStreamExpansionRatio,
      maximumTailSearchBytes: maximumTailSearchBytes,
      maximumPages: maximumPages,
      maximumPageTreeScratchBytes: maximumPageTreeScratchBytes,
      maximumPageContentStreams: maximumPageContentStreams,
      maximumDecodedPageContentBytes: maximumDecodedPageContentBytes,
      maximumGeneratedPageLabelBytes: maximumGeneratedPageLabelBytes,
      maximumOptionalContentGroups: maximumOptionalContentGroups,
      maximumOptionalContentExpressionDepth: maximumOptionalContentExpressionDepth,
      maximumStructureElements: maximumStructureElements,
      maximumStructureDepth: maximumStructureDepth,
      maximumStructureChildren: maximumStructureChildren,
      maximumStructureScratchBytes: maximumStructureScratchBytes,
      maximumAnnotationsPerPage: maximumAnnotationsPerPage,
      maximumFormFields: maximumFormFields,
      maximumFormFieldDepth: maximumFormFieldDepth,
      maximumActionChainLength: maximumActionChainLength,
      maximumAnnotationAppearanceStates: maximumAnnotationAppearanceStates,
      maximumSignatureByteRanges: maximumSignatureByteRanges,
      maximumInteractiveStructureScratchBytes: maximumInteractiveStructureScratchBytes,
      maximumMetadataPacketBytes: 64 * 1_024 * 1_024,
      maximumXMPNesting: 128,
      maximumXMPProperties: 1_000_000,
      maximumFileSpecifications: 1_000_000,
      maximumEmbeddedFileEntries: 1_000_000,
      maximumCollectionFields: 65_536,
      maximumSignatures: 65_536,
      maximumCMSSigners: 64,
      maximumCertificates: 1_024,
      maximumASN1Nesting: 128,
      maximumTimestamps: 64,
      maximumRevocationObjects: 4_096,
      maximumAuthenticityScratchBytes: 512 * 1_024 * 1_024
    )
  }
}
