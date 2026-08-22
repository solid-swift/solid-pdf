import SolidColor
import SolidPostScript

struct PDFGraphicsState {
  struct ColorState {
    var space: GraphicsColorSpaceDescription
    var realization: GraphicsColorSpaceRealization?
    var components: [Double]
    var paint: GraphicsPaint
    var makePaint: (@Sendable ([Double]) throws -> GraphicsPaint)?

    init(
      space: GraphicsColorSpaceDescription,
      realization: GraphicsColorSpaceRealization? = nil,
      components: [Double],
      paint: GraphicsPaint,
      makePaint: (@Sendable ([Double]) throws -> GraphicsPaint)? = nil
    ) {
      self.space = space
      self.realization = realization
      self.components = components
      self.paint = paint
      self.makePaint = makePaint
    }
  }

  var matrix: GraphicsMatrix
  var pathElements: [GraphicsPath.Element] = []
  var clip: GraphicsClip
  var pendingClip: GraphicsFillRule?
  var stroking = ColorState(space: .deviceGray, components: [0], paint: .deviceGray(0))
  var nonstroking = ColorState(space: .deviceGray, components: [0], paint: .deviceGray(0))
  var strokingOverprint = false
  var nonstrokingOverprint = false
  var lineWidth = 1.0
  var lineCap = GraphicsLineCap.butt
  var lineJoin = GraphicsLineJoin.miter
  var miterLimit = 10.0
  var dash = GraphicsDash()
  var flatness = 1.0
  var strokeAdjustment = false
  var smoothness = 0.02
  var renderingIntent = ColorRenderingIntent.relativeColorimetric
  var deviceRendering = GraphicsDeviceRenderingSnapshot.continuousTone
  let device: GraphicsDeviceSnapshot

  init(device: GraphicsDeviceSnapshot) {
    self.device = device
    matrix = device.descriptor.defaultMatrix
    clip = GraphicsClip(imageableBounds: device.descriptor.imageableBounds)
    flatness = device.descriptor.defaultFlatness
    strokeAdjustment = device.descriptor.defaultStrokeAdjustment
    smoothness = device.descriptor.defaultSmoothness
    deviceRendering = device.descriptor.deviceRendering.defaultState
  }

  func snapshot(stroking useStroking: Bool, path: GraphicsPath? = nil) -> GraphicsStateSnapshot {
    let color = useStroking ? stroking : nonstroking
    return GraphicsStateSnapshot(
      matrix: matrix,
      path: path ?? GraphicsPath(elements: pathElements),
      clip: clip,
      paint: color.paint,
      colorSpace: color.space,
      colorRealization: color.realization,
      colorComponents: color.components,
      overprint: useStroking ? strokingOverprint : nonstrokingOverprint,
      lineWidth: lineWidth,
      lineCap: lineCap,
      lineJoin: lineJoin,
      miterLimit: miterLimit,
      dash: dash,
      flatness: flatness,
      strokeAdjustment: strokeAdjustment,
      smoothness: smoothness,
      device: device,
      deviceRendering: deviceRendering,
      renderingIntent: renderingIntent
    )
  }
}
