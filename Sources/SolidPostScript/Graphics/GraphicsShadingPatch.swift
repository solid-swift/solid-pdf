/// One reconstructed Coons or tensor-product patch in its source shading space.
public struct GraphicsShadingPatch: Sendable, Hashable {
  /// Shading type `6` for Coons patches or `7` for tensor-product patches.
  public let type: Int
  /// The original continuation flag in the encoded patch record.
  public let continuationFlag: Int
  /// Ordered boundary or tensor control points after continuation reconstruction.
  public let controlPoints: [GraphicsPoint]
  /// Four ordered corner-component arrays before function or color-space realization.
  public let cornerComponents: [[Double]]

  /// Creates one reconstructed shading patch.
  public init(
    type: Int,
    continuationFlag: Int,
    controlPoints: [GraphicsPoint],
    cornerComponents: [[Double]]
  ) {
    self.type = type
    self.continuationFlag = continuationFlag
    self.controlPoints = controlPoints
    self.cornerComponents = cornerComponents
  }
}
