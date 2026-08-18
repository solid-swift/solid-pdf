/// A color in the CIE 1931 XYZ profile-connection space.
public struct ColorXYZ: Sendable, Hashable {
  /// The X tristimulus component.
  public let x: Double
  /// The Y tristimulus component.
  public let y: Double
  /// The Z tristimulus component.
  public let z: Double

  /// Creates an XYZ color.
  public init(x: Double, y: Double, z: Double) {
    self.x = x
    self.y = y
    self.z = z
  }

  /// The CIE D65 reference white normalized to Y equal to one.
  public static let d65 = Self(x: 0.95047, y: 1, z: 1.08883)
}
