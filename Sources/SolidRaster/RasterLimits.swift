import Foundation

/// Resource limits applied by the rasterizer before allocating storage.
public struct RasterLimits: Sendable, Hashable {
  public var maximumSurfaceBytes: Int
  public var maximumScratchBytes: Int
  public var maximumPathElements: Int
  public var maximumClipConstraints: Int

  /// Creates raster resource limits.
  public init(
    maximumSurfaceBytes: Int = 512 * 1_024 * 1_024,
    maximumScratchBytes: Int = 64 * 1_024 * 1_024,
    maximumPathElements: Int = 1_000_000,
    maximumClipConstraints: Int = 10_000
  ) {
    self.maximumSurfaceBytes = maximumSurfaceBytes
    self.maximumScratchBytes = maximumScratchBytes
    self.maximumPathElements = maximumPathElements
    self.maximumClipConstraints = maximumClipConstraints
  }

  /// Standard limits suitable for general document rendering.
  public static let `default` = Self()
}
