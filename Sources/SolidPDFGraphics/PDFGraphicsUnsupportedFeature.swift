import SolidPDF

/// A well-formed PDF graphics feature intentionally outside native interpretation support.
public enum PDFGraphicsUnsupportedFeature: Sendable, Hashable {
  /// A text-showing operator requires glyph realization.
  case textPainting
  /// A glyph program cannot supply an exact outline for PDF text clipping.
  case textClipping
  /// Optional-content configuration can change visibility.
  case optionalContent
  /// A nonidentity transparency feature is active.
  case transparency(PDFName)
  /// Overprint mode 1 is active.
  case overprintModeOne
  /// A reference XObject was selected.
  case referenceXObject
  /// A transparency-group form was selected.
  case transparencyGroup
  /// A decoded image format has no owned codec.
  case imageFilter(PDFName)
  /// A known PDF operator has semantics deferred to a later tranche.
  case operatorName(String)
}
