import Foundation

/// Geometry and coordinate-system information supplied by a graphics target.
public struct GraphicsDeviceDescriptor: Sendable, Hashable {
  /// The complete page bounds in device space.
  public let mediaBounds: GraphicsRect
  /// The initially imageable page bounds in device space.
  public let imageableBounds: GraphicsRect
  /// The horizontal device resolution in dots per inch.
  public let horizontalResolution: Double
  /// The vertical device resolution in dots per inch.
  public let verticalResolution: Double
  /// The initial transformation from default user space to device space.
  public let defaultMatrix: GraphicsMatrix

  /// Creates a graphics device descriptor.
  public init(
    mediaBounds: GraphicsRect,
    imageableBounds: GraphicsRect,
    horizontalResolution: Double,
    verticalResolution: Double,
    defaultMatrix: GraphicsMatrix
  ) {
    self.mediaBounds = mediaBounds
    self.imageableBounds = imageableBounds
    self.horizontalResolution = horizontalResolution
    self.verticalResolution = verticalResolution
    self.defaultMatrix = defaultMatrix
  }

  /// The installation-default Letter page at 72 dots per inch.
  public static let letter = Self(
    mediaBounds: GraphicsRect(x: 0, y: 0, width: 612, height: 792),
    imageableBounds: GraphicsRect(x: 0, y: 0, width: 612, height: 792),
    horizontalResolution: 72,
    verticalResolution: 72,
    defaultMatrix: .identity
  )
}
