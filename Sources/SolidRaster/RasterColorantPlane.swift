import Foundation

/// An immutable gray8 device-colorant plane where 255 is maximum ink.
public struct RasterColorantPlane: Sendable, Hashable {
  public let name: String
  public let mask: RasterMask

  /// Creates a colorant plane.
  public init(name: String, mask: RasterMask) {
    self.name = name
    self.mask = mask
  }
}
