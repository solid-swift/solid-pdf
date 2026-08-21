import Foundation
import SolidPostScript
import SolidRaster

extension GraphicsMatrix {
  var raster: RasterAffineTransform { .init(a: a, b: b, c: c, d: d, tx: tx, ty: ty) }
}

extension GraphicsPoint {
  var raster: RasterPoint { RasterPoint(x: x, y: y) }
}

extension GraphicsRect {
  var raster: RasterRect { .init(x: x, y: y, width: width, height: height) }
}

extension GraphicsPath {
  var rasterPath: RasterPath {
    RasterPath(elements: elements.map { element in
      switch element {
      case .move(let point): .move(to: RasterPoint(x: point.x, y: point.y))
      case .line(let point): .line(to: RasterPoint(x: point.x, y: point.y))
      case .curve(let control1, let control2, let end):
        .cubic(
          control1: RasterPoint(x: control1.x, y: control1.y),
          control2: RasterPoint(x: control2.x, y: control2.y),
          end: RasterPoint(x: end.x, y: end.y)
        )
      case .close: .close
      }
    })
  }

  static func rectangle(_ rect: GraphicsRect) -> Self {
    Self(elements: [
      .move(to: GraphicsPoint(x: rect.x, y: rect.y)),
      .line(to: GraphicsPoint(x: rect.maxX, y: rect.y)),
      .line(to: GraphicsPoint(x: rect.maxX, y: rect.maxY)),
      .line(to: GraphicsPoint(x: rect.x, y: rect.maxY)),
      .close,
    ])
  }

  func transformed(by matrix: GraphicsMatrix) -> Self {
    Self(elements: elements.map { element in
      switch element {
      case .move(let point): .move(to: matrix.transform(point))
      case .line(let point): .line(to: matrix.transform(point))
      case .curve(let control1, let control2, let end):
        .curve(
          control1: matrix.transform(control1),
          control2: matrix.transform(control2),
          end: matrix.transform(end)
        )
      case .close: .close
      }
    })
  }
}

extension GraphicsFillRule {
  var raster: RasterFillRule { self == .winding ? .winding : .evenOdd }
}

extension GraphicsLineCap {
  var raster: RasterLineCap {
    switch self {
    case .butt: .butt
    case .round: .round
    case .square: .square
    }
  }
}

extension GraphicsLineJoin {
  var raster: RasterLineJoin {
    switch self {
    case .miter: .miter
    case .round: .round
    case .bevel: .bevel
    }
  }
}
