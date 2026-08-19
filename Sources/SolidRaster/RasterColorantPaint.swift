import Foundation

/// Subtractive colorant tints used by `RasterColorantCanvas`.
public struct RasterColorantPaint: Sendable, Hashable {
  public let tints: [String: Double]
  public let overprintsUnspecifiedColorants: Bool
  public let paintsNothing: Bool

  /// Creates a colorant paint.
  public init(
    tints: [String: Double],
    overprintsUnspecifiedColorants: Bool = false,
    paintsNothing: Bool = false
  ) {
    self.tints = tints.mapValues { min(1, max(0, $0)) }
    self.overprintsUnspecifiedColorants = overprintsUnspecifiedColorants
    self.paintsNothing = paintsNothing
  }
}
