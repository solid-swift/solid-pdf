import Foundation
import SolidRaster

package enum GraphicsPathGeometry {
  static func flattened(_ path: GraphicsPath, flatness: Double) throws -> GraphicsPath {
    do {
      return GraphicsPath(try RasterPathGeometry.flattened(path.rasterPath, flatness: flatness))
    } catch {
      throw error.postScriptError
    }
  }

  static func region(
    for path: GraphicsPath,
    rule: GraphicsFillRule,
    flatness: Double
  ) throws -> RasterRegion {
    do {
      return try RasterRegion.path(path.rasterPath, rule: rule.rasterFillRule, flatness: flatness)
    } catch {
      throw error.postScriptError
    }
  }

  static func intersect(_ lhs: RasterRegion, _ rhs: RasterRegion) throws -> RasterRegion {
    do {
      return try lhs.intersecting(rhs)
    } catch {
      throw error.postScriptError
    }
  }

  static func clippingPath(_ region: RasterRegion) throws -> GraphicsPath {
    do {
      return GraphicsPath(try region.path())
    } catch {
      throw error.postScriptError
    }
  }

  static func strokeOutline(
    path: GraphicsPath,
    state: GraphicsCanonicalState,
    matrix: GraphicsMatrix? = nil
  ) throws -> GraphicsPath {
    try strokeOutline(
      path: path,
      matrix: matrix ?? state.matrix,
      lineWidth: state.lineWidth,
      lineCap: state.lineCap,
      lineJoin: state.lineJoin,
      miterLimit: state.miterLimit,
      dash: state.dash,
      flatness: state.flatness,
      strokeAdjustment: state.strokeAdjustment
    )
  }

  package static func strokeOutline(
    path: GraphicsPath,
    state: GraphicsStateSnapshot,
    matrix: GraphicsMatrix? = nil
  ) throws -> GraphicsPath {
    try strokeOutline(
      path: path,
      matrix: matrix ?? state.matrix,
      lineWidth: state.lineWidth,
      lineCap: state.lineCap,
      lineJoin: state.lineJoin,
      miterLimit: state.miterLimit,
      dash: state.dash,
      flatness: state.flatness,
      strokeAdjustment: state.strokeAdjustment
    )
  }

  private static func strokeOutline(
    path: GraphicsPath,
    matrix strokeMatrix: GraphicsMatrix,
    lineWidth: Double,
    lineCap: GraphicsLineCap,
    lineJoin: GraphicsLineJoin,
    miterLimit: Double,
    dash: GraphicsDash,
    flatness: Double,
    strokeAdjustment: Bool
  ) throws -> GraphicsPath {
    guard let inverse = strokeMatrix.inverted else { return GraphicsPath() }
    var width = lineWidth
    if strokeAdjustment, width > 0 {
      let xScale = hypot(strokeMatrix.a, strokeMatrix.b)
      let yScale = hypot(strokeMatrix.c, strokeMatrix.d)
      let scale = max(xScale, yScale)
      if scale.isFinite, scale > 0 {
        width = max(1, (width * scale).rounded()) / scale
      }
    }
    let style = RasterStrokeStyle(
      width: width,
      cap: lineCap.rasterLineCap,
      join: lineJoin.rasterLineJoin,
      miterLimit: miterLimit,
      dash: dash.pattern,
      dashPhase: dash.phase
    )
    let strokeSpace = path.rasterPath.transformed(by: inverse.rasterTransform)
    do {
      let outline = try RasterPathGeometry.stroked(
        strokeSpace,
        style: style,
        transform: strokeMatrix.rasterTransform,
        flatness: flatness
      )
      return GraphicsPath(outline)
    } catch {
      throw error.postScriptError
    }
  }
}

extension GraphicsLineCap {
  fileprivate var rasterLineCap: RasterLineCap {
    switch self {
    case .butt: .butt
    case .round: .round
    case .square: .square
    }
  }
}

extension GraphicsLineJoin {
  fileprivate var rasterLineJoin: RasterLineJoin {
    switch self {
    case .miter: .miter
    case .round: .round
    case .bevel: .bevel
    }
  }
}
