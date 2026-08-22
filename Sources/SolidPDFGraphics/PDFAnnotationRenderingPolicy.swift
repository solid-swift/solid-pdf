/// Selects which annotation appearances participate in page rendering.
public enum PDFAnnotationRenderingPolicy: Sendable, Hashable {
  /// Do not paint annotation appearances.
  case none
  /// Use the render access purpose to select view or print annotations.
  case purposeAware
  /// Paint annotations eligible for interactive viewing.
  case view
  /// Paint annotations eligible for printing.
  case print
  /// Paint every annotation that has an appearance.
  case all
}

/// Controls whether missing standard annotation appearances may be generated.
public enum PDFAnnotationAppearancePolicy: Sendable, Hashable {
  /// Require an existing selected appearance.
  case existingOnly
  /// Generate a deterministic standard appearance only when `/AP` is absent.
  case generateMissingStandard
}
