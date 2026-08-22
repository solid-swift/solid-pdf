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
  /// Opt-in generation was requested for an annotation not yet supported by the generator.
  case annotationAppearanceGeneration
}

extension PDFAnnotationDetails {
  var payload: PDFAnnotationPayload {
    switch self {
    case .text(let value), .link(let value), .freeText(let value), .line(let value),
      .square(let value), .circle(let value), .polygon(let value), .polyLine(let value),
      .highlight(let value), .underline(let value), .squiggly(let value), .strikeOut(let value),
      .stamp(let value), .caret(let value), .ink(let value), .popup(let value),
      .fileAttachment(let value), .sound(let value), .movie(let value), .widget(let value),
      .screen(let value), .printerMark(let value), .trapNet(let value), .watermark(let value),
      .threeD(let value), .redact(let value), .projection(let value), .richMedia(let value),
      .unknown(_, let value): value
    }
  }
}
