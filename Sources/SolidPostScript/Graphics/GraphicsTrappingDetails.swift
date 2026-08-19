import Foundation

/// Type-specific trapping information installed in a page device.
public struct GraphicsTrappingDetails: Sendable, Hashable {
  /// The trapping implementation type.
  public let type: Int
  /// The ordered colorants used for trapping analysis.
  public let trappingOrder: [String]
  /// Per-colorant trapping behavior keyed by colorant name.
  public let colorantDetails: [String: GraphicsColorantTrappingProperties]

  /// Creates trapping details.
  public init(
    type: Int = 1001,
    trappingOrder: [String] = [],
    colorantDetails: [String: GraphicsColorantTrappingProperties] = [:]
  ) {
    self.type = type
    self.trappingOrder = trappingOrder
    self.colorantDetails = colorantDetails
  }
}
