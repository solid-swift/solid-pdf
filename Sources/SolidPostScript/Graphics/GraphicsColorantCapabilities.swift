import Foundation

/// Colorant-output capabilities advertised by a page-device provider.
public struct GraphicsColorantCapabilities: Sendable, Hashable {
  public let supportedProcessModels: Set<GraphicsProcessColorModel>
  public let supportsCompositeOutput: Bool
  public let supportsSeparationOutput: Bool
  public let supportsOverprint: Bool
  public let acceptsDynamicColorants: Bool
  public let maximumSeparations: Int

  /// Creates colorant-output capabilities.
  public init(
    supportedProcessModels: Set<GraphicsProcessColorModel> = [.deviceRGB],
    supportsCompositeOutput: Bool = true,
    supportsSeparationOutput: Bool = false,
    supportsOverprint: Bool = false,
    acceptsDynamicColorants: Bool = false,
    maximumSeparations: Int = 1
  ) {
    self.supportedProcessModels = supportedProcessModels
    self.supportsCompositeOutput = supportsCompositeOutput
    self.supportsSeparationOutput = supportsSeparationOutput
    self.supportsOverprint = supportsOverprint
    self.acceptsDynamicColorants = acceptsDynamicColorants
    self.maximumSeparations = min(250, max(1, maximumSeparations))
  }

  /// Compatibility capabilities for an RGB composite target.
  public static let compositeRGB = Self()

  /// Semantic capabilities for targets that preserve colorants without physical plate output.
  public static let semantic = Self(
    supportedProcessModels: Set(GraphicsProcessColorModel.allCases),
    supportsCompositeOutput: true,
    supportsSeparationOutput: true,
    supportsOverprint: true,
    acceptsDynamicColorants: true,
    maximumSeparations: 250
  )
}
