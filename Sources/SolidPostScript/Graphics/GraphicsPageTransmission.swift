import Foundation

/// Complete delivery metadata for one logical PostScript page transmission.
public struct GraphicsPageTransmission: Sendable, Hashable {
  /// The trigger that requested transmission.
  public let trigger: GraphicsPageTransmissionTrigger
  /// The one-based logical transmission ordinal.
  public let logicalOrdinal: Int
  /// The effective number of requested copies.
  public let copies: Int
  /// The selected or deferred input medium.
  public let mediaSelection: GraphicsMediaSelection
  /// The physical placement for this page.
  public let placement: GraphicsPagePlacement
  /// The output delivery configuration.
  public let delivery: GraphicsPageDeliveryConfiguration

  /// Creates page-transmission metadata.
  public init(
    trigger: GraphicsPageTransmissionTrigger,
    logicalOrdinal: Int,
    copies: Int,
    mediaSelection: GraphicsMediaSelection = .virtual,
    placement: GraphicsPagePlacement = .simplex,
    delivery: GraphicsPageDeliveryConfiguration = .virtual
  ) {
    self.trigger = trigger
    self.logicalOrdinal = logicalOrdinal
    self.copies = copies
    self.mediaSelection = mediaSelection
    self.placement = placement
    self.delivery = delivery
  }
}
