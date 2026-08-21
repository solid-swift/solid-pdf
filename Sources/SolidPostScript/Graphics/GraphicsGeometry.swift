import Foundation

/// A point in the portable PostScript graphics coordinate space.
public struct GraphicsPoint: Sendable, Hashable {
  /// The horizontal coordinate.
  public var x: Double
  /// The vertical coordinate.
  public var y: Double

  /// Creates a point.
  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

/// A size in the portable PostScript graphics coordinate space.
public struct GraphicsSize: Sendable, Hashable {
  /// The horizontal extent.
  public var width: Double
  /// The vertical extent.
  public var height: Double

  /// Creates a size.
  public init(width: Double, height: Double) {
    self.width = width
    self.height = height
  }
}

/// A rectangle in the portable PostScript graphics coordinate space.
public struct GraphicsRect: Sendable, Hashable {
  /// The minimum horizontal coordinate.
  public var x: Double
  /// The minimum vertical coordinate.
  public var y: Double
  /// The rectangle width.
  public var width: Double
  /// The rectangle height.
  public var height: Double

  /// Creates a rectangle.
  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  /// The maximum horizontal coordinate.
  public var maxX: Double { x + width }
  /// The maximum vertical coordinate.
  public var maxY: Double { y + height }

  func contains(_ point: GraphicsPoint) -> Bool {
    point.x >= x && point.x <= maxX && point.y >= y && point.y <= maxY
  }
}

extension GraphicsRect {
  static func bounding(_ points: [GraphicsPoint]) -> Self {
    let minimumX = points.map(\.x).min() ?? 0
    let minimumY = points.map(\.y).min() ?? 0
    let maximumX = points.map(\.x).max() ?? minimumX
    let maximumY = points.map(\.y).max() ?? minimumY
    return Self(x: minimumX, y: minimumY, width: maximumX - minimumX, height: maximumY - minimumY)
  }
}

/// A six-component PostScript affine transformation matrix.
public struct GraphicsMatrix: Sendable, Hashable {
  /// The horizontal scale component.
  public var a: Double
  /// The vertical shear component.
  public var b: Double
  /// The horizontal shear component.
  public var c: Double
  /// The vertical scale component.
  public var d: Double
  /// The horizontal translation component.
  public var tx: Double
  /// The vertical translation component.
  public var ty: Double

  /// Creates a matrix from its PostScript components.
  public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
    self.a = a
    self.b = b
    self.c = c
    self.d = d
    self.tx = tx
    self.ty = ty
  }

  /// The identity matrix.
  public static let identity = Self(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

  /// Returns the point transformed by this matrix.
  public func transform(_ point: GraphicsPoint) -> GraphicsPoint {
    GraphicsPoint(
      x: a * point.x + c * point.y + tx,
      y: b * point.x + d * point.y + ty
    )
  }

  /// Returns the distance transformed by this matrix without translation.
  public func transformDistance(_ point: GraphicsPoint) -> GraphicsPoint {
    GraphicsPoint(x: a * point.x + c * point.y, y: b * point.x + d * point.y)
  }

  /// Returns a matrix that applies this matrix followed by `other`.
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

  /// Returns the inverse matrix, or `nil` when the matrix is singular.
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
