import Foundation

/// Resource limits enforced while building a portable physical print spool.
public struct GraphicsPrintSpoolLimits: Sendable, Hashable {
  /// Maximum number of captured logical pages.
  public let maximumLogicalPages: Int
  /// Maximum number of delivered side records.
  public let maximumDeliveredSides: Int
  /// Maximum estimated bytes retained by captured page effects.
  public let maximumPlanningBytes: Int

  /// Creates print-spool limits.
  public init(
    maximumLogicalPages: Int = 65_536,
    maximumDeliveredSides: Int = 1_000_000,
    maximumPlanningBytes: Int = 512 * 1_024 * 1_024
  ) {
    self.maximumLogicalPages = maximumLogicalPages
    self.maximumDeliveredSides = maximumDeliveredSides
    self.maximumPlanningBytes = maximumPlanningBytes
  }
}
