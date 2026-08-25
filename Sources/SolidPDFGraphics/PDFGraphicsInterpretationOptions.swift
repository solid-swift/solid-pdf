import SolidPDF

/// Controls native PDF content interpretation into semantic graphics events.
public struct PDFGraphicsInterpretationOptions: Sendable, Hashable {
  /// The effective page boundary used as the page viewport.
  public let pageBoundary: PDFPageBoundaryKind
  /// The permission purpose checked before target sessions are created.
  public let accessPurpose: PDFGraphicsAccessPurpose
  /// Whether unknown operators and invalid graphics-object states are rejected.
  public let strict: Bool
  /// Resource limits for interpretation.
  public let limits: PDFGraphicsLimits
  /// The optional-content configuration and caller overrides.
  public let optionalContentSelection: PDFOptionalContentSelection
  /// The environment used for optional-content usage applications.
  public let optionalContentContext: PDFOptionalContentContext
  /// The annotations painted after page content.
  public let annotationRenderingPolicy: PDFAnnotationRenderingPolicy
  /// Whether absent standard appearances may be generated.
  public let annotationAppearancePolicy: PDFAnnotationAppearancePolicy

  /// Creates interpretation options.
  public init(
    pageBoundary: PDFPageBoundaryKind = .crop,
    accessPurpose: PDFGraphicsAccessPurpose = .viewing,
    strict: Bool = true,
    limits: PDFGraphicsLimits = .init(),
    optionalContentSelection: PDFOptionalContentSelection = .documentDefault,
    optionalContentContext: PDFOptionalContentContext = .init(),
    annotationRenderingPolicy: PDFAnnotationRenderingPolicy = .purposeAware,
    annotationAppearancePolicy: PDFAnnotationAppearancePolicy = .existingOnly
  ) {
    self.pageBoundary = pageBoundary
    self.accessPurpose = accessPurpose
    self.strict = strict
    self.limits = limits
    self.optionalContentSelection = optionalContentSelection
    self.optionalContentContext = optionalContentContext
    self.annotationRenderingPolicy = annotationRenderingPolicy
    self.annotationAppearancePolicy = annotationAppearancePolicy
  }
}
