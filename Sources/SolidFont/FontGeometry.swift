import Foundation

/// A point in a font's design coordinate system.
public struct FontPoint: Sendable, Hashable {
  /// The horizontal coordinate.
  public let x: Double
  /// The vertical coordinate.
  public let y: Double

  /// Creates a font point.
  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

/// A rectangle in a font's design coordinate system.
public struct FontBounds: Sendable, Hashable {
  /// The minimum horizontal coordinate.
  public let minimumX: Double
  /// The minimum vertical coordinate.
  public let minimumY: Double
  /// The maximum horizontal coordinate.
  public let maximumX: Double
  /// The maximum vertical coordinate.
  public let maximumY: Double

  /// Creates a font bounding rectangle.
  public init(minimumX: Double, minimumY: Double, maximumX: Double, maximumY: Double) {
    self.minimumX = minimumX
    self.minimumY = minimumY
    self.maximumX = maximumX
    self.maximumY = maximumY
  }
}

/// A six-component affine transform in font coordinates.
public struct FontMatrix: Sendable, Hashable {
  /// The horizontal scale component.
  public let a: Double
  /// The vertical shear component.
  public let b: Double
  /// The horizontal shear component.
  public let c: Double
  /// The vertical scale component.
  public let d: Double
  /// The horizontal translation.
  public let tx: Double
  /// The vertical translation.
  public let ty: Double

  /// Creates a font transform.
  public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
    self.a = a
    self.b = b
    self.c = c
    self.d = d
    self.tx = tx
    self.ty = ty
  }

  /// The identity transform.
  public static let identity = Self(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)
}
