/// A vertex in a portable color-interpolated gradient mesh.
public struct RasterGradientVertex: Sendable, Hashable {
  /// The device-space position.
  public let position: RasterPoint
  /// The normalized premultiplied interpolation color.
  public let color: RasterColor

  /// Creates a gradient vertex.
  public init(position: RasterPoint, color: RasterColor) {
    self.position = position
    self.color = color
  }
}

/// One ordered triangle in a gradient mesh.
public struct RasterGradientTriangle: Sendable, Hashable {
  /// The first vertex.
  public let first: RasterGradientVertex
  /// The second vertex.
  public let second: RasterGradientVertex
  /// The third vertex.
  public let third: RasterGradientVertex

  /// Creates a gradient triangle.
  public init(
    first: RasterGradientVertex,
    second: RasterGradientVertex,
    third: RasterGradientVertex
  ) {
    self.first = first
    self.second = second
    self.third = third
  }
}

/// An immutable ordered gradient mesh.
public struct RasterGradientMesh: Sendable, Hashable {
  /// Triangles in painting order.
  public let triangles: [RasterGradientTriangle]

  /// Creates a gradient mesh.
  public init(triangles: [RasterGradientTriangle]) {
    self.triangles = triangles
  }
}
