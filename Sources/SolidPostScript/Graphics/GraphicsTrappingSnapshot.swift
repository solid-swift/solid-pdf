import Foundation

/// Immutable trapping state associated with one page-device snapshot.
public struct GraphicsTrappingSnapshot: Sendable, Hashable {
  /// Whether the page device requests in-RIP trapping.
  public let enabled: Bool
  /// Type-specific colorant details.
  public let details: GraphicsTrappingDetails
  /// Parameters used outside explicit zones.
  public let parameters: GraphicsTrappingParameters
  /// Ordered default and page-specific zones.
  public let zones: [GraphicsTrappingZone]

  /// Creates a trapping snapshot.
  public init(
    enabled: Bool = false,
    details: GraphicsTrappingDetails = GraphicsTrappingDetails(),
    parameters: GraphicsTrappingParameters = GraphicsTrappingParameters(),
    zones: [GraphicsTrappingZone] = []
  ) {
    self.enabled = enabled
    self.details = details
    self.parameters = parameters
    self.zones = zones
  }

  /// Disabled trapping with Type 1001 defaults.
  public static let disabled = Self()
}
