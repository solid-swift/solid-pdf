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
  /// The current color-space description.
  public let colorSpace: GraphicsColorSpaceDescription
  /// The current components in the current color space.
  public let colorComponents: [Double]
  /// Whether overprinting is enabled.
  public let overprint: Bool
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
  /// The device-limited color-error tolerance used to tessellate shadings.
  public let smoothness: Double
  /// The explicit device-space path bounds established by `setbbox`, if any.
  public let pathBoundingBox: GraphicsRect?
  /// The current output device and page-lifecycle state.
  public let device: GraphicsDeviceSnapshot

  /// Creates a graphics-state snapshot.
  public init(
    matrix: GraphicsMatrix,
    path: GraphicsPath,
    clip: GraphicsClip,
    paint: GraphicsPaint,
    colorSpace: GraphicsColorSpaceDescription = .deviceGray,
    colorComponents: [Double] = [0],
    overprint: Bool = false,
    lineWidth: Double,
    lineCap: GraphicsLineCap,
    lineJoin: GraphicsLineJoin,
    miterLimit: Double,
    dash: GraphicsDash,
    flatness: Double = 1,
    strokeAdjustment: Bool = false,
    smoothness: Double = 0.02,
    pathBoundingBox: GraphicsRect? = nil,
    device: GraphicsDeviceSnapshot = .letter
  ) {
    self.matrix = matrix
    self.path = path
    self.clip = clip
    self.paint = paint
    self.colorSpace = colorSpace
    self.colorComponents = colorComponents
    self.overprint = overprint
    self.lineWidth = lineWidth
    self.lineCap = lineCap
    self.lineJoin = lineJoin
    self.miterLimit = miterLimit
    self.dash = dash
    self.flatness = flatness
    self.strokeAdjustment = strokeAdjustment
    self.smoothness = smoothness
    self.pathBoundingBox = pathBoundingBox
    self.device = device
  }

  func replacingDevice(_ device: GraphicsDeviceSnapshot) -> Self {
    Self(
      matrix: matrix,
      path: path,
      clip: clip,
      paint: paint,
      colorSpace: colorSpace,
      colorComponents: colorComponents,
      overprint: overprint,
      lineWidth: lineWidth,
      lineCap: lineCap,
      lineJoin: lineJoin,
      miterLimit: miterLimit,
      dash: dash,
      flatness: flatness,
      strokeAdjustment: strokeAdjustment,
      smoothness: smoothness,
      pathBoundingBox: pathBoundingBox,
      device: device
    )
  }
}
