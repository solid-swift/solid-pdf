/// One resolved vertex in a portable PostScript shading mesh.
public struct GraphicsShadingVertex: Sendable, Hashable {
  /// Device-space position.
  public let position: GraphicsPoint
  /// Portable color at the vertex.
  public let paint: GraphicsPaint

  /// Creates a shading vertex.
  public init(position: GraphicsPoint, paint: GraphicsPaint) {
    self.position = position
    self.paint = paint
  }
}

/// One ordered triangle in a portable PostScript shading mesh.
public struct GraphicsShadingTriangle: Sendable, Hashable {
  /// First vertex.
  public let first: GraphicsShadingVertex
  /// Second vertex.
  public let second: GraphicsShadingVertex
  /// Third vertex.
  public let third: GraphicsShadingVertex

  /// Creates a shading triangle.
  public init(
    first: GraphicsShadingVertex,
    second: GraphicsShadingVertex,
    third: GraphicsShadingVertex
  ) {
    self.first = first
    self.second = second
    self.third = third
  }
}

/// An immutable portable fallback mesh for a PostScript shading.
public struct GraphicsShadingMesh: Sendable, Hashable {
  /// Triangles in source painting order.
  public let triangles: [GraphicsShadingTriangle]

  /// Creates a shading mesh.
  public init(triangles: [GraphicsShadingTriangle]) {
    self.triangles = triangles
  }
}
