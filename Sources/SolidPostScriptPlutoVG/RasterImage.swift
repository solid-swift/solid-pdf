import Foundation

/// An immutable, platform-neutral raster image with owned pixel storage.
public struct RasterImage: Sendable, Hashable {
  /// The image width in pixels.
  public let width: Int
  /// The image height in pixels.
  public let height: Int
  /// The number of bytes between successive top-left-origin rows.
  public let bytesPerRow: Int
  /// The organization of the pixel components.
  public let pixelFormat: RasterPixelFormat
  /// Pixel bytes beginning with the top-left row.
  public let data: Data

  init(
    width: Int,
    height: Int,
    bytesPerRow: Int,
    pixelFormat: RasterPixelFormat,
    data: Data
  ) {
    self.width = width
    self.height = height
    self.bytesPerRow = bytesPerRow
    self.pixelFormat = pixelFormat
    self.data = data
  }
}
