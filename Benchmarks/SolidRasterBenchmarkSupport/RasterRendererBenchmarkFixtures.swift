import SolidPostScript

/// Prepared target-level workloads shared by native and PlutoVG benchmarks.
public enum RasterRendererBenchmarkFixtures {
  /// Stable workload names in registration order.
  public static let names = [
    "Flat Fill",
    "1,000 Cubic Fill",
    "Dashed Stroke",
    "Deep Clip Fill",
    "8 MP Nearest Image",
    "8 MP Bilinear Image",
    "Combined Path-Heavy Page",
  ]

  /// Creates every comparison workload without including fixture construction in measurements.
  public static func all() throws -> [RasterRendererBenchmarkWorkload] {
    let width = RasterBenchmarkFixtures.pathSurfaceWidth
    let height = RasterBenchmarkFixtures.pathSurfaceHeight
    let descriptor = deviceDescriptor(width: width, height: height)
    let emptyState = state(width: width, height: height)
    let surfacePath = graphicsSurfacePath(width: width, height: height)
    let cubicPath = graphicsCubicPath()
    let deepClip = graphicsDeepClip(width: width, height: height)
    let page = pageEvent(state: emptyState)

    let flatState = replacing(emptyState, path: surfacePath)
    let cubicState = replacing(emptyState, path: cubicPath)
    let dashState = replacing(
      cubicState,
      paint: .deviceRGB(red: 0.1, green: 0.4, blue: 0.8),
      lineWidth: 3,
      lineCap: .round,
      lineJoin: .round,
      dash: GraphicsDash(pattern: [8, 3, 2, 3])
    )
    let clippedState = replacing(flatState, clip: deepClip)

    let pathWorkloads = try [
      workload(name: names[0], descriptor: descriptor, state: flatState, operation: .paint(.fill(.winding)), page: page),
      workload(name: names[1], descriptor: descriptor, state: cubicState, operation: .paint(.fill(.winding)), page: page),
      workload(name: names[2], descriptor: descriptor, state: dashState, operation: .paint(.stroke), page: page),
      workload(name: names[3], descriptor: descriptor, state: clippedState, operation: .paint(.fill(.winding)), page: page),
    ]

    let nearest = try imageWorkload(name: names[4], interpolate: false)
    let bilinear = try imageWorkload(name: names[5], interpolate: true)
    let combined = try RasterRendererBenchmarkWorkload(
      name: names[6],
      pixelWidth: width,
      pixelHeight: height,
      deviceDescriptor: descriptor,
      commands: [
        .process(event(.paint(.fill(.winding)), state: clippedState)),
        .process(event(.paint(.stroke), state: dashState)),
        .process(page),
      ],
      enforcesPerformanceGate: true
    )
    return pathWorkloads + [nearest, bilinear, combined]
  }

  private static func workload(
    name: String,
    descriptor: GraphicsDeviceDescriptor,
    state: GraphicsStateSnapshot,
    operation: GraphicsOperation,
    page: GraphicsEvent
  ) throws -> RasterRendererBenchmarkWorkload {
    try RasterRendererBenchmarkWorkload(
      name: name,
      pixelWidth: Int(descriptor.mediaBounds.width),
      pixelHeight: Int(descriptor.mediaBounds.height),
      deviceDescriptor: descriptor,
      commands: [.process(event(operation, state: state)), .process(page)]
    )
  }

  private static func imageWorkload(name: String, interpolate: Bool) throws -> RasterRendererBenchmarkWorkload {
    let width = RasterBenchmarkFixtures.imageWidth
    let height = RasterBenchmarkFixtures.imageHeight
    let descriptor = deviceDescriptor(width: width, height: height)
    let state = state(width: width, height: height)
    let image = GraphicsImageDescriptor(
      width: width,
      height: height,
      kind: .color(.deviceGray),
      imageToDevice: .identity,
      interpolate: interpolate
    )
    let imageEvent = event(.paint(.image(image)), state: state)
    let rowsPerCommand = 128
    var commands: [RasterRendererBenchmarkWorkload.Command] = [.beginImage(imageEvent)]
    for startRow in stride(from: 0, to: height, by: rowsPerCommand) {
      let rowCount = min(rowsPerCommand, height - startRow)
      var components = [Float]()
      components.reserveCapacity(width * rowCount)
      for y in startRow..<(startRow + rowCount) {
        for x in 0..<width {
          components.append(Float((x ^ y) & 0xff) / 255)
        }
      }
      commands.append(.imageRows(GraphicsImageRows(startRow: startRow, rowCount: rowCount, components: components)))
    }
    commands.append(.endImage)
    commands.append(.process(pageEvent(state: state)))
    return try RasterRendererBenchmarkWorkload(
      name: name,
      pixelWidth: width,
      pixelHeight: height,
      deviceDescriptor: descriptor,
      commands: commands
    )
  }

