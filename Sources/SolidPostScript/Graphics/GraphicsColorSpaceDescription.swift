import SolidColor

/// A portable description of the color space associated with a graphics value.
public indirect enum GraphicsColorSpaceDescription: Sendable, Hashable {
  /// Device-dependent grayscale.
  case deviceGray
  /// Device-dependent additive RGB.
  case deviceRGB
  /// Device-dependent subtractive CMYK.
  case deviceCMYK
  /// A one-component CIE-based space.
  case cieBasedA(whitePoint: ColorXYZ)
  /// A three-component CIE-based space.
  case cieBasedABC(whitePoint: ColorXYZ)
  /// A LanguageLevel 3 three-component pre-extension.
  case cieBasedDEF(whitePoint: ColorXYZ)
  /// A LanguageLevel 3 four-component pre-extension.
  case cieBasedDEFG(whitePoint: ColorXYZ)
  /// A table-indexed base color space.
  case indexed(base: Self, maximumIndex: Int)
  /// A single named colorant with an alternative space.
  case separation(name: String, alternative: Self)
  /// Multiple named colorants with an alternative space.
  case deviceN(names: [String], alternative: Self)
  /// A Pattern space, optionally carrying the base space of uncolored tiling patterns.
  case pattern(underlying: Self?)

  /// The number of source components accepted by the space.
  public var componentCount: Int {
    switch self {
    case .deviceGray, .cieBasedA, .indexed, .separation: 1
    case .deviceRGB, .cieBasedABC, .cieBasedDEF: 3
    case .deviceCMYK, .cieBasedDEFG: 4
    case .deviceN(let names, _): names.count
    case .pattern(let underlying): (underlying?.componentCount ?? 0) + 1
    }
  }
}
