import Foundation

/// A fully merged request presented to a page-device provider for negotiation.
public struct GraphicsPageDeviceRequest: Sendable, Hashable {
  /// The requested medium size in default-user-space points.
  public let pageSize: GraphicsSize
  /// The requested horizontal and vertical resolution in pixels per inch.
  public let resolution: GraphicsSize
  /// The optional asserted imaging bounds in default user space.
  public let imagingBoundingBox: GraphicsRect?
  /// The requested copy count, or `nil` to use `#copies`.
  public let numberOfCopies: Int?

  /// Creates a page-device request.
  public init(
    pageSize: GraphicsSize,
    resolution: GraphicsSize,
    imagingBoundingBox: GraphicsRect?,
    numberOfCopies: Int?
  ) {
    self.pageSize = pageSize
    self.resolution = resolution
    self.imagingBoundingBox = imagingBoundingBox
    self.numberOfCopies = numberOfCopies
  }
}
