/// A closed range used to validate or clamp a color component.
public struct ColorComponentRange: Sendable, Hashable {
  /// The lower bound.
  public let lowerBound: Double
  /// The upper bound.
  public let upperBound: Double

  /// Creates a component range.
  public init(_ lowerBound: Double, _ upperBound: Double) throws(ColorError) {
    guard lowerBound.isFinite, upperBound.isFinite, lowerBound <= upperBound else {
      throw .invalidValue
    }
    self.lowerBound = lowerBound
    self.upperBound = upperBound
  }

  /// Returns `value` limited to this range.
  public func clamp(_ value: Double) -> Double { min(upperBound, max(lowerBound, value)) }
}
