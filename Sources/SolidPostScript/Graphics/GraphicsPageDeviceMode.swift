import Foundation

/// Determines whether a graphics target accepts page geometry requested by a PostScript program.
public enum GraphicsPageDeviceMode: Sendable, Hashable {
  /// Accept bounded page sizes and resolutions dynamically.
  case adaptive
  /// Accept bounded page-size changes while retaining the target's initial resolution.
  case adaptivePageSize
  /// Expose only the target's initial geometry.
  case fixed
}
