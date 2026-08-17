import Foundation

/// The rule used to determine the inside of a path.
public enum GraphicsFillRule: Sendable, Hashable {
  /// The nonzero winding-number rule.
  case winding
  /// The even-odd rule.
  case evenOdd
}

/// The shape used at the ends of open stroked subpaths.
public enum GraphicsLineCap: Int32, Sendable, Hashable {
  /// A square end at the endpoint.
  case butt = 0
  /// A semicircular end centered on the endpoint.
  case round = 1
  /// A square end extending half the line width.
  case square = 2
}

/// The shape used where stroked line segments meet.
public enum GraphicsLineJoin: Int32, Sendable, Hashable {
  /// A mitered join.
  case miter = 0
  /// A rounded join.
  case round = 1
  /// A beveled join.
  case bevel = 2
}

/// A PostScript line-dash pattern.
public struct GraphicsDash: Sendable, Hashable {
  /// Alternating on and off lengths in user-space units.
  public var pattern: [Double]
  /// The initial offset into the pattern.
  public var phase: Double

  /// Creates a dash pattern.
  public init(pattern: [Double] = [], phase: Double = 0) {
    self.pattern = pattern
    self.phase = phase
  }
}

/// A portable paint value.
public enum GraphicsPaint: Sendable, Hashable {
  /// A DeviceGray paint, where zero is black and one is white.
  case deviceGray(Double)
}

/// One clipping-path intersection.
public struct GraphicsClipConstraint: Sendable, Hashable {
  /// The path to intersect with the prior clipping region.
  public let path: GraphicsPath
  /// The fill rule used for the intersection.
  public let rule: GraphicsFillRule

  /// Creates a clipping constraint.
  public init(path: GraphicsPath, rule: GraphicsFillRule) {
    self.path = path
    self.rule = rule
  }
}

/// An ordered, exactly replayable PostScript clipping region.
public struct GraphicsClip: Sendable, Hashable {
  /// The device's initial imageable boundary.
  public let imageableBounds: GraphicsRect
  /// Additional intersections in application order.
  public let constraints: [GraphicsClipConstraint]

  /// Creates a clipping region.
  public init(imageableBounds: GraphicsRect, constraints: [GraphicsClipConstraint] = []) {
    self.imageableBounds = imageableBounds
    self.constraints = constraints
  }

  func appending(_ constraint: GraphicsClipConstraint) throws -> Self {
    guard constraints.count < LanguageLimits.maximumClipConstraints else { throw Error.limitCheck }
    return Self(imageableBounds: imageableBounds, constraints: constraints + [constraint])
  }
}