  private static func event(_ operation: GraphicsOperation, state: GraphicsStateSnapshot) -> GraphicsEvent {
    GraphicsEvent(operation: operation, before: state, after: state)
  }

  private static func pageEvent(state: GraphicsStateSnapshot) -> GraphicsEvent {
    event(.page(.show), state: state)
  }

  private static func state(width: Int, height: Int) -> GraphicsStateSnapshot {
    GraphicsStateSnapshot(
      matrix: .identity,
      path: GraphicsPath(),
      clip: GraphicsClip(imageableBounds: GraphicsRect(x: 0, y: 0, width: Double(width), height: Double(height))),
      paint: .deviceGray(0),
      lineWidth: 1,
      lineCap: .butt,
      lineJoin: .miter,
      miterLimit: 10,
      dash: GraphicsDash()
    )
  }

  private static func replacing(
    _ state: GraphicsStateSnapshot,
    path: GraphicsPath? = nil,
    clip: GraphicsClip? = nil,
    paint: GraphicsPaint? = nil,
    lineWidth: Double? = nil,
    lineCap: GraphicsLineCap? = nil,
    lineJoin: GraphicsLineJoin? = nil,
    dash: GraphicsDash? = nil
  ) -> GraphicsStateSnapshot {
    GraphicsStateSnapshot(
      matrix: state.matrix,
      path: path ?? state.path,
      clip: clip ?? state.clip,
      paint: paint ?? state.paint,
      lineWidth: lineWidth ?? state.lineWidth,
      lineCap: lineCap ?? state.lineCap,
      lineJoin: lineJoin ?? state.lineJoin,
      miterLimit: state.miterLimit,
      dash: dash ?? state.dash
    )
  }

  private static func deviceDescriptor(width: Int, height: Int) -> GraphicsDeviceDescriptor {
    let bounds = GraphicsRect(x: 0, y: 0, width: Double(width), height: Double(height))
    return GraphicsDeviceDescriptor(
      mediaBounds: bounds,
      imageableBounds: bounds,
      horizontalResolution: 72,
      verticalResolution: 72,
      defaultMatrix: .identity
    )
  }

  private static func graphicsSurfacePath(width: Int, height: Int) -> GraphicsPath {
    rectangle(GraphicsRect(x: 0, y: 0, width: Double(width), height: Double(height)))
  }

  private static func graphicsCubicPath() -> GraphicsPath {
    var elements: [GraphicsPath.Element] = [.move(to: GraphicsPoint(x: 16, y: 384))]
    elements.reserveCapacity(1_001)
    for index in 0..<1_000 {
      let x = 16 + Double(index % 50) * 12
      let y = 16 + Double(index / 50) * 36
      elements.append(
        .curve(
          control1: GraphicsPoint(x: x + 3, y: y - 12),
          control2: GraphicsPoint(x: x + 9, y: y + 12),
          end: GraphicsPoint(x: x + 12, y: y)
        )
      )
    }
    return GraphicsPath(elements: elements)
  }

  private static func graphicsDeepClip(width: Int, height: Int) -> GraphicsClip {
    let bounds = GraphicsRect(x: 0, y: 0, width: Double(width), height: Double(height))
    let constraints = (0..<32).map { index in
      let inset = Double(index + 1) * 3
      return GraphicsClipConstraint(
        path: rectangle(
          GraphicsRect(
            x: inset,
            y: inset,
            width: max(0, bounds.width - inset * 2),
            height: max(0, bounds.height - inset * 2)
          )
        ),
        rule: .winding
      )
    }
    return GraphicsClip(imageableBounds: bounds, constraints: constraints)
  }

  private static func rectangle(_ rect: GraphicsRect) -> GraphicsPath {
    GraphicsPath(elements: [
      .move(to: GraphicsPoint(x: rect.x, y: rect.y)),
      .line(to: GraphicsPoint(x: rect.maxX, y: rect.y)),
      .line(to: GraphicsPoint(x: rect.maxX, y: rect.maxY)),
      .line(to: GraphicsPoint(x: rect.x, y: rect.maxY)),
      .close,
    ])
  }
}
