/// The published output and provenance of one incremental PDF update.
public struct PDFIncrementalUpdateResult<Output: Sendable>: Sendable {
  /// The sink-specific published output.
  public let output: Output
  /// The revision from which the transaction was planned.
  public let sourceRevision: PDFRevisionIdentifier
  /// Metadata for the newly appended revision.
  public let appendedRevision: PDFIncrementalUpdateRevision
  /// Exact bytes appended after the original source.
  public let appendedByteCount: Int
  /// Existing indirect objects redefined by the update.
  public let changedReferences: [PDFObjectReference]
  /// New indirect objects allocated by the update.
  public let newReferences: [PDFObjectReference]
  /// The effective version of the resulting PDF.
  public let effectiveVersion: PDFFileVersion
  /// Nonfatal update diagnostics.
  public let diagnostics: [PDFIncrementalUpdateDiagnostic]
}
