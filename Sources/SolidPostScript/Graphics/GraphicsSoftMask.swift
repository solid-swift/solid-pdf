/// The channel extracted from a soft-mask transparency group.
public enum GraphicsSoftMaskSubtype: Sendable, Hashable {
  case alpha
  case luminosity
}

/// An immutable soft-mask program captured without PDF or PostScript objects.
public struct GraphicsSoftMask: Sendable, Hashable {
  /// The group channel used as the mask value.
  public let subtype: GraphicsSoftMaskSubtype
  /// The transparency group that produces the mask.
  public let group: GraphicsTransparencyGroup
  /// The group color-space backdrop components.
  public let backdrop: [Double]
  /// An optional one-input transfer function applied to mask values.
  public let transferFunction: GraphicsComponentFunction?
  /// Stable identity for the mask resource during this render.
  public let resourceIdentifier: GraphicsResourceIdentifier

  /// Creates a soft-mask program.
  public init(
    subtype: GraphicsSoftMaskSubtype,
    group: GraphicsTransparencyGroup,
    backdrop: [Double] = [],
    transferFunction: GraphicsComponentFunction? = nil,
    resourceIdentifier: GraphicsResourceIdentifier = .anonymous
  ) {
    self.subtype = subtype
    self.group = group
    self.backdrop = backdrop
    self.transferFunction = transferFunction
    self.resourceIdentifier = resourceIdentifier
  }
}
