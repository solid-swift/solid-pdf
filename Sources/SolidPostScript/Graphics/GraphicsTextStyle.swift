/// The independent fill and stroke styling captured for a PDF text run.
public struct GraphicsTextStyle: Sendable, Hashable {
  /// The nonstroking text paint.
  public let fill: GraphicsTextPaint
  /// The stroking text paint.
  public let stroke: GraphicsTextPaint

  /// Creates exact text styling metadata.
  public init(fill: GraphicsTextPaint, stroke: GraphicsTextPaint) {
    self.fill = fill
    self.stroke = stroke
  }
}
