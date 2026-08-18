/// A color in the CIE L*a*b* color space.
public struct ColorLab: Sendable, Hashable {
  /// Perceptual lightness.
  public let lightness: Double
  /// The green-red opponent component.
  public let a: Double
  /// The blue-yellow opponent component.
  public let b: Double

  /// Creates a Lab color.
  public init(lightness: Double, a: Double, b: Double) {
    self.lightness = lightness
    self.a = a
    self.b = b
  }

  /// Converts the color to XYZ relative to `whitePoint`.
  public func xyz(whitePoint: ColorXYZ = .d65) -> ColorXYZ {
    let fy = (lightness + 16) / 116
    let fx = fy + a / 500
    let fz = fy - b / 200
    func inverse(_ value: Double) -> Double {
      let cube = value * value * value
      return cube > 216.0 / 24_389.0 ? cube : (116 * value - 16) / 903.3
    }
    return ColorXYZ(
      x: whitePoint.x * inverse(fx),
      y: whitePoint.y * inverse(fy),
      z: whitePoint.z * inverse(fz)
    )
  }
}
