import Foundation
import SolidPostScript
import SolidRaster

/// One transmitted page with authoritative plates and a diagnostic composite preview.
public struct RasterSeparatedPage: Sendable, Hashable {
  public let device: GraphicsDeviceSnapshot
  public let plates: [RasterSeparationPlate]
  public let compositePreview: RasterImage

  /// Creates a separated page result.
  public init(
    device: GraphicsDeviceSnapshot,
    plates: [RasterSeparationPlate],
    compositePreview: RasterImage
  ) {
    self.device = device
    self.plates = plates
    self.compositePreview = compositePreview
  }
}
