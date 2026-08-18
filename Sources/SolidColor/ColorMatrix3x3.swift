/// A row-major three-by-three color transformation matrix.
public struct ColorMatrix3x3: Sendable, Hashable {
  /// The nine row-major coefficients.
  public let values: [Double]

  /// Creates a matrix from exactly nine finite coefficients.
  public init(_ values: [Double]) throws(ColorError) {
    guard values.count == 9, values.allSatisfy(\.isFinite) else { throw .invalidValue }
    self.values = values
  }

  /// The identity color transformation.
  public static let identity = try! Self([1, 0, 0, 0, 1, 0, 0, 0, 1])

  /// Applies the matrix to an XYZ-sized vector.
  public func transform(_ value: ColorXYZ) -> ColorXYZ {
    ColorXYZ(
      x: values[0] * value.x + values[1] * value.y + values[2] * value.z,
      y: values[3] * value.x + values[4] * value.y + values[5] * value.z,
      z: values[6] * value.x + values[7] * value.y + values[8] * value.z
    )
  }

  /// Returns the inverse matrix.
  public var inverted: Self? {
    let a = values[0], b = values[1], c = values[2]
    let d = values[3], e = values[4], f = values[5]
    let g = values[6], h = values[7], i = values[8]
    let determinant = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    guard determinant.isFinite, abs(determinant) > Double.ulpOfOne else { return nil }
    return try? Self([
      (e * i - f * h) / determinant,
      (c * h - b * i) / determinant,
      (b * f - c * e) / determinant,
      (f * g - d * i) / determinant,
      (a * i - c * g) / determinant,
      (c * d - a * f) / determinant,
      (d * h - e * g) / determinant,
      (b * g - a * h) / determinant,
      (a * e - b * d) / determinant,
    ])
  }
}
