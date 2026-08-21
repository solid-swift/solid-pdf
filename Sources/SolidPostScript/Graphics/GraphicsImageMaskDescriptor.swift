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

  /// Returns this mask with any device-space geometry followed by `matrix`.
  public func transformed(by matrix: GraphicsMatrix) -> Self {
    switch self {
    case .explicit(let width, let height, let maskToDevice, let interpolate):
      return .explicit(
        width: width,
        height: height,
        maskToDevice: maskToDevice.concatenated(with: matrix),
        interpolate: interpolate
      )
    case .colorKey:
      return self
    }
  }
}
