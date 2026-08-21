import Foundation

/// Trapping features and limits advertised by an output device.
public struct GraphicsTrappingCapabilities: Sendable, Hashable {
  /// The supported trapping detail types.
  public let supportedTypes: Set<Int>
  /// Whether the target realizes traps in its physical output.
  public let realizesTraps: Bool
  /// The maximum number of page trapping zones.
  public let maximumZones: Int

  /// Creates trapping capabilities.
  public init(
    supportedTypes: Set<Int> = [],
    realizesTraps: Bool = false,
    maximumZones: Int = 0
  ) {
    self.supportedTypes = supportedTypes
    self.realizesTraps = realizesTraps
    self.maximumZones = max(0, maximumZones)
  }

  /// A device that does not support trapping.
  public static let unsupported = Self()
  /// A semantic target that preserves LanguageLevel 3 trapping state.
  public static let semanticType1001 = Self(supportedTypes: [1001], maximumZones: 10_000)
  /// The native separated-raster Type 1001 implementation.
  public static let rasterType1001 = Self(
    supportedTypes: [1001],
    realizesTraps: true,
    maximumZones: 10_000
  )
}
