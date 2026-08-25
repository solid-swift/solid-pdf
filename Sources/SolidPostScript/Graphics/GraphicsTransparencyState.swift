import SolidColor

/// The transparency parameters captured for an elementary graphics object.
public struct GraphicsTransparencyState: Sendable, Hashable {
  /// The blend function applied to overlapping source and backdrop colors.
  public let blendMode: GraphicsBlendMode
  /// The constant alpha applied to the object.
  public let constantAlpha: Double
  /// Whether constant alpha modifies shape rather than opacity.
  public let alphaIsShape: Bool
  /// The active soft mask, if any.
  public let softMask: GraphicsSoftMask?
  /// Whether glyphs in a text object knock out earlier glyphs in that object.
  public let textKnockout: Bool

  /// Creates transparency state.
  public init(
    blendMode: GraphicsBlendMode = .normal,
    constantAlpha: Double = 1,
    alphaIsShape: Bool = false,
    softMask: GraphicsSoftMask? = nil,
    textKnockout: Bool = true
  ) {
    self.blendMode = blendMode
    self.constantAlpha = constantAlpha
    self.alphaIsShape = alphaIsShape
    self.softMask = softMask
    self.textKnockout = textKnockout
  }

  /// Fully opaque Normal compositing with no soft mask.
  public static let opaque = Self()
}
