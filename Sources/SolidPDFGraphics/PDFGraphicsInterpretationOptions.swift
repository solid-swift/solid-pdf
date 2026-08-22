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

  /// Creates interpretation options.
  public init(
    pageBoundary: PDFPageBoundaryKind = .crop,
    accessPurpose: PDFGraphicsAccessPurpose = .viewing,
    strict: Bool = true,
    limits: PDFGraphicsLimits = .init()
  ) {
    self.pageBoundary = pageBoundary
    self.accessPurpose = accessPurpose
    self.strict = strict
    self.limits = limits
  }
}
