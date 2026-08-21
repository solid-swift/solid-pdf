import SolidPostScript
import SolidRaster

/// One immutable page delivered to a streaming raster sink.
public struct RasterRenderedPage: Sendable {
  public let image: RasterImage
  public let device: GraphicsDeviceSnapshot
  public let transmissionOrdinal: Int
  public let copyOrdinal: Int

  /// Creates a transferred page value.
  public init(
    image: RasterImage,
    device: GraphicsDeviceSnapshot,
    transmissionOrdinal: Int,
    copyOrdinal: Int
  ) {
    self.image = image
    self.device = device
    self.transmissionOrdinal = transmissionOrdinal
    self.copyOrdinal = copyOrdinal
  }
}
