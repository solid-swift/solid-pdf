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
    "Dense Tiling Pattern",
    "Nested Pattern Display Lists",
    "Axial Gradient",
    "Radial Gradient",
    "Million-Vertex Mesh",
    "Patch Fallback Mesh",
    "Repeated Form Replay",
    "Nested Form Replay",
    "Form Pattern and Shading",
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
    let graphicsWorkloads = try patternAndShadingWorkloads(
      descriptor: descriptor,
      state: emptyState,
      page: page
    )
    let formWorkloads = try formWorkloads(descriptor: descriptor, state: emptyState, page: page)
    return pathWorkloads + [nearest, bilinear, combined] + graphicsWorkloads + formWorkloads
  }

  private static func formWorkloads(
    descriptor: GraphicsDeviceDescriptor,
    state: GraphicsStateSnapshot,
    page: GraphicsEvent
  ) throws -> [RasterRendererBenchmarkWorkload] {
    let cell = rectangle(GraphicsRect(x: 8, y: 8, width: 48, height: 48))
    let cellState = replacing(state, path: cell, paint: .deviceRGB(red: 0.1, green: 0.4, blue: 0.8))
    let leaf = GraphicsForm(
      bounds: GraphicsRect(x: 0, y: 0, width: 64, height: 64),
      matrix: .identity,
      deviceDescriptor: descriptor,
      compilationState: cellState,
      displayList: GraphicsDisplayList(effects: [.fill(path: cell, rule: .winding, state: cellState)])
    )
    let repeated = Array(
      repeating: RasterRendererBenchmarkWorkload.Command.process(event(.paint(.form(leaf)), state: state)),
      count: 1_000
    ) + [.process(page)]

    var nested = leaf
    for _ in 0..<12 {
      nested = GraphicsForm(
        bounds: leaf.bounds,
        matrix: .identity,
        deviceDescriptor: descriptor,
        compilationState: state,
        displayList: GraphicsDisplayList(effects: [.form(nested, state: state)])
      )
    }

    let pattern = GraphicsTilingPattern(
      paintType: 1,
      tilingType: 1,
      bounds: GraphicsRect(x: 0, y: 0, width: 64, height: 64),
      xStep: 64,
      yStep: 64,
      matrix: .identity,
      displayList: leaf.displayList
    )
    let surface = graphicsSurfacePath(
      width: Int(descriptor.mediaBounds.width),
      height: Int(descriptor.mediaBounds.height)
    )
    let patternedState = replacing(state, path: surface, paint: .pattern(.tiling(pattern, underlying: nil)))
    let shading = gradientShading(type: 2, radial: false)
    let mixed = GraphicsForm(
      bounds: descriptor.mediaBounds,
      matrix: .identity,
      deviceDescriptor: descriptor,
      compilationState: patternedState,
      displayList: GraphicsDisplayList(effects: [
        .fill(path: surface, rule: .winding, state: patternedState),
        .shading(shading, state: state),
      ])
    )

    return try [
      RasterRendererBenchmarkWorkload(
        name: names[13],
        pixelWidth: Int(descriptor.mediaBounds.width),
        pixelHeight: Int(descriptor.mediaBounds.height),
        deviceDescriptor: descriptor,
        commands: repeated
      ),
      workload(
        name: names[14],
        descriptor: descriptor,
        state: state,
        operation: .paint(.form(nested)),
        page: page
      ),
      workload(
        name: names[15],
        descriptor: descriptor,
        state: state,
        operation: .paint(.form(mixed)),
        page: page
      ),
    ]
  }

  private static func patternAndShadingWorkloads(
    descriptor: GraphicsDeviceDescriptor,
    state: GraphicsStateSnapshot,
    page: GraphicsEvent
  ) throws -> [RasterRendererBenchmarkWorkload] {
    let surface = graphicsSurfacePath(
      width: Int(descriptor.mediaBounds.width),
      height: Int(descriptor.mediaBounds.height)
    )
    let cell = rectangle(GraphicsRect(x: 0, y: 0, width: 4, height: 4))
    let cellState = replacing(state, path: cell, paint: .deviceRGB(red: 0.1, green: 0.4, blue: 0.8))
    let inner = GraphicsTilingPattern(
      paintType: 1,
      tilingType: 1,
      bounds: GraphicsRect(x: 0, y: 0, width: 8, height: 8),
      xStep: 8,
      yStep: 8,
      matrix: .identity,
      displayList: GraphicsDisplayList(effects: [.fill(path: cell, rule: .winding, state: cellState)])
    )
    let outerCell = rectangle(GraphicsRect(x: 0, y: 0, width: 16, height: 16))
    let outerCellState = replacing(state, path: outerCell, paint: .pattern(.tiling(inner, underlying: nil)))
    let outer = GraphicsTilingPattern(
      paintType: 1,
      tilingType: 1,
      bounds: GraphicsRect(x: 0, y: 0, width: 24, height: 24),
      xStep: 24,
      yStep: 24,
      matrix: .identity,
      displayList: GraphicsDisplayList(
        effects: [.fill(path: outerCell, rule: .winding, state: outerCellState)]
      )
    )
    let denseState = replacing(state, path: surface, paint: .pattern(.tiling(inner, underlying: nil)))
    let nestedState = replacing(state, path: surface, paint: .pattern(.tiling(outer, underlying: nil)))
    let axial = gradientShading(type: 2, radial: false)
    let radial = gradientShading(type: 3, radial: true)
    let millionVertex = meshShading(
      type: 4,
      triangleCount: 333_334,
      geometry: .triangles(type: 4, vertexCount: 1_000_002)
    )
    let patchFallback = meshShading(
      type: 7,
      triangleCount: 32_768,
      geometry: .patches(type: 7, patchCount: 32)
    )

    return try [
      workload(
        name: names[7],
        descriptor: descriptor,
        state: denseState,
        operation: .paint(.fill(.winding)),
        page: page
      ),
      workload(
        name: names[8],
        descriptor: descriptor,
        state: nestedState,
        operation: .paint(.fill(.winding)),
        page: page
      ),
      shadingWorkload(name: names[9], descriptor: descriptor, state: state, shading: axial, page: page),
      shadingWorkload(name: names[10], descriptor: descriptor, state: state, shading: radial, page: page),
      shadingWorkload(
        name: names[11],
        descriptor: descriptor,
        state: state,
        shading: millionVertex,
        page: page
      ),
      shadingWorkload(
        name: names[12],
        descriptor: descriptor,
        state: state,
        shading: patchFallback,
        page: page
      ),
    ]
  }

  private static func shadingWorkload(
    name: String,
    descriptor: GraphicsDeviceDescriptor,
    state: GraphicsStateSnapshot,
    shading: GraphicsShading,
    page: GraphicsEvent
  ) throws -> RasterRendererBenchmarkWorkload {
    try workload(
      name: name,
      descriptor: descriptor,
      state: state,
      operation: .paint(.shading(shading)),
      page: page
    )
  }

  private static func gradientShading(type: Int, radial: Bool) -> GraphicsShading {
    let width = Double(RasterBenchmarkFixtures.pathSurfaceWidth)
    let height = Double(RasterBenchmarkFixtures.pathSurfaceHeight)
    let triangles = gradientTriangles(width: width, height: height, columns: 256)
    let geometry: GraphicsShadingGeometry = radial
      ? .radial(
        startCenter: GraphicsPoint(x: width / 2, y: height / 2),
        startRadius: 0,
        endCenter: GraphicsPoint(x: width / 2, y: height / 2),
        endRadius: max(width, height) / 2,
        domainStart: 0,
        domainEnd: 1,
        extendStart: true,
        extendEnd: true,
        functions: []
      )
      : .axial(
        start: GraphicsPoint(x: 0, y: 0),
        end: GraphicsPoint(x: width, y: 0),
        domainStart: 0,
        domainEnd: 1,
        extendStart: true,
        extendEnd: true,
        functions: []
      )
    return GraphicsShading(
      type: type,
      colorSpace: .deviceRGB,
      geometry: geometry,
      mesh: GraphicsShadingMesh(triangles: triangles)
    )
  }

  private static func gradientTriangles(
    width: Double,
    height: Double,
    columns: Int
  ) -> [GraphicsShadingTriangle] {
    var triangles: [GraphicsShadingTriangle] = []
    triangles.reserveCapacity(columns * 2)
    for column in 0..<columns {
      let x0 = width * Double(column) / Double(columns)
      let x1 = width * Double(column + 1) / Double(columns)
      let firstPaint = gradientPaint(Double(column) / Double(columns))
      let secondPaint = gradientPaint(Double(column + 1) / Double(columns))
      let lowerLeft = GraphicsShadingVertex(position: .init(x: x0, y: 0), paint: firstPaint)
      let upperLeft = GraphicsShadingVertex(position: .init(x: x0, y: height), paint: firstPaint)
      let lowerRight = GraphicsShadingVertex(position: .init(x: x1, y: 0), paint: secondPaint)
      let upperRight = GraphicsShadingVertex(position: .init(x: x1, y: height), paint: secondPaint)
      triangles.append(.init(first: lowerLeft, second: lowerRight, third: upperRight))
      triangles.append(.init(first: lowerLeft, second: upperRight, third: upperLeft))
    }
    return triangles
  }

  private static func meshShading(
    type: Int,
    triangleCount: Int,
    geometry: GraphicsShadingGeometry
  ) -> GraphicsShading {
    let width = RasterBenchmarkFixtures.pathSurfaceWidth
    var triangles: [GraphicsShadingTriangle] = []
    triangles.reserveCapacity(triangleCount)
    for index in 0..<triangleCount {
      let x = Double(index % width)
      let y = Double((index / width) % RasterBenchmarkFixtures.pathSurfaceHeight)
      let paint = gradientPaint(Double(index % 256) / 255)
      triangles.append(.init(
        first: .init(position: .init(x: x, y: y), paint: paint),
        second: .init(position: .init(x: x + 1, y: y), paint: paint),
        third: .init(position: .init(x: x, y: y + 1), paint: paint)
      ))
    }
    return GraphicsShading(
      type: type,
      colorSpace: .deviceRGB,
      geometry: geometry,
      mesh: GraphicsShadingMesh(triangles: triangles)
    )
  }

  private static func gradientPaint(_ value: Double) -> GraphicsPaint {
    .deviceRGB(red: 1 - value, green: 0.2, blue: value)
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
