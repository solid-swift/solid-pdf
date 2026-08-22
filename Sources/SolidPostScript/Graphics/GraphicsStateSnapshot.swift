import Foundation
import SolidColor

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
  /// Immutable realization data for the selected color space, when required by a target.
  public let colorRealization: GraphicsColorSpaceRealization?
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
  /// The current transfer, color-adjustment, and halftone controls.
  public let deviceRendering: GraphicsDeviceRenderingSnapshot
  /// The current language-visible font.
  public let font: GraphicsFontDescription
  /// The current color-rendering intent.
  public let renderingIntent: ColorRenderingIntent

  /// Creates a graphics-state snapshot.
  public init(
    matrix: GraphicsMatrix,
    path: GraphicsPath,
    clip: GraphicsClip,
    paint: GraphicsPaint,
    colorSpace: GraphicsColorSpaceDescription = .deviceGray,
    colorRealization: GraphicsColorSpaceRealization? = nil,
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
    device: GraphicsDeviceSnapshot = .letter,
    deviceRendering: GraphicsDeviceRenderingSnapshot = .continuousTone,
    font: GraphicsFontDescription = .invalid,
    renderingIntent: ColorRenderingIntent = .relativeColorimetric
  ) {
    self.matrix = matrix
    self.path = path
    self.clip = clip
    self.paint = paint
    self.colorSpace = colorSpace
    self.colorRealization = colorRealization
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
    self.deviceRendering = deviceRendering
    self.font = font
    self.renderingIntent = renderingIntent
  }

  /// Returns a copy using the caller's current device-owned lifecycle state.
  public func replacingDevice(_ device: GraphicsDeviceSnapshot) -> Self {
    Self(
      matrix: matrix,
      path: path,
      clip: clip,
      paint: paint,
      colorSpace: colorSpace,
      colorRealization: colorRealization,
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
      device: device,
      deviceRendering: deviceRendering,
      font: font,
      renderingIntent: renderingIntent
    )
  }

  /// Returns a copy using one independently captured PDF text paint.
  public func replacingColor(with textPaint: GraphicsTextPaint) -> Self {
    Self(
      matrix: matrix,
      path: path,
      clip: clip,
      paint: textPaint.paint,
      colorSpace: textPaint.colorSpace,
      colorRealization: textPaint.colorRealization,
      colorComponents: textPaint.components,
      overprint: textPaint.overprint,
      lineWidth: lineWidth,
      lineCap: lineCap,
      lineJoin: lineJoin,
      miterLimit: miterLimit,
      dash: dash,
      flatness: flatness,
      strokeAdjustment: strokeAdjustment,
      smoothness: smoothness,
      pathBoundingBox: pathBoundingBox,
      device: device,
      deviceRendering: deviceRendering,
      font: font,
      renderingIntent: renderingIntent
    )
  }
}
