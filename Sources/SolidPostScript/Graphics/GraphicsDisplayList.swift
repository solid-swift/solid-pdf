/// An immutable list of realized graphics effects captured without interpreter callbacks.
public struct GraphicsDisplayList: Sendable, Hashable {
  /// Effects in painting order.
  public let effects: [GraphicsEffect]

  /// Creates a display list.
  public init(effects: [GraphicsEffect]) {
    self.effects = effects
  }
}
