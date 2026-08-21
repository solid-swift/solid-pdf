/// An inclusive range of raw sampled-image component values.
public struct GraphicsImageSampleRange: Sendable, Hashable {
  /// The lowest matching raw sample value.
  public let lowerBound: UInt16
  /// The highest matching raw sample value.
  public let upperBound: UInt16

  /// Creates an inclusive raw sample range.
  public init(lowerBound: UInt16, upperBound: UInt16) {
    self.lowerBound = lowerBound
    self.upperBound = upperBound
  }

  /// Returns whether `sample` belongs to this range.
  public func contains(_ sample: UInt16) -> Bool {
    lowerBound...upperBound ~= sample
  }
}
