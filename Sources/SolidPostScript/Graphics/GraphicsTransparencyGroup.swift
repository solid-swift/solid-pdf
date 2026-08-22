/// An immutable transparency group and its portable child effects.
public struct GraphicsTransparencyGroup: Sendable, Hashable {
  /// The group's device-space bounds.
  public let bounds: GraphicsRect
  /// Whether the group is composited against a transparent initial backdrop.
  public let isolated: Bool
  /// Whether each child object replaces earlier group objects within its shape.
  public let knockout: Bool
  /// The group's blending color space, when explicitly selected.
  public let colorSpace: GraphicsColorSpaceDescription?
  /// Portable realization data for the blending color space.
  public let colorRealization: GraphicsColorSpaceRealization?
  /// Child effects in painting order.
  public let displayList: GraphicsDisplayList
  /// Stable identity for the group during this render.
  public let resourceIdentifier: GraphicsResourceIdentifier

  /// Creates a transparency group.
  public init(
    bounds: GraphicsRect,
    isolated: Bool,
    knockout: Bool,
    colorSpace: GraphicsColorSpaceDescription? = nil,
    colorRealization: GraphicsColorSpaceRealization? = nil,
    displayList: GraphicsDisplayList,
    resourceIdentifier: GraphicsResourceIdentifier = .anonymous
  ) {
    self.bounds = bounds
    self.isolated = isolated
    self.knockout = knockout
    self.colorSpace = colorSpace
    self.colorRealization = colorRealization
    self.displayList = displayList
    self.resourceIdentifier = resourceIdentifier
  }
}
