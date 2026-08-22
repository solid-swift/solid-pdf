import Foundation

/// A validated, typed PostScript graphics operation.
public enum GraphicsOperation: Sendable, Hashable {
  /// A graphics-state stack or initialization operation.
  public enum State: Sendable, Hashable {
    case save
    case restore
    case restoreAll
    case initialize
    case clipSave
    case clipRestore
    case setGraphicsState
    case setLineWidth(Double)
    case setLineCap(GraphicsLineCap)
    case setLineJoin(GraphicsLineJoin)
    case setMiterLimit(Double)
    case setDash(GraphicsDash)
    case setFlatness(Double)
    case setStrokeAdjustment(Bool)
    case setSmoothness(Double)
    case setGray(Double)
    case setRGB(red: Double, green: Double, blue: Double)
    case setCMYK(cyan: Double, magenta: Double, yellow: Double, black: Double)
    case setColorSpace(GraphicsColorSpaceDescription)
    case setColor(GraphicsColorValue)
    case setColorRendering
    case setOverprint(Bool)
    case setTransferFunctions
    case setBlackGeneration
    case setUndercolorRemoval
    case setHalftone
    case setFont(GraphicsFontDescription)
    case setTrappingParameters(GraphicsTrappingParameters)
    case setTrappingZone(GraphicsTrappingZone)
  }

  /// A current-transformation operation.
  public enum Transform: Sendable, Hashable {
    case setMatrix(GraphicsMatrix)
    case translate(x: Double, y: Double)
    case scale(x: Double, y: Double)
    case rotate(degrees: Double)
    case concatenate(GraphicsMatrix)
  }

  /// A current-path construction operation.
  public enum Path: Sendable, Hashable {
    case new
    case move(to: GraphicsPoint)
    case relativeMove(dx: Double, dy: Double)
    case line(to: GraphicsPoint)
    case relativeLine(dx: Double, dy: Double)
    case curve(control1: GraphicsPoint, control2: GraphicsPoint, end: GraphicsPoint)
    case relativeCurve(
      control1: GraphicsPoint,
      control2: GraphicsPoint,
      end: GraphicsPoint
    )
    case arc(center: GraphicsPoint, radius: Double, startDegrees: Double, endDegrees: Double)
    case arcNegative(center: GraphicsPoint, radius: Double, startDegrees: Double, endDegrees: Double)
    case arcTo(corner: GraphicsPoint, following: GraphicsPoint, radius: Double)
    case close
    case setBoundingBox(GraphicsRect)
    case flatten
    case reverse
    case strokeOutline
    case clippingPath
    case appendUserPath
    case exportUserPath
    case textOutline
  }

  /// A clipping operation.
  public enum Clip: Sendable, Hashable {
    case initialize
    case intersect(GraphicsFillRule)
    case intersectRectangles([GraphicsPath])
  }

  /// A painting operation.
  public enum Paint: Sendable, Hashable {
    case erasePage
    case fill(GraphicsFillRule)
    case stroke
    case fillRectangles([GraphicsPath])
    case strokeRectangles(paths: [GraphicsPath], matrix: GraphicsMatrix?)
    case image(GraphicsImageDescriptor)
    case userPathFill(GraphicsFillRule)
    case userPathStroke
    case shading(GraphicsShading)
    case form(GraphicsForm)
    case text(GraphicsGlyphRun)
  }

  /// A page-lifecycle operation.
  public enum Page: Sendable, Hashable {
    case show
    case copy
  }

  /// A document-semantic operation that does not directly paint.
  public enum Content: Sendable, Hashable {
    case markedContent(GraphicsMarkedContentOperation)
  }

  case state(State)
  case transform(Transform)
  case path(Path)
  case clip(Clip)
  case paint(Paint)
  case content(Content)
  case page(Page)
}
