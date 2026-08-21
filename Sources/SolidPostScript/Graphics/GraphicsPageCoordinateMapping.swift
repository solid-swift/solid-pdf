/// Exact conversion between PostScript default-user-space page points and device coordinates.
public struct GraphicsPageCoordinateMapping: Sendable, Hashable {
  /// The installed page's default matrix.
  public let pageToDevice: GraphicsMatrix
  /// The inverse default matrix, or `nil` for a singular installation-defined mapping.
  public let deviceToPage: GraphicsMatrix?
  /// The device media bounds expressed in default-user-space page coordinates, when invertible.
  public let mediaBounds: GraphicsRect?
  /// The device imageable bounds expressed in default-user-space page coordinates, when invertible.
  public let imageableBounds: GraphicsRect?

  /// Creates a page-coordinate mapping from a device descriptor.
  public init(device: GraphicsDeviceDescriptor) {
    pageToDevice = device.defaultMatrix
    deviceToPage = device.defaultMatrix.inverted
    mediaBounds = device.defaultMatrix.inverted.map { device.mediaBounds.transformedBounds(by: $0) }
    imageableBounds = device.defaultMatrix.inverted.map { device.imageableBounds.transformedBounds(by: $0) }
  }
}

extension GraphicsRect {
  func transformedBounds(by matrix: GraphicsMatrix) -> Self {
    Self.bounding([
      matrix.transform(GraphicsPoint(x: x, y: y)),
      matrix.transform(GraphicsPoint(x: maxX, y: y)),
      matrix.transform(GraphicsPoint(x: x, y: maxY)),
      matrix.transform(GraphicsPoint(x: maxX, y: maxY)),
    ])
  }
}
