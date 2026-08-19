import Foundation

/// A gradient vertex carrying subtractive device-colorant tints.
public struct RasterColorantGradientVertex: Sendable, Hashable {
  public let position: RasterPoint
  public let paint: RasterColorantPaint

  /// Creates a colorant gradient vertex.
  public init(position: RasterPoint, paint: RasterColorantPaint) {
    self.position = position
    self.paint = paint
  }
}

/// One colorant-interpolated gradient triangle.
public struct RasterColorantGradientTriangle: Sendable, Hashable {
  public let first: RasterColorantGradientVertex
  public let second: RasterColorantGradientVertex
  public let third: RasterColorantGradientVertex

  /// Creates a colorant gradient triangle.
  public init(
    first: RasterColorantGradientVertex,
    second: RasterColorantGradientVertex,
    third: RasterColorantGradientVertex
  ) {
    self.first = first
    self.second = second
    self.third = third
  }
}

/// An ordered mesh of colorant-interpolated triangles.
public struct RasterColorantGradientMesh: Sendable, Hashable {
  public let triangles: [RasterColorantGradientTriangle]

  /// Creates a colorant gradient mesh.
  public init(triangles: [RasterColorantGradientTriangle]) {
    self.triangles = triangles
  }
}
