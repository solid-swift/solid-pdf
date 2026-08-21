/// An immutable list of realized graphics effects captured without interpreter callbacks.
public struct GraphicsDisplayList: Sendable, Hashable {
  /// Identity shared by repeated references to this immutable display list.
  public let resourceIdentifier: GraphicsResourceIdentifier
  /// Effects in painting order.
  public let effects: [GraphicsEffect]

  /// Creates a display list.
  public init(
    effects: [GraphicsEffect],
    resourceIdentifier: GraphicsResourceIdentifier = .anonymous
  ) {
    self.resourceIdentifier = resourceIdentifier
    self.effects = effects
  }
}
