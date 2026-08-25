/// Bounded resource limits for one incremental PDF update.
public struct PDFIncrementalWritingLimits: Sendable, Hashable {
  /// Maximum form fields changed by one transaction.
  public var maximumFieldUpdates: Int
  /// Maximum indirect objects appended by one update.
  public var maximumAppendedObjects: Int
  /// Maximum decoded bytes in one generated appearance stream.
  public var maximumAppearanceStreamBytes: Int
  /// Maximum bytes appended after the original document.
  public var maximumAppendedBytes: Int
  /// Maximum bytes in the staged complete document.
  public var maximumStagedDocumentBytes: Int64
  /// Maximum temporary bytes retained while validating an update.
  public var maximumValidationScratchBytes: Int

  /// Creates incremental-update limits.
  public init(
    maximumFieldUpdates: Int = 65_536,
    maximumAppendedObjects: Int = 262_144,
    maximumAppearanceStreamBytes: Int = 64 * 1_024 * 1_024,
    maximumAppendedBytes: Int = 512 * 1_024 * 1_024,
    maximumStagedDocumentBytes: Int64 = 4 * 1_024 * 1_024 * 1_024,
    maximumValidationScratchBytes: Int = 512 * 1_024 * 1_024
  ) {
    self.maximumFieldUpdates = maximumFieldUpdates
    self.maximumAppendedObjects = maximumAppendedObjects
    self.maximumAppearanceStreamBytes = maximumAppearanceStreamBytes
    self.maximumAppendedBytes = maximumAppendedBytes
    self.maximumStagedDocumentBytes = maximumStagedDocumentBytes
    self.maximumValidationScratchBytes = maximumValidationScratchBytes
  }
}
