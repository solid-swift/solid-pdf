import SolidPostScript

/// Explicit font providers available to one PDF graphics render.
public struct PDFGraphicsFontEnvironment: Sendable {
  /// Providers consulted after portable embedded-font resolution.
  public let providers: [any FontResourceProvider]

  /// Creates an explicit font environment.
  public init(providers: [any FontResourceProvider] = []) {
    self.providers = providers
  }

  /// Portable embedded-font handling without host discovery.
  public static let portable = Self()
}
