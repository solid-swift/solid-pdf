/// A PDF page boundary kind.
public enum PDFPageBoundaryKind: Sendable, Hashable, CaseIterable {
  case media
  case crop
  case bleed
  case trim
  case art
}

/// A declared page boundary and its effective media-clipped rectangle.
public struct PDFPageBoundary: Sendable, Hashable {
  /// The declared or defaulted rectangle with provenance.
  public let declared: PDFPageAttribute<PDFRectangle>
  /// The rectangle used after intersecting it with the media box where required.
  public let effective: PDFRectangle

  /// Creates a page boundary.
  public init(declared: PDFPageAttribute<PDFRectangle>, effective: PDFRectangle) {
    self.declared = declared
    self.effective = effective
  }
}

/// A normalized clockwise page rotation.
public enum PDFPageRotation: Int, Sendable, Hashable, CaseIterable {
  case degrees0 = 0
  case degrees90 = 90
  case degrees180 = 180
  case degrees270 = 270
}

/// Effective geometry and attribute provenance for one PDF page.
public struct PDFPageGeometry: Sendable, Hashable {
  public let mediaBox: PDFPageBoundary
  public let cropBox: PDFPageBoundary
  public let bleedBox: PDFPageBoundary
  public let trimBox: PDFPageBoundary
  public let artBox: PDFPageBoundary
  public let rotation: PDFPageAttribute<PDFPageRotation>
  public let userUnit: PDFPageAttribute<Double>

  package init(
    mediaBox: PDFPageBoundary,
    cropBox: PDFPageBoundary,
    bleedBox: PDFPageBoundary,
    trimBox: PDFPageBoundary,
    artBox: PDFPageBoundary,
    rotation: PDFPageAttribute<PDFPageRotation>,
    userUnit: PDFPageAttribute<Double>
  ) {
    self.mediaBox = mediaBox
    self.cropBox = cropBox
    self.bleedBox = bleedBox
    self.trimBox = trimBox
    self.artBox = artBox
    self.rotation = rotation
    self.userUnit = userUnit
  }
}
