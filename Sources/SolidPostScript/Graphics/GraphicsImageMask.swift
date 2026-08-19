/// A materialized sampled-image mask retained by a recording target.
public struct GraphicsImageMask: Sendable, Hashable {
  /// The semantic mask metadata.
  public let descriptor: GraphicsImageMaskDescriptor
  /// Row-major opacity values, where 1 paints and 0 is transparent.
  public let opacities: [Float]

  /// Creates a materialized image mask.
  public init(descriptor: GraphicsImageMaskDescriptor, opacities: [Float]) {
    self.descriptor = descriptor
    self.opacities = opacities
  }
}
