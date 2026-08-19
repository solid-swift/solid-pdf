import Foundation

/// A colorant's role in raster trapping analysis.
public enum RasterTrappingColorantBehavior: Sendable, Hashable {
  case normal
  case transparent
  case opaque
  case opaqueIgnore
}

/// Placement used when trapping an image against another page object.
public enum RasterImageTrapPlacement: Sendable, Hashable {
  case normal
  case spread
  case choke
  case center
}

/// One device-space trapping zone, with later array elements taking precedence.
public struct RasterTrappingZone: Sendable, Hashable {
  public let path: RasterPath
  public let stepLimit: Double
  public let colorScaling: Double
  public let width: Double
  public let colorantStepLimits: [String: Double]
  public let colorantColorScales: [String: Double]

  /// Creates a raster trapping zone.
  public init(
    path: RasterPath,
    stepLimit: Double,
    colorScaling: Double,
    width: Double,
    colorantStepLimits: [String: Double] = [:],
    colorantColorScales: [String: Double] = [:]
  ) {
    self.path = path
    self.stepLimit = stepLimit
    self.colorScaling = colorScaling
    self.width = width
    self.colorantStepLimits = colorantStepLimits
    self.colorantColorScales = colorantColorScales
  }
}

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
  /// Placement used at image/object boundaries.
  public let imagePlacement: RasterImageTrapPlacement
  /// Device-pixel stride used for bounded image-internal analysis.
  public let imageAnalysisStride: Int
  /// Optical densities keyed by colorant name.
  public let neutralDensities: [String: Double]
  /// Boundary behavior keyed by colorant name.
  public let colorantBehaviors: [String: RasterTrappingColorantBehavior]
  /// Ordered page trapping zones.
  public let zones: [RasterTrappingZone]

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
    trapsInsideImages: Bool,
    imagePlacement: RasterImageTrapPlacement = .center,
    imageAnalysisStride: Int = 1,
    neutralDensities: [String: Double] = [:],
    colorantBehaviors: [String: RasterTrappingColorantBehavior] = [:],
    zones: [RasterTrappingZone] = []
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
    self.imagePlacement = imagePlacement
    self.imageAnalysisStride = max(1, imageAnalysisStride)
    self.neutralDensities = neutralDensities
    self.colorantBehaviors = colorantBehaviors
    self.zones = zones
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
    trapsInsideImages: false,
    imagePlacement: .center,
    imageAnalysisStride: 1,
    neutralDensities: [:],
    colorantBehaviors: [:],
    zones: []
  )
}
