import Foundation

/// The rule used to determine the interior of a path.
public enum RasterFillRule: Sendable, Hashable {
  case winding
  case evenOdd
}

/// The shape applied to open stroke ends.
public enum RasterLineCap: Sendable, Hashable {
  case butt
  case round
  case square
}

/// The shape applied at stroke joins.
public enum RasterLineJoin: Sendable, Hashable {
  case miter
  case round
  case bevel
}

/// Complete geometric stroke parameters.
public struct RasterStrokeStyle: Sendable, Hashable {
  public var width: Double
  public var cap: RasterLineCap
  public var join: RasterLineJoin
  public var miterLimit: Double
  public var dash: [Double]
  public var dashPhase: Double

  /// Creates a stroke style.
  public init(
    width: Double = 1,
    cap: RasterLineCap = .butt,
    join: RasterLineJoin = .miter,
    miterLimit: Double = 10,
    dash: [Double] = [],
    dashPhase: Double = 0
  ) {
    self.width = width
    self.cap = cap
    self.join = join
    self.miterLimit = miterLimit
    self.dash = dash
    self.dashPhase = dashPhase
  }
}

/// An RGBA color with normalized components.
public struct RasterColor: Sendable, Hashable {
  public var red: Double
  public var green: Double
  public var blue: Double
  public var alpha: Double

  /// Creates a color.
  public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  public static let white = Self(red: 1, green: 1, blue: 1)
  public static let black = Self(red: 0, green: 0, blue: 0)
}

/// A portable raster paint.
public enum RasterPaint: Sendable, Hashable {
  case solid(RasterColor)
}

/// The image sampling method.
public enum RasterInterpolation: Sendable, Hashable {
  case nearest
  case linear
}
