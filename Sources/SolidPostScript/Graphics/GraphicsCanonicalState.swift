import Foundation
import SolidRaster

struct GraphicsClipStackEntry: Sendable {
  let clip: GraphicsClip
  let region: RasterRegion
}

struct GraphicsCanonicalState: Sendable {
  var matrix: GraphicsMatrix
  var path: GraphicsPath
  var clip: GraphicsClip
  var paint: GraphicsPaint
  var colorSpace: PostScriptColorSpace
  var colorComponents: [Double]
  var colorRenderingSource: Object?
  var overprint: Bool
  var lineWidth: Double
  var lineCap: GraphicsLineCap
  var lineJoin: GraphicsLineJoin
  var miterLimit: Double
  var dash: GraphicsDash
  var dashSource: Object?
  var flatness: Double
  var strokeAdjustment: Bool
  var smoothness: Double
  var pathBoundingBox: GraphicsRect?
  var resolvedClip: RasterRegion
  var clipStack: [GraphicsClipStackEntry]

  static func initial(for descriptor: GraphicsDeviceDescriptor) -> Self {
    Self(
      matrix: descriptor.defaultMatrix,
      path: GraphicsPath(),
      clip: GraphicsClip(imageableBounds: descriptor.imageableBounds),
      paint: .deviceGray(0),
      colorSpace: .deviceGray(nil),
      colorComponents: [0],
      colorRenderingSource: nil,
      overprint: false,
      lineWidth: 1,
      lineCap: .butt,
      lineJoin: .miter,
      miterLimit: 10,
      dash: GraphicsDash(),
      dashSource: nil,
      flatness: descriptor.defaultFlatness,
      strokeAdjustment: descriptor.defaultStrokeAdjustment,
      smoothness: descriptor.defaultSmoothness,
      pathBoundingBox: nil,
      resolvedClip: (try? .rectangle(descriptor.imageableBounds.rasterRect)) ?? RasterRegion(),
      clipStack: []
    )
  }

  var snapshot: GraphicsStateSnapshot {
    GraphicsStateSnapshot(
      matrix: matrix,
      path: path,
      clip: clip,
      paint: paint,
      colorSpace: colorSpace.description,
      colorComponents: colorComponents,
      overprint: overprint,
      lineWidth: lineWidth,
      lineCap: lineCap,
      lineJoin: lineJoin,
      miterLimit: miterLimit,
      dash: dash,
      flatness: flatness,
      strokeAdjustment: strokeAdjustment,
      smoothness: smoothness,
      pathBoundingBox: pathBoundingBox
    )
  }

  mutating func clearPath() {
    path.removeAll()
    pathBoundingBox = nil
  }

  mutating func appendPath(_ element: GraphicsPath.Element) throws {
    if let pathBoundingBox {
      for point in element.points where !pathBoundingBox.contains(point) {
        throw Error.rangeCheck
      }
    }
    try path.append(element)
  }

  func validatePathBounds() throws {
    guard let pathBoundingBox else { return }
    guard path.elements.allSatisfy({ $0.points.allSatisfy(pathBoundingBox.contains) }) else {
      throw Error.rangeCheck
    }
  }

  mutating func initializeGraphics(for descriptor: GraphicsDeviceDescriptor) {
    let preservedFlatness = flatness
    let preservedStrokeAdjustment = strokeAdjustment
    let preservedSmoothness = smoothness
    let preservedClipStack = clipStack
    self = .initial(for: descriptor)
    flatness = preservedFlatness
    strokeAdjustment = preservedStrokeAdjustment
    smoothness = preservedSmoothness
    clipStack = preservedClipStack
  }

  func checkStorage(in vm: VM) throws {
    try dashSource?.checkStorage(in: vm)
    for object in colorSpace.retainedObjects { try object.checkStorage(in: vm) }
    try colorRenderingSource?.checkStorage(in: vm)
  }
}

struct GraphicsStackFrame: Sendable {
  enum Kind: Sendable {
    case graphicsSave
    case languageSave(UInt64)
  }

  let kind: Kind
  let state: GraphicsCanonicalState
}
