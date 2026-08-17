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
    dash: GraphicsDash
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
  }
}
