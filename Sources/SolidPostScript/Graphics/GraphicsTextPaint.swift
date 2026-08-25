/// One source-facing paint retained for exact text realization.
public struct GraphicsTextPaint: Sendable, Hashable {
  /// The resolved portable paint.
  public let paint: GraphicsPaint
  /// The original selected color space.
  public let colorSpace: GraphicsColorSpaceDescription
  /// The selected color-space realization, when required.
  public let colorRealization: GraphicsColorSpaceRealization?
  /// The original color components.
  public let components: [Double]
  /// Whether this paint overprints existing marks.
  public let overprint: Bool

  /// Creates text-paint metadata.
  public init(
    paint: GraphicsPaint,
    colorSpace: GraphicsColorSpaceDescription,
    colorRealization: GraphicsColorSpaceRealization? = nil,
    components: [Double],
    overprint: Bool = false
  ) {
    self.paint = paint
    self.colorSpace = colorSpace
    self.colorRealization = colorRealization
    self.components = components
    self.overprint = overprint
  }
}
