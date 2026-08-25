/// One annotation appearance entry.
public enum PDFAnnotationAppearance: Sendable, Hashable {
  /// A single appearance stream.
  case stream(PDFStreamObject)
  /// A state-name dictionary of appearance streams.
  case states([PDFName: PDFStreamObject])
}

/// The normal, rollover, and down appearances associated with an annotation.
public struct PDFAnnotationAppearances: Sendable, Hashable {
  public let normal: PDFAnnotationAppearance?
  public let rollover: PDFAnnotationAppearance?
  public let down: PDFAnnotationAppearance?

  public init(
    normal: PDFAnnotationAppearance? = nil,
    rollover: PDFAnnotationAppearance? = nil,
    down: PDFAnnotationAppearance? = nil
  ) {
    self.normal = normal
    self.rollover = rollover
    self.down = down
  }
}
