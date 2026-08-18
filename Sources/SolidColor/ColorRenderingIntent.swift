/// A standard color-rendering intent.
public enum ColorRenderingIntent: String, Sendable, Hashable {
  /// Preserve perceptual relationships while mapping the source gamut.
  case perceptual
  /// Preserve in-gamut colors relative to the destination white point.
  case relativeColorimetric
  /// Prefer vividness over colorimetric accuracy.
  case saturation
  /// Preserve absolute colorimetry including the source white point.
  case absoluteColorimetric
}
