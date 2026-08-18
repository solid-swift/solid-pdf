import Foundation

/// One ordered clipping-path intersection.
public struct RasterClipConstraint: Sendable, Hashable {
  public let path: RasterPath
  public let rule: RasterFillRule

  /// Creates a clipping constraint.
  public init(path: RasterPath, rule: RasterFillRule) {
    self.path = path
    self.rule = rule
  }
}

/// An imageable boundary and its ordered clipping intersections.
public struct RasterClip: Sendable, Hashable {
  public let imageableBounds: RasterRect
  public let constraints: [RasterClipConstraint]

  /// Creates a clip.
  public init(imageableBounds: RasterRect, constraints: [RasterClipConstraint] = []) {
    self.imageableBounds = imageableBounds
    self.constraints = constraints
  }
}
