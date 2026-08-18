import Foundation

/// A portable six-component affine transformation.
public struct RasterAffineTransform: Sendable, Hashable {
  /// The horizontal scale component.
  public var a: Double
  /// The vertical shear component.
  public var b: Double
  /// The horizontal shear component.
  public var c: Double
  /// The vertical scale component.
  public var d: Double
  /// The horizontal translation.
  public var tx: Double
  /// The vertical translation.
  public var ty: Double

  /// Creates a transformation.
  public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
    self.a = a
    self.b = b
    self.c = c
    self.d = d
    self.tx = tx
    self.ty = ty
  }

  /// The identity transformation.
  public static let identity = Self(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

  /// Transforms a point.
  public func transform(_ point: RasterPoint) -> RasterPoint {
    RasterPoint(x: a * point.x + c * point.y + tx, y: b * point.x + d * point.y + ty)
  }

  /// Returns a transformation that applies this transformation followed by `other`.
  public func concatenated(with other: Self) -> Self {
    Self(
      a: other.a * a + other.c * b,
      b: other.b * a + other.d * b,
      c: other.a * c + other.c * d,
      d: other.b * c + other.d * d,
      tx: other.a * tx + other.c * ty + other.tx,
      ty: other.b * tx + other.d * ty + other.ty
    )
  }

  /// The inverse transformation, or `nil` if this transformation is singular.
  public var inverted: Self? {
    let determinant = a * d - b * c
    guard determinant.isFinite, determinant != 0 else { return nil }
    return Self(
      a: d / determinant,
      b: -b / determinant,
      c: -c / determinant,
      d: a / determinant,
      tx: (c * ty - d * tx) / determinant,
      ty: (b * tx - a * ty) / determinant
    )
  }
}
