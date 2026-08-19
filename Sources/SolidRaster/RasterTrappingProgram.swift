import Foundation

/// Device-pixel trapping parameters compiled for one separated raster page.
public struct RasterTrappingProgram: Sendable, Hashable {
  /// Whether trap analysis and realization are enabled.
  public let enabled: Bool
  /// Trap width in device pixels.
  public let width: Double
  /// Relative component-change threshold.
  public let stepLimit: Double
  /// Requested trap-density scale.
  public let colorScaling: Double
  /// Density threshold used to identify black boundaries.
  public let blackDensityLimit: Double
  /// Maximum chromatic contribution in a black boundary.
  public let blackColorLimit: Double
  /// Multiplier applied to black trap widths.
  public let blackWidth: Double
  /// Density ratio at which centered traps begin sliding.
  public let slidingLimit: Double
  /// Whether image/object boundaries are trapped.
  public let trapsImagesToObjects: Bool
  /// Whether boundaries internal to images are trapped.
  public let trapsInsideImages: Bool

  /// Creates a raster trapping program.
  public init(
    enabled: Bool,
    width: Double,
    stepLimit: Double,
    colorScaling: Double,
    blackDensityLimit: Double,
    blackColorLimit: Double,
    blackWidth: Double,
    slidingLimit: Double,
    trapsImagesToObjects: Bool,
    trapsInsideImages: Bool
  ) {
    self.enabled = enabled
    self.width = width
    self.stepLimit = stepLimit
    self.colorScaling = colorScaling
    self.blackDensityLimit = blackDensityLimit
    self.blackColorLimit = blackColorLimit
    self.blackWidth = blackWidth
    self.slidingLimit = slidingLimit
    self.trapsImagesToObjects = trapsImagesToObjects
    self.trapsInsideImages = trapsInsideImages
  }

  /// A disabled program that allocates no trap-analysis storage.
  public static let disabled = Self(
    enabled: false,
    width: 0,
    stepLimit: 0.5,
    colorScaling: 1,
    blackDensityLimit: 1,
    blackColorLimit: 0.5,
    blackWidth: 1,
    slidingLimit: 1,
    trapsImagesToObjects: false,
    trapsInsideImages: false
  )
}
