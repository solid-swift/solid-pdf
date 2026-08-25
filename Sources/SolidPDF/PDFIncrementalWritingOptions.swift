/// Options controlling native incremental PDF updates.
public struct PDFIncrementalWritingOptions: Sendable, Hashable {
  /// Resource limits applied while planning, writing, and validating the update.
  public var limits: PDFIncrementalWritingLimits

  /// Creates incremental-writing options.
  public init(limits: PDFIncrementalWritingLimits = .init()) {
    self.limits = limits
  }
}
