import Foundation

/// An immutable platform-neutral raster image with owned pixel storage.
public struct RasterImage: Sendable, Hashable {
  public let width: Int
  public let height: Int
  public let bytesPerRow: Int
  public let pixelFormat: RasterPixelFormat
  public let data: Data

  /// Creates an image after validating its storage dimensions.
  public init(
    width: Int,
    height: Int,
    bytesPerRow: Int,
    pixelFormat: RasterPixelFormat,
    data: Data
  ) throws(RasterError) {
    guard width >= 0,
      height >= 0,
      bytesPerRow >= width * 4,
      height == 0 || bytesPerRow <= Int.max / height,
      data.count == bytesPerRow * height
    else { throw .invalidImage }
    self.width = width
    self.height = height
    self.bytesPerRow = bytesPerRow
    self.pixelFormat = pixelFormat
    self.data = data
  }
}
