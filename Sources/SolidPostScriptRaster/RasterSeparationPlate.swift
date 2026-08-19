import Foundation
import SolidRaster

/// One authoritative monochrome colorant plate.
public struct RasterSeparationPlate: Sendable, Hashable {
  public let colorant: String
  public let tint: RasterMask

  /// Creates a colorant plate.
  public init(colorant: String, tint: RasterMask) {
    self.colorant = colorant
    self.tint = tint
  }
}
