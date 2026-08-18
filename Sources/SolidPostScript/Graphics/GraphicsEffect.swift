import Foundation

/// A realized effect retained by a portable graphics recording.
public enum GraphicsEffect: Sendable, Hashable {
  /// A path-fill effect.
  case fill(path: GraphicsPath, rule: GraphicsFillRule, state: GraphicsStateSnapshot)
  /// A path-stroke effect.
  case stroke(path: GraphicsPath, state: GraphicsStateSnapshot)
  /// A page-erasure effect.
  case erase(state: GraphicsStateSnapshot)
  /// A batched rectangle-fill effect.
  case fillRectangles(paths: [GraphicsPath], state: GraphicsStateSnapshot)
  /// A batched rectangle-stroke effect.
  case strokeRectangles(paths: [GraphicsPath], matrix: GraphicsMatrix?, state: GraphicsStateSnapshot)
  /// A sampled-image effect.
  case image(GraphicsImage, state: GraphicsStateSnapshot)
}
