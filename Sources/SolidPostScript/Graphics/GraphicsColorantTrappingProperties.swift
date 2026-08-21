import Foundation

/// How one colorant participates in Type 1001 trapping decisions.
public enum GraphicsTrappingColorantType: String, Sendable, Hashable, CaseIterable {
  case normal = "Normal"
  case transparent = "Transparent"
  case opaque = "Opaque"
  case opaqueIgnore = "OpaqueIgnore"
}

/// Trapping properties associated with one process or named colorant.
public struct GraphicsColorantTrappingProperties: Sendable, Hashable {
  /// The PostScript colorant name.
  public let colorantName: String
  /// The colorant's boundary-analysis behavior.
  public let colorantType: GraphicsTrappingColorantType
  /// The colorant's optical neutral density.
  public let neutralDensity: Double

  /// Creates colorant trapping properties.
  public init(
    colorantName: String,
    colorantType: GraphicsTrappingColorantType = .normal,
    neutralDensity: Double
  ) {
    self.colorantName = colorantName
    self.colorantType = colorantType
    self.neutralDensity = neutralDensity
  }
}
