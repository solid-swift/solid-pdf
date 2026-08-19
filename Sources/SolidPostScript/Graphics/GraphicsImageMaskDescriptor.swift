/// The semantic mask associated with a sampled image.
public enum GraphicsImageMaskDescriptor: Sendable, Hashable {
  /// An independently sampled explicit opacity mask.
  case explicit(
    width: Int,
    height: Int,
    maskToDevice: GraphicsMatrix,
    interpolate: Bool
  )
  /// Inclusive raw component ranges that make matching source samples transparent.
  case colorKey(ranges: [GraphicsImageSampleRange])
}
