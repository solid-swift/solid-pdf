import SolidRaster

extension GraphicsPoint {
  var rasterPoint: RasterPoint { RasterPoint(x: x, y: y) }
}

extension GraphicsRect {
  var rasterRect: RasterRect { RasterRect(x: x, y: y, width: width, height: height) }
}

extension GraphicsMatrix {
  var rasterTransform: RasterAffineTransform {
    RasterAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
  }
}

extension GraphicsFillRule {
  var rasterFillRule: RasterFillRule {
    switch self {
    case .winding: .winding
    case .evenOdd: .evenOdd
    }
  }
}

extension GraphicsPath {
  var rasterPath: RasterPath {
    RasterPath(elements: elements.map { element in
      switch element {
      case .move(let point): .move(to: point.rasterPoint)
      case .line(let point): .line(to: point.rasterPoint)
      case .curve(let control1, let control2, let end):
        .cubic(control1: control1.rasterPoint, control2: control2.rasterPoint, end: end.rasterPoint)
      case .close: .close
      }
    })
  }

  init(_ rasterPath: RasterPath) {
    self.init(elements: rasterPath.elements.map { element in
      switch element {
      case .move(let point): .move(to: GraphicsPoint(x: point.x, y: point.y))
      case .line(let point): .line(to: GraphicsPoint(x: point.x, y: point.y))
      case .cubic(let control1, let control2, let end):
        .curve(
          control1: GraphicsPoint(x: control1.x, y: control1.y),
          control2: GraphicsPoint(x: control2.x, y: control2.y),
          end: GraphicsPoint(x: end.x, y: end.y)
        )
      case .close: .close
      }
    })
  }
}

extension RasterError {
  var postScriptError: Error {
    switch self {
    case .coordinateOverflow, .limitExceeded: .limitCheck
    case .invalidGeometry, .invalidImage, .finishedCanvas: .undefinedResult
    }
  }
}
