/// A portable matrix-and-transfer-curve destination color profile.
public struct ColorDestinationProfile: Sendable, Hashable {
  /// The destination process-color model.
  public enum Model: Int, Sendable, Hashable {
    /// One gray component.
    case gray = 1
    /// Three RGB components.
    case rgb = 3
    /// Four CMYK components.
    case cmyk = 4
  }

  /// The profile's process-color model.
  public let model: Model
  /// The profile reference white.
  public let whitePoint: ColorXYZ
  /// Transformation from linear RGB to XYZ when the model is RGB.
  public let rgbToXYZ: ColorMatrix3x3
  /// Per-component encoding curves.
  public let transferCurves: [ColorTransferCurve]

  /// Creates a destination profile.
  public init(
    model: Model,
    whitePoint: ColorXYZ = .d65,
    rgbToXYZ: ColorMatrix3x3 = .identity,
    transferCurves: [ColorTransferCurve]
  ) throws(ColorError) {
    guard [1, model.rawValue].contains(transferCurves.count),
      [whitePoint.x, whitePoint.y, whitePoint.z].allSatisfy({ $0.isFinite && $0 > 0 }),
      model != .rgb || rgbToXYZ.inverted != nil
    else { throw .invalidValue }
    self.model = model
    self.whitePoint = whitePoint
    self.rgbToXYZ = rgbToXYZ
    self.transferCurves = transferCurves
  }

  /// The standard sRGB profile with a D65 white point.
  public static let sRGB = try! Self(
    model: .rgb,
    rgbToXYZ: try! ColorMatrix3x3([
      0.4124564, 0.3575761, 0.1804375,
      0.2126729, 0.7151522, 0.0721750,
      0.0193339, 0.1191920, 0.9503041,
    ]),
    transferCurves: [.sRGB, .sRGB, .sRGB]
  )

  /// A linear one-component gray destination profile.
  public static let deviceGray = try! Self(model: .gray, transferCurves: [.linear])

  /// A linear four-component process-CMYK destination profile.
  public static let deviceCMYK = try! Self(
    model: .cmyk,
    transferCurves: [.linear, .linear, .linear, .linear]
  )
}
