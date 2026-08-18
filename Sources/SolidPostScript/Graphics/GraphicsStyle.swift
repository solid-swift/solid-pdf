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
  /// A DeviceRGB paint.
  case deviceRGB(red: Double, green: Double, blue: Double)
  /// A DeviceCMYK paint.
  case deviceCMYK(cyan: Double, magenta: Double, yellow: Double, black: Double)

  /// The equivalent DeviceGray component defined by the PLRM device-color conversions.
  public var grayComponent: Double {
    switch self {
    case .deviceGray(let gray):
      return gray
    case .deviceRGB(let red, let green, let blue):
      return 0.3 * red + 0.59 * green + 0.11 * blue
    case .deviceCMYK(let cyan, let magenta, let yellow, let black):
      return 1 - min(1, 0.3 * cyan + 0.59 * magenta + 0.11 * yellow + black)
    }
  }

  /// The equivalent DeviceRGB components defined by the PLRM device-color conversions.
  public var rgbComponents: (red: Double, green: Double, blue: Double) {
    switch self {
    case .deviceGray(let gray):
      return (gray, gray, gray)
    case .deviceRGB(let red, let green, let blue):
      return (red, green, blue)
    case .deviceCMYK(let cyan, let magenta, let yellow, let black):
      return (
        1 - min(1, cyan + black),
        1 - min(1, magenta + black),
        1 - min(1, yellow + black)
      )
    }
  }

  /// The equivalent nominal DeviceCMYK components.
  public var cmykComponents: (cyan: Double, magenta: Double, yellow: Double, black: Double) {
    switch self {
    case .deviceGray(let gray):
      return (0, 0, 0, 1 - gray)
    case .deviceRGB(let red, let green, let blue):
      let cyan = 1 - red
      let magenta = 1 - green
      let yellow = 1 - blue
      let black = min(cyan, magenta, yellow)
      return (cyan - black, magenta - black, yellow - black, black)
    case .deviceCMYK(let cyan, let magenta, let yellow, let black):
      return (cyan, magenta, yellow, black)
    }
  }
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
