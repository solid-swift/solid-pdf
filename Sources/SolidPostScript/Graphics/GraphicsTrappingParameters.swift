import Foundation

/// Placement used for traps at image/object boundaries.
public enum GraphicsImageTrapPlacement: String, Sendable, Hashable, CaseIterable {
  case normal = "Normal"
  case spread = "Spread"
  case choke = "Choke"
  case center = "Center"
}

/// Per-colorant overrides in a trapping zone.
public struct GraphicsTrappingColorantZoneParameters: Sendable, Hashable {
  /// The relative component-change threshold.
  public let stepLimit: Double?
  /// The requested trap-density scale.
  public let trapColorScaling: Double?

  /// Creates per-colorant zone overrides.
  public init(stepLimit: Double? = nil, trapColorScaling: Double? = nil) {
    self.stepLimit = stepLimit
    self.trapColorScaling = trapColorScaling
  }
}

/// Portable values installed by `settrapparams`.
public struct GraphicsTrappingParameters: Sendable, Hashable {
  public let trapSetName: String?
  public let enabled: Bool
  public let stepLimit: Double
  public let trapWidth: Double
  public let trapColorScaling: Double
  public let blackDensityLimit: Double
  public let blackColorLimit: Double
  public let blackWidth: Double
  public let slidingTrapLimit: Double
  public let imageToObjectTrapping: Bool
  public let imageInternalTrapping: Bool
  public let imageTrapPlacement: GraphicsImageTrapPlacement
  public let imageResolution: Double
  public let colorantZoneDetails: [String: GraphicsTrappingColorantZoneParameters]

  /// Creates trapping parameters.
  public init(
    trapSetName: String? = nil,
    enabled: Bool = true,
    stepLimit: Double = 0.5,
    trapWidth: Double = 0.25,
    trapColorScaling: Double = 1,
    blackDensityLimit: Double = 1,
    blackColorLimit: Double = 0.5,
    blackWidth: Double = 1,
    slidingTrapLimit: Double = 1,
    imageToObjectTrapping: Bool = false,
    imageInternalTrapping: Bool = false,
    imageTrapPlacement: GraphicsImageTrapPlacement = .center,
    imageResolution: Double = 150,
    colorantZoneDetails: [String: GraphicsTrappingColorantZoneParameters] = [:]
  ) {
    self.trapSetName = trapSetName
    self.enabled = enabled
    self.stepLimit = stepLimit
    self.trapWidth = min(10, trapWidth)
    self.trapColorScaling = trapColorScaling
    self.blackDensityLimit = blackDensityLimit
    self.blackColorLimit = blackColorLimit
    self.blackWidth = blackWidth
    self.slidingTrapLimit = slidingTrapLimit
    self.imageToObjectTrapping = imageToObjectTrapping
    self.imageInternalTrapping = imageInternalTrapping
    self.imageTrapPlacement = imageTrapPlacement
    self.imageResolution = imageResolution
    self.colorantZoneDetails = colorantZoneDetails
  }
}
