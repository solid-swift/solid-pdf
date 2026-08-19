import Foundation

/// An immutable platform-neutral 8-bit opacity mask.
public struct RasterMask: Sendable, Hashable {
  /// The number of mask columns.
  public let width: Int
  /// The number of mask rows.
  public let height: Int
  /// The byte stride between consecutive rows.
  public let bytesPerRow: Int
  /// Gray8 opacity samples, where 255 paints and 0 is transparent.
  public let data: Data

  /// Creates a mask after validating its storage dimensions.
  public init(width: Int, height: Int, bytesPerRow: Int, data: Data) throws(RasterError) {
    guard width >= 0,
      height >= 0,
      bytesPerRow >= width,
      height == 0 || bytesPerRow <= Int.max / height,
      data.count == bytesPerRow * height,
      data.count <= RasterLimits.default.maximumSurfaceBytes
    else { throw .invalidImage }
    self.width = width
    self.height = height
    self.bytesPerRow = bytesPerRow
    self.data = data
  }
}
