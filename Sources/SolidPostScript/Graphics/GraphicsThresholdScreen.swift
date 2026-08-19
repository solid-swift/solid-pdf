import Foundation

/// A rectangular threshold screen in absolute device-pixel coordinates.
public struct GraphicsThresholdScreen: Sendable, Hashable {
  public let width: Int
  public let height: Int
  public let bitsPerSample: Int
  public let thresholds: [UInt16]

  /// Creates a threshold screen.
  public init(width: Int, height: Int, bitsPerSample: Int = 8, thresholds: [UInt16]) throws {
    let count = width.multipliedReportingOverflow(by: height)
    guard width > 0, height > 0, bitsPerSample == 8 || bitsPerSample == 16,
      !count.overflow, count.partialValue == thresholds.count
    else { throw Error.rangeCheck }
    self.width = width
    self.height = height
    self.bitsPerSample = bitsPerSample
    self.thresholds = thresholds.map { max(1, $0) }
  }
}
