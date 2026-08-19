/// Deterministic portable conversions into a destination profile.
public struct NativeColorConverter: Sendable {
  /// The destination profile.
  public let destination: ColorDestinationProfile

  /// Creates a converter.
  public init(destination: ColorDestinationProfile = .sRGB) {
    self.destination = destination
  }

  /// Converts XYZ into the destination profile's ordered process components.
  public func components(from xyz: ColorXYZ) throws(ColorError) -> [Double] {
    switch destination.model {
    case .gray:
      return [try gray(from: xyz)]
    case .rgb:
      let value = try rgb(from: xyz)
      return [value.red, value.green, value.blue]
    case .cmyk:
      let value = try cmyk(from: xyz)
      return [value.cyan, value.magenta, value.yellow, value.black]
    }
  }

  /// Converts XYZ to a one-component destination gray value.
  public func gray(from xyz: ColorXYZ) throws(ColorError) -> Double {
    guard destination.model == .gray else { throw .componentCount }
    let linear = xyz.y / destination.whitePoint.y
    return try destination.transferCurves[0].evaluate(linear).clampedUnit
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

  /// Converts XYZ to nominal destination process-CMYK components.
  public func cmyk(from xyz: ColorXYZ) throws(ColorError) -> ColorCMYK {
    guard destination.model == .cmyk else { throw .componentCount }
    let rgb = try Self.sRGBConverter.rgb(from: xyz)
    let unadjusted = [1 - rgb.red, 1 - rgb.green, 1 - rgb.blue]
    let black = unadjusted.min() ?? 0
    let linear = [unadjusted[0] - black, unadjusted[1] - black, unadjusted[2] - black, black]
    let curves = destination.transferCurves.count == 1
      ? Array(repeating: destination.transferCurves[0], count: 4)
      : destination.transferCurves
    var encoded: [Double] = []
    encoded.reserveCapacity(4)
    for (value, curve) in zip(linear, curves) {
      encoded.append(try curve.evaluate(value).clampedUnit)
    }
    return ColorCMYK(
      cyan: encoded[0],
      magenta: encoded[1],
      yellow: encoded[2],
      black: encoded[3]
    )
  }

  private static let sRGBConverter = Self(destination: .sRGB)
}
