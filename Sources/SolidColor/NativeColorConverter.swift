/// Deterministic portable conversions into a destination profile.
public struct NativeColorConverter: Sendable {
  /// The destination profile.
  public let destination: ColorDestinationProfile

  /// Creates a converter.
  public init(destination: ColorDestinationProfile = .sRGB) {
    self.destination = destination
  }

  /// Converts XYZ to destination RGB, using the destination matrix and transfer curves.
  public func rgb(from xyz: ColorXYZ) throws(ColorError) -> ColorRGB {
    guard destination.model == .rgb, let inverse = destination.rgbToXYZ.inverted else {
      throw .componentCount
    }
    let linear = inverse.transform(xyz)
    let curves = destination.transferCurves.count == 1
      ? Array(repeating: destination.transferCurves[0], count: 3)
      : destination.transferCurves
    return try ColorRGB(
      red: curves[0].evaluate(linear.x),
      green: curves[1].evaluate(linear.y),
      blue: curves[2].evaluate(linear.z)
    ).clamped
  }
}
