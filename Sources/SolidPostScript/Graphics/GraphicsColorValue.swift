import SolidColor

/// A validated target-independent color value.
public indirect enum GraphicsColorValue: Sendable, Hashable {
  /// A DeviceGray value.
  case deviceGray(Double)
  /// A DeviceRGB value.
  case deviceRGB(ColorRGB)
  /// A DeviceCMYK value.
  case deviceCMYK(ColorCMYK)
  /// A color resolved into the CIE XYZ profile-connection space.
  case cie(
    space: GraphicsColorSpaceDescription,
    source: [Double],
    xyz: ColorXYZ,
    device: Self?
  )
  /// Named colorants and their tints with a fully evaluated alternative value.
  case named(
    space: GraphicsColorSpaceDescription,
    colorants: [String],
    tints: [Double],
    alternative: Self
  )
  /// Colorants selected directly on the active device without evaluating an alternative transform.
  case directColorants(
    space: GraphicsColorSpaceDescription,
    colorants: [String],
    tints: [Double]
  )

  /// A nominal RGB fallback for bitmap devices without native named-color support.
  public var rgb: ColorRGB {
    switch self {
    case .deviceGray(let gray):
      return ColorRGB(red: gray, green: gray, blue: gray).clamped
    case .deviceRGB(let value):
      return value.clamped
    case .deviceCMYK(let value):
      return value.rgb.clamped
    case .cie(_, _, let xyz, let device):
      return device?.rgb
        ?? (try? NativeColorConverter().rgb(from: xyz))
        ?? ColorRGB(red: 0, green: 0, blue: 0)
    case .named(_, _, _, let alternative):
      return alternative.rgb
    case .directColorants:
      return ColorRGB(red: 0, green: 0, blue: 0)
    }
  }
}
