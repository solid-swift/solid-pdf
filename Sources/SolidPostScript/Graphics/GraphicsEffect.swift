import Foundation

/// A realized effect retained by a portable graphics recording.
public enum GraphicsEffect: Sendable, Hashable {
  /// A path-fill effect.
  case fill(path: GraphicsPath, rule: GraphicsFillRule, state: GraphicsStateSnapshot)
  /// A path-stroke effect.
  case stroke(path: GraphicsPath, state: GraphicsStateSnapshot)
  /// A page-erasure effect.
  case erase(state: GraphicsStateSnapshot)
}
