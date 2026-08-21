/// A PostScript bounding rectangle expressed in default-user-space points.
public struct PostScriptDocumentBounds: Sendable, Hashable {
  public let lowerX: Double
  public let lowerY: Double
  public let upperX: Double
  public let upperY: Double

  /// Creates finite, ordered document bounds.
  public init(lowerX: Double, lowerY: Double, upperX: Double, upperY: Double) throws {
    guard lowerX.isFinite, lowerY.isFinite, upperX.isFinite, upperY.isFinite,
      lowerX <= upperX, lowerY <= upperY
    else { throw PostScriptDocumentError.invalidBoundingBox }
    self.lowerX = lowerX
    self.lowerY = lowerY
    self.upperX = upperX
    self.upperY = upperY
  }

  public var width: Double { upperX - lowerX }
  public var height: Double { upperY - lowerY }
}
