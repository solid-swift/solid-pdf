/// A normalized rectangle in PDF default user space.
public struct PDFRectangle: Sendable, Hashable {
  /// The minimum horizontal coordinate.
  public let minimumX: Double
  /// The minimum vertical coordinate.
  public let minimumY: Double
  /// The maximum horizontal coordinate.
  public let maximumX: Double
  /// The maximum vertical coordinate.
  public let maximumY: Double

  /// Creates a rectangle while normalizing opposite-corner order.
  public init(x1: Double, y1: Double, x2: Double, y2: Double) throws {
    guard x1.isFinite, y1.isFinite, x2.isFinite, y2.isFinite else {
      throw PDFRectangleError.nonfiniteCoordinate
    }
    minimumX = min(x1, x2)
    minimumY = min(y1, y2)
    maximumX = max(x1, x2)
    maximumY = max(y1, y2)
  }

  package func intersection(with other: PDFRectangle) -> PDFRectangle {
    let lowerX = max(minimumX, other.minimumX)
    let lowerY = max(minimumY, other.minimumY)
    let upperX = max(lowerX, min(maximumX, other.maximumX))
    let upperY = max(lowerY, min(maximumY, other.maximumY))
    return try! PDFRectangle(x1: lowerX, y1: lowerY, x2: upperX, y2: upperY)
  }
}

/// An error raised while constructing a PDF rectangle.
public enum PDFRectangleError: Error, Sendable, Hashable {
  /// One or more coordinates are not finite.
  case nonfiniteCoordinate
}
