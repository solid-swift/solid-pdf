/// A PDF page boundary kind.
public enum PDFPageBoundaryKind: Sendable, Hashable, CaseIterable {
  /// The physical media boundary.
  case media
  /// The default display or print boundary.
  case crop
  /// The production bleed boundary.
  case bleed
  /// The intended finished-page boundary.
  case trim
  /// The meaningful artwork boundary.
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
  /// No clockwise rotation.
  case degrees0 = 0
  /// Ninety degrees clockwise.
  case degrees90 = 90
  /// One hundred eighty degrees clockwise.
  case degrees180 = 180
  /// Two hundred seventy degrees clockwise.
  case degrees270 = 270
}

/// Effective geometry and attribute provenance for one PDF page.
public struct PDFPageGeometry: Sendable, Hashable {
  /// The required effective media boundary.
  public let mediaBox: PDFPageBoundary
  /// The effective crop boundary.
  public let cropBox: PDFPageBoundary
  /// The effective bleed boundary.
  public let bleedBox: PDFPageBoundary
  /// The effective trim boundary.
  public let trimBox: PDFPageBoundary
  /// The effective artwork boundary.
  public let artBox: PDFPageBoundary
  /// The normalized clockwise page rotation.
  public let rotation: PDFPageAttribute<PDFPageRotation>
  /// The positive default-user-space unit scale.
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
