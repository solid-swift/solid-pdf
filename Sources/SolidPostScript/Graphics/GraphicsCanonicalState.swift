import Foundation
import SolidRaster

struct GraphicsClipStackEntry: Sendable {
  let clip: GraphicsClip
  let region: RasterRegion
}

struct GraphicsCanonicalState: Sendable {
  var device: PostScriptDeviceRecord
  var pageDeviceParameters: PostScriptPageDeviceParameters?
  var matrix: GraphicsMatrix
  var path: GraphicsPath
  var clip: GraphicsClip
  var paint: GraphicsPaint
  var colorSelection: PostScriptColorSelection
  var colorComponents: [Double]
  var patternSource: Object?
  var colorRenderingSource: Object?
  var transferFunctionSources: [Object?]
  var blackGenerationSource: Object?
  var undercolorRemovalSource: Object?
  var halftoneSource: Object?
  var deviceRendering: GraphicsDeviceRenderingSnapshot
  var screenLease: ScreenLease?
  var fontSource: Object?
  var font: GraphicsFontDescription
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

  var colorSpace: PostScriptColorSpace { colorSelection.source }

  static func initial(
    for descriptor: GraphicsDeviceDescriptor,
    device: PostScriptDeviceRecord? = nil
  ) -> Self {
    Self(
      device: device ?? .page(descriptor: descriptor),
      pageDeviceParameters: nil,
      matrix: descriptor.defaultMatrix,
      path: GraphicsPath(),
      clip: GraphicsClip(imageableBounds: descriptor.imageableBounds),
      paint: .deviceGray(0),
      colorSelection: .direct(.deviceGray(nil)),
      colorComponents: [0],
      patternSource: nil,
      colorRenderingSource: nil,
      transferFunctionSources: [nil, nil, nil, nil],
      blackGenerationSource: nil,
      undercolorRemovalSource: nil,
      halftoneSource: nil,
      deviceRendering: descriptor.deviceRendering.defaultState,
      screenLease: nil,
      fontSource: nil,
      font: .invalid,
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
      colorSpace: colorSelection.source.description,
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
      pathBoundingBox: pathBoundingBox,
      device: device.snapshot,
      deviceRendering: deviceRendering,
      font: font
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
    let preservedDevice = device
    let preservedPageDeviceParameters = pageDeviceParameters
    let preservedColorRenderingSource = colorRenderingSource
    let preservedTransferFunctionSources = transferFunctionSources
    let preservedBlackGenerationSource = blackGenerationSource
    let preservedUndercolorRemovalSource = undercolorRemovalSource
    let preservedHalftoneSource = halftoneSource
    let preservedDeviceRendering = deviceRendering
    let preservedScreenLease = screenLease
    let preservedOverprint = overprint
    let preservedFlatness = flatness
    let preservedStrokeAdjustment = strokeAdjustment
    let preservedSmoothness = smoothness
    let preservedClipStack = clipStack
    self = .initial(for: descriptor, device: preservedDevice)
    pageDeviceParameters = preservedPageDeviceParameters
    colorRenderingSource = preservedColorRenderingSource
    transferFunctionSources = preservedTransferFunctionSources
    blackGenerationSource = preservedBlackGenerationSource
    undercolorRemovalSource = preservedUndercolorRemovalSource
    halftoneSource = preservedHalftoneSource
    deviceRendering = preservedDeviceRendering
    screenLease = preservedScreenLease
    overprint = preservedOverprint
    flatness = preservedFlatness
    strokeAdjustment = preservedStrokeAdjustment
    smoothness = preservedSmoothness
    clipStack = preservedClipStack
  }

  func checkStorage(in vm: VM) throws {
    try dashSource?.checkStorage(in: vm)
    for object in colorSelection.retainedObjects { try object.checkStorage(in: vm) }
    try colorRenderingSource?.checkStorage(in: vm)
    for source in transferFunctionSources { try source?.checkStorage(in: vm) }
    try blackGenerationSource?.checkStorage(in: vm)
    try undercolorRemovalSource?.checkStorage(in: vm)
    try halftoneSource?.checkStorage(in: vm)
    try fontSource?.checkStorage(in: vm)
    try patternSource?.checkStorage(in: vm)
    try pageDeviceParameters?.checkStorage(in: vm)
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
