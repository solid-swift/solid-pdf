import Foundation

/// One page transmitted by a recording graphics target.
public struct RecordedGraphicsPage: Sendable, Hashable {
  /// The graphics device used for the page.
  public let deviceDescriptor: GraphicsDeviceDescriptor
  /// The realized effects in painting order.
  public let effects: [GraphicsEffect]

  /// Creates a recorded page.
  public init(deviceDescriptor: GraphicsDeviceDescriptor, effects: [GraphicsEffect]) {
    self.deviceDescriptor = deviceDescriptor
    self.effects = effects
  }
}
