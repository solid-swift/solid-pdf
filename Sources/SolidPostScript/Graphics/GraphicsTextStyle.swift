/// The independent fill and stroke styling captured for a PDF text run.
public struct GraphicsTextStyle: Sendable, Hashable {
  /// The nonstroking text paint.
  public let fill: GraphicsTextPaint
  /// The stroking text paint.
  public let stroke: GraphicsTextPaint
  /// Transparency applied to nonstroking glyph marks.
  public let fillTransparency: GraphicsTransparencyState
  /// Transparency applied to stroking glyph marks.
  public let strokeTransparency: GraphicsTransparencyState

  /// Creates exact text styling metadata.
  public init(
    fill: GraphicsTextPaint,
    stroke: GraphicsTextPaint,
    fillTransparency: GraphicsTransparencyState = .opaque,
    strokeTransparency: GraphicsTransparencyState = .opaque
  ) {
    self.fill = fill
    self.stroke = stroke
    self.fillTransparency = fillTransparency
    self.strokeTransparency = strokeTransparency
  }
}
