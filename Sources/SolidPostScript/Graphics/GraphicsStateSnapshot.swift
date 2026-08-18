import Foundation

/// An immutable snapshot of the canonical PostScript graphics state.
public struct GraphicsStateSnapshot: Sendable, Hashable {
  /// The current transformation matrix.
  public let matrix: GraphicsMatrix
  /// The current device-space path.
  public let path: GraphicsPath
  /// The current clipping region.
  public let clip: GraphicsClip
  /// The current paint.
  public let paint: GraphicsPaint
  /// The current line width.
  public let lineWidth: Double
  /// The current line-cap style.
  public let lineCap: GraphicsLineCap
  /// The current line-join style.
  public let lineJoin: GraphicsLineJoin
  /// The current miter limit.
  public let miterLimit: Double
  /// The current dash pattern.
  public let dash: GraphicsDash
  /// The curve-flattening tolerance in device pixels.
  public let flatness: Double
  /// Whether stroke adjustment is enabled.
  public let strokeAdjustment: Bool
  /// The explicit device-space path bounds established by `setbbox`, if any.
  public let pathBoundingBox: GraphicsRect?

  /// Creates a graphics-state snapshot.
  public init(
    matrix: GraphicsMatrix,
    path: GraphicsPath,
    clip: GraphicsClip,
    paint: GraphicsPaint,
    lineWidth: Double,
    lineCap: GraphicsLineCap,
    lineJoin: GraphicsLineJoin,
    miterLimit: Double,
    dash: GraphicsDash,
    flatness: Double = 1,
    strokeAdjustment: Bool = false,
    pathBoundingBox: GraphicsRect? = nil
  ) {
    self.matrix = matrix
    self.path = path
    self.clip = clip
    self.paint = paint
    self.lineWidth = lineWidth
    self.lineCap = lineCap
    self.lineJoin = lineJoin
    self.miterLimit = miterLimit
    self.dash = dash
    self.flatness = flatness
    self.strokeAdjustment = strokeAdjustment
    self.pathBoundingBox = pathBoundingBox
  }
}
