/// A named-destination key represented exactly as a PDF name or string.
public enum PDFDestinationName: Sendable, Hashable {
  case name(PDFName)
  case string(PDFString)
}

/// The view established by an explicit PDF destination.
public enum PDFDestinationView: Sendable, Hashable {
  case xyz(left: Double?, top: Double?, zoom: Double?)
  case fit
  case fitHorizontal(top: Double?)
  case fitVertical(left: Double?)
  case fitRectangle(PDFRectangle)
  case fitBoundingBox
  case fitBoundingBoxHorizontal(top: Double?)
  case fitBoundingBoxVertical(left: Double?)
}

/// An inert PDF destination.
public enum PDFDestination: Sendable, Hashable {
  case explicit(page: PDFObject, view: PDFDestinationView)
  case named(PDFDestinationName)
}
