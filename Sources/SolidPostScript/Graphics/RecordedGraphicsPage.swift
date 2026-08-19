import Foundation

/// One page transmitted by a recording graphics target.
public struct RecordedGraphicsPage: Sendable, Hashable {
  /// The graphics device used for the page.
  public let deviceDescriptor: GraphicsDeviceDescriptor
  /// The realized effects in painting order.
  public let effects: [GraphicsEffect]
  /// The trapping zones and parameters active when the page was transmitted.
  public let trapping: GraphicsTrappingSnapshot

  /// Creates a recorded page.
  public init(
    deviceDescriptor: GraphicsDeviceDescriptor,
    effects: [GraphicsEffect],
    trapping: GraphicsTrappingSnapshot = .disabled
  ) {
    self.deviceDescriptor = deviceDescriptor
    self.effects = effects
    self.trapping = trapping
  }
}
