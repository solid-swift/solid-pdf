/// An immutable realized PostScript tiling pattern.
public struct GraphicsTilingPattern: Sendable, Hashable {
  /// Whether the cell supplies its own colors (`1`) or acts as a mask (`2`).
  public let paintType: Int
  /// The requested tiling-adjustment policy (`1`, `2`, or `3`).
  public let tilingType: Int
  /// The pattern-cell bounding box in pattern space.
  public let bounds: GraphicsRect
  /// The horizontal cell displacement in pattern space.
  public let xStep: Double
  /// The vertical cell displacement in pattern space.
  public let yStep: Double
  /// The locked pattern-space to device-space transformation.
  public let matrix: GraphicsMatrix
  /// The realized key-cell effects in device space.
  public let displayList: GraphicsDisplayList

  /// Creates a realized tiling pattern.
  public init(
    paintType: Int,
    tilingType: Int,
    bounds: GraphicsRect,
    xStep: Double,
    yStep: Double,
    matrix: GraphicsMatrix,
    displayList: GraphicsDisplayList
  ) {
    self.paintType = paintType
    self.tilingType = tilingType
    self.bounds = bounds
    self.xStep = xStep
    self.yStep = yStep
    self.matrix = matrix
    self.displayList = displayList
  }
}
