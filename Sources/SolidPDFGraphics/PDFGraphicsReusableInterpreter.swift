import Foundation
import SolidColor
import SolidPDF
import SolidPostScript

extension PDFGraphicsInstructionHandler {
  func compilePattern(
    named name: PDFName,
    underlying: GraphicsPaint?,
    instruction: PDFContentInstruction
  ) async throws -> GraphicsPatternPaint {
    guard let object = try await resources.resourceObject(category: "Pattern", name: name) else {
      throw malformed("Missing pattern resource.", instruction)
    }
    let dictionary: [PDFName: PDFObject]
    let stream: PDFStreamObject?
    let identifier: GraphicsResourceIdentifier
    if case .reference(let reference) = object {
      let resolved = try await resources.document.resolve(reference, in: resources.revision)
      identifier = resourceIdentifier(reference)
      switch resolved.value {
      case .value(.dictionary(let value)):
        dictionary = value
        stream = nil
      case .stream(let value):
        dictionary = value.dictionary
        stream = value
      default: throw malformed("Pattern resource is invalid.", instruction)
      }
    } else {
      dictionary = try PDFObjectAccess.dictionary(object)
      stream = nil
      identifier = .anonymous
    }
    let type = try PDFObjectAccess.integer(dictionary["PatternType"] ?? .null)
    let matrix = try dictionary["Matrix"].map(PDFObjectAccess.numbers).map(graphicsMatrix) ?? .identity
    switch type {
    case 1:
      guard let stream else { throw malformed("Tiling pattern is not a stream.", instruction) }
      let paintType = try PDFObjectAccess.integer(dictionary["PaintType"] ?? .null)
      let tilingType = try PDFObjectAccess.integer(dictionary["TilingType"] ?? .null)
      let bounds = try graphicsRect(PDFObjectAccess.numbers(dictionary["BBox"] ?? .null))
      let xStep = try PDFObjectAccess.number(dictionary["XStep"] ?? .null)
      let yStep = try PDFObjectAccess.number(dictionary["YStep"] ?? .null)
      guard [1, 2].contains(paintType), (1...3).contains(tilingType), xStep != 0, yStep != 0 else {
        throw malformed("Invalid tiling pattern dictionary.", instruction)
      }
      if paintType == 1, underlying != nil { throw malformed("Colored pattern has an underlying color.", instruction) }
      if paintType == 2, underlying == nil { throw malformed("Uncolored pattern lacks an underlying color.", instruction) }
      let localResources: [PDFName: PDFObject]?
      if let object = dictionary["Resources"] {
        localResources = try PDFObjectAccess.dictionary(try await resources.resolvedObject(object))
      } else {
        localResources = nil
      }
      let reference = stream.objectReference
      if let reference { try resources.enter(reference) }
      try resources.push(resources: localResources)
      do {
        let page = try await resources.document.page(at: instruction.location.pageIndex, in: resources.revision)
        var childState = state
        childState.pathElements = []
        childState.pendingClip = nil
        childState.matrix = matrix.concatenated(with: state.matrix)
        childState.clip = try childState.clip.appending(.init(
          path: rectanglePath(bounds).transformed(by: childState.matrix),
          rule: .winding
        ))
        let collector = PDFGraphicsCollectorOutput()
        let handler = PDFGraphicsInstructionHandler(
          device: state.device,
          resources: resources,
          limits: limits,
          output: collector,
          initialState: childState,
          type3Capture: type3Capture,
          type3Depth: type3Depth
        )
        let input = PDFContentInput(streams: [stream]) { [document = resources.document] stream in
          try await document.decodedStream(of: stream)
        }
        let parser = PDFContentParser(
          input: input,
          revision: resources.revision,
          page: page,
          maximumScratchBytes: limits.maximumScratchBytes,
          resourceStack: instruction.location.resourceStack + (reference.map { [$0] } ?? [])
        )
        try await PDFContentExecutor(
          parser: parser,
          handler: handler,
          maximumOperators: limits.maximumOperatorsPerPage
        ).execute()
        resources.pop()
        if let reference { resources.leave(reference) }
        return .tiling(
          GraphicsTilingPattern(
            paintType: paintType,
            tilingType: tilingType,
            bounds: bounds,
            xStep: xStep,
            yStep: yStep,
            matrix: childState.matrix,
            displayList: .init(effects: collector.collector.effects, resourceIdentifier: identifier),
            resourceIdentifier: identifier
          ),
          underlying: underlying
        )
      } catch {
        resources.pop()
        if let reference { resources.leave(reference) }
        throw error
      }
    case 2:
      guard let shadingObject = dictionary["Shading"] else { throw malformed("Shading pattern lacks Shading.", instruction) }
      let savedMatrix = state.matrix
      state.matrix = matrix.concatenated(with: state.matrix)
      do {
        let shading = try await compileShading(shadingObject, instruction: instruction)
        state.matrix = savedMatrix
        return .shading(shading)
      } catch {
        state.matrix = savedMatrix
        throw error
      }
    default: throw malformed("Invalid pattern type.", instruction)
    }
  }

  func paintForm(
    _ stream: PDFStreamObject,
    reference: PDFObjectReference,
    instruction: PDFContentInstruction
  ) async throws {
    if stream.dictionary["Ref"] != nil {
      throw PDFGraphicsError.unsupported(.referenceXObject, location: instruction.location)
    }
    if stream.dictionary["Group"] != nil {
      throw PDFGraphicsError.unsupported(.transparencyGroup, location: instruction.location)
    }
    let bounds = try graphicsRect(PDFObjectAccess.numbers(stream.dictionary["BBox"] ?? .null))
    let matrix = try stream.dictionary["Matrix"].map(PDFObjectAccess.numbers).map(graphicsMatrix) ?? .identity
    let localResources: [PDFName: PDFObject]?
    if let resourceObject = stream.dictionary["Resources"] {
      localResources = try PDFObjectAccess.dictionary(try await resources.resolvedObject(resourceObject))
    } else {
      localResources = nil
    }
    try resources.enter(reference)
    try resources.push(resources: localResources)
    do {
      let page = try await resources.document.page(at: instruction.location.pageIndex, in: resources.revision)
      var childState = state
      childState.pathElements = []
      childState.pendingClip = nil
      childState.matrix = matrix.concatenated(with: state.matrix)
      let clipPath = rectanglePath(bounds).transformed(by: childState.matrix)
      childState.clip = try childState.clip.appending(.init(path: clipPath, rule: .winding))
      let collector = PDFGraphicsCollectorOutput()
      let handler = PDFGraphicsInstructionHandler(
        device: state.device,
        resources: resources,
        limits: limits,
        output: collector,
        initialState: childState,
        type3Capture: type3Capture,
        type3Depth: type3Depth
      )
      let input = PDFContentInput(streams: [stream]) { [document = resources.document] stream in
        try await document.decodedStream(of: stream)
      }
      let parser = PDFContentParser(
        input: input,
        revision: resources.revision,
        page: page,
        maximumScratchBytes: limits.maximumScratchBytes,
        resourceStack: instruction.location.resourceStack + [reference]
      )
      try await PDFContentExecutor(
        parser: parser,
        handler: handler,
        maximumOperators: limits.maximumOperatorsPerPage
      ).execute()
      let identifier = resourceIdentifier(reference)
      let form = GraphicsForm(
        bounds: bounds,
        matrix: matrix,
        deviceDescriptor: state.device.descriptor,
        compilationState: childState.snapshot(stroking: false),
        displayList: GraphicsDisplayList(effects: collector.collector.effects, resourceIdentifier: identifier),
        resourceIdentifier: identifier
      )
      try output.process(GraphicsEvent(
        operation: .paint(.form(form)),
        before: state.snapshot(stroking: false),
        after: state.snapshot(stroking: false),
        origin: origin(instruction.location, resource: identifier)
      ))
      resources.pop()
      resources.leave(reference)
    } catch {
      resources.pop()
      resources.leave(reference)
      throw error
    }
  }

  func paintShading(_ instruction: PDFContentInstruction) async throws {
    try operands(instruction, count: 1)
    let name = try PDFObjectAccess.name(instruction.operands[0])
    guard let object = try await resources.resourceObject(category: "Shading", name: name) else {
      throw malformed("Missing shading resource.", instruction)
    }
    let shading = try await compileShading(object, instruction: instruction)
    try output.process(GraphicsEvent(
      operation: .paint(.shading(shading)),
      before: state.snapshot(stroking: false),
      after: state.snapshot(stroking: false),
      origin: origin(instruction.location, resource: shading.resourceIdentifier)
    ))
  }

  private func graphicsRect(_ values: [Double]) throws -> GraphicsRect {
    guard values.count == 4, values.allSatisfy(\.isFinite) else { throw PDFObjectAccess.TypeMismatch.array }
    return GraphicsRect(
      x: min(values[0], values[2]),
      y: min(values[1], values[3]),
      width: abs(values[2] - values[0]),
      height: abs(values[3] - values[1])
    )
  }

  private func graphicsMatrix(_ values: [Double]) throws -> GraphicsMatrix {
    guard values.count == 6, values.allSatisfy(\.isFinite) else { throw PDFObjectAccess.TypeMismatch.array }
    return GraphicsMatrix(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
  }

  private func rectanglePath(_ rect: GraphicsRect) -> GraphicsPath {
    GraphicsPath(elements: [
      .move(to: .init(x: rect.x, y: rect.y)),
      .line(to: .init(x: rect.maxX, y: rect.y)),
      .line(to: .init(x: rect.maxX, y: rect.maxY)),
      .line(to: .init(x: rect.x, y: rect.maxY)),
      .close,
    ])
  }

  func compileShading(
    _ object: PDFObject,
    instruction: PDFContentInstruction
  ) async throws -> GraphicsShading {
    let dictionary: [PDFName: PDFObject]
    let stream: PDFStreamObject?
    let identifier: GraphicsResourceIdentifier
    if case .reference(let reference) = object {
      let resolved = try await resources.document.resolve(reference, in: resources.revision)
      switch resolved.value {
      case .value(.dictionary(let value)):
        dictionary = value
        stream = nil
      case .stream(let value):
        dictionary = value.dictionary
        stream = value
      default: throw malformed("Shading resource is not a dictionary or stream.", instruction)
      }
      identifier = resourceIdentifier(reference)
    } else {
      dictionary = try PDFObjectAccess.dictionary(object)
      stream = nil
      identifier = .anonymous
    }
    let type = try PDFObjectAccess.integer(dictionary["ShadingType"] ?? .null)
    let colorSpace = try await resources.colorSpace(dictionary["ColorSpace"] ?? .null)
    let functions: [ColorFunction]
    if let function = dictionary["Function"] {
      functions = try await shadingFunctions(function)
    } else {
      functions = []
    }
    let background = try dictionary["Background"].map(PDFObjectAccess.numbers).map(colorSpace.makePaint)
    let bounds = try dictionary["BBox"].map(PDFObjectAccess.numbers).map(graphicsRect)
    let antialias = try booleanValue(dictionary["AntiAlias"], default: false)
    let clip = bounds.map { rectanglePath($0).transformed(by: state.matrix) }
    switch type {
    case 1:
      guard !functions.isEmpty else { throw malformed("Function shading lacks Function.", instruction) }
      let domain = try dictionary["Domain"].map(PDFObjectAccess.numbers) ?? [0, 1, 0, 1]
      guard domain.count == 4 else { throw malformed("Invalid function shading domain.", instruction) }
      let matrix = try dictionary["Matrix"].map(PDFObjectAccess.numbers).map(graphicsMatrix) ?? .identity
      let resolvedMatrix = matrix.concatenated(with: state.matrix)
      let vertices = try shadingGrid(rows: 17, columns: 17) { row, column in
        let x = domain[0] + (domain[1] - domain[0]) * Double(column) / 16
        let y = domain[2] + (domain[3] - domain[2]) * Double(row) / 16
        return GraphicsShadingVertex(
          position: resolvedMatrix.transform(.init(x: x, y: y)),
          paint: try colorSpace.makePaint(evaluate(functions, input: [x, y]))
        )
      }
      return GraphicsShading(
        type: type,
        colorSpace: colorSpace.description,
        colorRealization: colorSpace.realization,
        background: background,
        bounds: bounds,
        clipPath: clip,
        antialias: antialias,
        geometry: .function(
          domain: .init(x: domain[0], y: domain[2], width: domain[1] - domain[0], height: domain[3] - domain[2]),
          matrix: matrix,
          functions: functions
        ),
        mesh: .init(triangles: triangles(vertices)),
        resourceIdentifier: identifier
      )
    case 2:
      guard !functions.isEmpty else { throw malformed("Axial shading lacks Function.", instruction) }
      let coordinates = try PDFObjectAccess.numbers(dictionary["Coords"] ?? .null)
      let domain = try dictionary["Domain"].map(PDFObjectAccess.numbers) ?? [0, 1]
      let extend = try booleanArray(dictionary["Extend"], default: [false, false])
      guard coordinates.count == 4, domain.count == 2, extend.count == 2 else {
        throw malformed("Invalid axial shading geometry.", instruction)
      }
      let start = GraphicsPoint(x: coordinates[0], y: coordinates[1])
      let end = GraphicsPoint(x: coordinates[2], y: coordinates[3])
      let deviceStart = state.matrix.transform(start)
      let deviceEnd = state.matrix.transform(end)
      let dx = deviceEnd.x - deviceStart.x
      let dy = deviceEnd.y - deviceStart.y
      let length = max(1, hypot(dx, dy))
      let normal = GraphicsPoint(x: -dy / length * 100_000, y: dx / length * 100_000)
      var strips: [[GraphicsShadingVertex]] = []
      for index in 0...64 {
        let ratio = Double(index) / 64
        let value = domain[0] + (domain[1] - domain[0]) * ratio
        let center = GraphicsPoint(x: deviceStart.x + dx * ratio, y: deviceStart.y + dy * ratio)
        let paint = try colorSpace.makePaint(evaluate(functions, input: [value]))
        strips.append([
          .init(position: .init(x: center.x - normal.x, y: center.y - normal.y), paint: paint),
          .init(position: .init(x: center.x + normal.x, y: center.y + normal.y), paint: paint),
        ])
      }
      return GraphicsShading(
        type: type,
        colorSpace: colorSpace.description,
        colorRealization: colorSpace.realization,
        background: background,
        bounds: bounds,
        clipPath: clip,
        antialias: antialias,
        geometry: .axial(
          start: start,
          end: end,
          domainStart: domain[0],
          domainEnd: domain[1],
          extendStart: extend[0],
          extendEnd: extend[1],
          functions: functions
        ),
        mesh: .init(triangles: triangles(strips)),
        resourceIdentifier: identifier
      )
    case 3:
      guard !functions.isEmpty else { throw malformed("Radial shading lacks Function.", instruction) }
      let coordinates = try PDFObjectAccess.numbers(dictionary["Coords"] ?? .null)
      let domain = try dictionary["Domain"].map(PDFObjectAccess.numbers) ?? [0, 1]
      let extend = try booleanArray(dictionary["Extend"], default: [false, false])
      guard coordinates.count == 6, coordinates[2] >= 0, coordinates[5] >= 0,
        domain.count == 2, extend.count == 2
      else { throw malformed("Invalid radial shading geometry.", instruction) }
      let start = GraphicsPoint(x: coordinates[0], y: coordinates[1])
      let end = GraphicsPoint(x: coordinates[3], y: coordinates[4])
      var rings: [[GraphicsShadingVertex]] = []
      for ring in 0...32 {
        let ratio = Double(ring) / 32
        let center = GraphicsPoint(
          x: start.x + (end.x - start.x) * ratio,
          y: start.y + (end.y - start.y) * ratio
        )
        let radius = coordinates[2] + (coordinates[5] - coordinates[2]) * ratio
        let value = domain[0] + (domain[1] - domain[0]) * ratio
        let paint = try colorSpace.makePaint(evaluate(functions, input: [value]))
        rings.append((0...64).map { segment in
          let angle = Double(segment) / 64 * 2 * Double.pi
          return GraphicsShadingVertex(
            position: state.matrix.transform(.init(
              x: center.x + cos(angle) * radius,
              y: center.y + sin(angle) * radius
            )),
            paint: paint
          )
        })
      }
      return GraphicsShading(
        type: type,
        colorSpace: colorSpace.description,
        colorRealization: colorSpace.realization,
        background: background,
        bounds: bounds,
        clipPath: clip,
        antialias: antialias,
        geometry: .radial(
          startCenter: start,
          startRadius: coordinates[2],
          endCenter: end,
          endRadius: coordinates[5],
          domainStart: domain[0],
          domainEnd: domain[1],
          extendStart: extend[0],
          extendEnd: extend[1],
          functions: functions
        ),
        mesh: .init(triangles: triangles(rings)),
        resourceIdentifier: identifier
      )
    case 4, 5:
      guard let stream else { throw malformed("Mesh shading is not a stream.", instruction) }
      let data = try await resources.document.decodedBytes(of: stream)
      let mesh = try triangleMesh(
        type: type,
        dictionary: dictionary,
        data: data,
        colorSpace: colorSpace,
        functions: functions,
        instruction: instruction
      )
      return GraphicsShading(
        type: type,
        colorSpace: colorSpace.description,
        colorRealization: colorSpace.realization,
        background: background,
        bounds: bounds,
        clipPath: clip,
        antialias: antialias,
        geometry: .triangles(type: type, vertexCount: mesh.vertexCount),
        mesh: .init(triangles: mesh.triangles),
        resourceIdentifier: identifier
      )
    case 6, 7:
      guard let stream else { throw malformed("Patch shading is not a stream.", instruction) }
      let data = try await resources.document.decodedBytes(of: stream)
      let patches = try patchMesh(
        type: type,
        dictionary: dictionary,
        data: data,
        colorSpace: colorSpace,
        functions: functions,
        instruction: instruction
      )
      return GraphicsShading(
        type: type,
        colorSpace: colorSpace.description,
        colorRealization: colorSpace.realization,
        background: background,
        bounds: bounds,
        clipPath: clip,
        antialias: antialias,
        geometry: .patches(type: type, patchCount: patches.source.count),
        mesh: .init(triangles: patches.triangles),
        sourcePatches: patches.source,
        resourceIdentifier: identifier
      )
    default: throw malformed("Invalid shading type.", instruction)
    }
  }

  private func shadingFunctions(_ object: PDFObject?) async throws -> [ColorFunction] {
    guard let object else { throw PDFObjectAccess.TypeMismatch.dictionary }
    if case .array(let values) = object {
      var result: [ColorFunction] = []
      for value in values { result.append(try await resources.colorFunction(value)) }
      return result
    }
    return [try await resources.colorFunction(object)]
  }

  private func evaluate(_ functions: [ColorFunction], input: [Double]) throws -> [Double] {
    if functions.count == 1 { return try functions[0].evaluate(input) }
    return try functions.map {
      let value = try $0.evaluate(input)
      guard value.count == 1 else { throw PDFObjectAccess.TypeMismatch.array }
      return value[0]
    }
  }

  private func shadingGrid(
    rows: Int,
    columns: Int,
    make: (Int, Int) throws -> GraphicsShadingVertex
  ) throws -> [[GraphicsShadingVertex]] {
    try (0..<rows).map { row in try (0..<columns).map { try make(row, $0) } }
  }

  private func triangles(_ rows: [[GraphicsShadingVertex]]) -> [GraphicsShadingTriangle] {
    guard rows.count >= 2 else { return [] }
    var result: [GraphicsShadingTriangle] = []
    for row in 0..<(rows.count - 1) {
      let count = min(rows[row].count, rows[row + 1].count)
      guard count >= 2 else { continue }
      for column in 0..<(count - 1) {
        result.append(.init(
          first: rows[row][column],
          second: rows[row + 1][column],
          third: rows[row + 1][column + 1]
        ))
        result.append(.init(
          first: rows[row][column],
          second: rows[row + 1][column + 1],
          third: rows[row][column + 1]
        ))
      }
    }
    return result
  }

  private func booleanArray(_ object: PDFObject?, default value: [Bool]) throws -> [Bool] {
    guard let object else { return value }
    return try PDFObjectAccess.array(object).map {
      guard case .boolean(let result) = $0 else { throw PDFObjectAccess.TypeMismatch.array }
      return result
    }
  }

  private func booleanValue(_ object: PDFObject?, default value: Bool) throws -> Bool {
    guard let object else { return value }
    guard case .boolean(let result) = object else { throw PDFObjectAccess.TypeMismatch.integer }
    return result
  }

  private func triangleMesh(
    type: Int,
    dictionary: [PDFName: PDFObject],
    data: Data,
    colorSpace: PDFGraphicsResourceResolver<Source>.ResolvedColorSpace,
    functions: [ColorFunction],
    instruction: PDFContentInstruction
  ) throws -> (vertexCount: Int, triangles: [GraphicsShadingTriangle]) {
    let coordinateBits = try PDFObjectAccess.integer(dictionary["BitsPerCoordinate"] ?? .null)
    let componentBits = try PDFObjectAccess.integer(dictionary["BitsPerComponent"] ?? .null)
    let flagBits = type == 4 ? try PDFObjectAccess.integer(dictionary["BitsPerFlag"] ?? .null) : 0
    guard [1, 2, 4, 8, 12, 16, 24, 32].contains(coordinateBits),
      [1, 2, 4, 8, 12, 16].contains(componentBits),
      type != 4 || [2, 4, 8].contains(flagBits)
    else { throw malformed("Invalid mesh bit widths.", instruction) }
    let componentCount = functions.isEmpty ? colorSpace.description.componentCount : 1
    let decode = try PDFObjectAccess.numbers(dictionary["Decode"] ?? .null)
    guard decode.count == 4 + componentCount * 2 else { throw malformed("Invalid mesh Decode array.", instruction) }
    var reader = PDFShadingBitReader(data)
    var records: [(flag: Int, vertex: GraphicsShadingVertex)] = []
    let bitsPerRecord = flagBits + coordinateBits * 2 + componentBits * componentCount
    while reader.remainingBits >= bitsPerRecord {
      let flag = type == 4 ? Int(try reader.read(flagBits)) : 0
      let x = try reader.decode(coordinateBits, lower: decode[0], upper: decode[1])
      let y = try reader.decode(coordinateBits, lower: decode[2], upper: decode[3])
      var values: [Double] = []
      for component in 0..<componentCount {
        values.append(try reader.decode(
          componentBits,
          lower: decode[4 + component * 2],
          upper: decode[5 + component * 2]
        ))
      }
      reader.alignToByte()
      let components = functions.isEmpty ? values : try evaluate(functions, input: values)
      records.append((flag, .init(
        position: state.matrix.transform(.init(x: x, y: y)),
        paint: try colorSpace.makePaint(components)
      )))
      guard records.count <= 1_000_000 else {
        throw PDFGraphicsError.limitExceeded("PDF shading vertex limit exceeded.", location: instruction.location)
      }
    }
    guard reader.remainingBits == 0 else { throw malformed("Truncated mesh record.", instruction) }
    var result: [GraphicsShadingTriangle] = []
    if type == 4 {
      var previous: (GraphicsShadingVertex, GraphicsShadingVertex, GraphicsShadingVertex)?
      var index = 0
      while index < records.count {
        let record = records[index]
        switch record.flag {
        case 0:
          guard index + 2 < records.count else { throw malformed("Truncated free-form triangle.", instruction) }
          let triangle = (record.vertex, records[index + 1].vertex, records[index + 2].vertex)
          result.append(.init(first: triangle.0, second: triangle.1, third: triangle.2))
          previous = triangle
          index += 3
        case 1:
          guard let prior = previous else { throw malformed("Mesh continuation lacks a prior triangle.", instruction) }
          let triangle = (prior.1, prior.2, record.vertex)
          result.append(.init(first: triangle.0, second: triangle.1, third: triangle.2))
          previous = triangle
          index += 1
        case 2:
          guard let prior = previous else { throw malformed("Mesh continuation lacks a prior triangle.", instruction) }
          let triangle = (prior.0, prior.2, record.vertex)
          result.append(.init(first: triangle.0, second: triangle.1, third: triangle.2))
          previous = triangle
          index += 1
        default: throw malformed("Invalid free-form mesh flag.", instruction)
        }
      }
    } else {
      let perRow = try PDFObjectAccess.integer(dictionary["VerticesPerRow"] ?? .null)
      guard perRow >= 2, records.count.isMultiple(of: perRow), records.count / perRow >= 2 else {
        throw malformed("Invalid lattice mesh dimensions.", instruction)
      }
      let rows = stride(from: 0, to: records.count, by: perRow).map {
        Array(records[$0..<($0 + perRow)].map(\.vertex))
      }
      result = triangles(rows)
    }
    return (records.count, result)
  }

  private struct PatchData {
    let flag: Int
    let controlPoints: [GraphicsPoint]
    let colors: [[Double]]
  }

  private func patchMesh(
    type: Int,
    dictionary: [PDFName: PDFObject],
    data: Data,
    colorSpace: PDFGraphicsResourceResolver<Source>.ResolvedColorSpace,
    functions: [ColorFunction],
    instruction: PDFContentInstruction
  ) throws -> (source: [GraphicsShadingPatch], triangles: [GraphicsShadingTriangle]) {
    let coordinateBits = try PDFObjectAccess.integer(dictionary["BitsPerCoordinate"] ?? .null)
    let componentBits = try PDFObjectAccess.integer(dictionary["BitsPerComponent"] ?? .null)
    let flagBits = try PDFObjectAccess.integer(dictionary["BitsPerFlag"] ?? .null)
    guard [1, 2, 4, 8, 12, 16, 24, 32].contains(coordinateBits),
      [1, 2, 4, 8, 12, 16].contains(componentBits),
      [2, 4, 8].contains(flagBits)
    else { throw malformed("Invalid patch-mesh bit widths.", instruction) }
    let componentCount = functions.isEmpty ? colorSpace.description.componentCount : 1
    let decode = try PDFObjectAccess.numbers(dictionary["Decode"] ?? .null)
    guard decode.count == 4 + componentCount * 2 else {
      throw malformed("Invalid patch-mesh Decode array.", instruction)
    }
    var reader = PDFShadingBitReader(data)
    var decoded: [PatchData] = []
    var previous: PatchData?
    while reader.remainingBits >= flagBits {
      let flag = Int(try reader.read(flagBits))
      guard (0...3).contains(flag) else { throw malformed("Invalid patch continuation flag.", instruction) }
      let pointCount = flag == 0 ? (type == 6 ? 12 : 16) : (type == 6 ? 8 : 12)
      let colorCount = flag == 0 ? 4 : 2
      let pointBits = pointCount.multipliedReportingOverflow(by: coordinateBits * 2)
      let colorBits = colorCount.multipliedReportingOverflow(by: componentCount * componentBits)
      let required = pointBits.partialValue.addingReportingOverflow(colorBits.partialValue)
      guard !pointBits.overflow, !colorBits.overflow, !required.overflow,
        reader.remainingBits >= required.partialValue
      else { throw malformed("Truncated patch-mesh record.", instruction) }
      var points = try implicitPatchPoints(previous, flag: flag, type: type, instruction: instruction)
      for _ in 0..<pointCount {
        points.append(.init(
          x: try reader.decode(coordinateBits, lower: decode[0], upper: decode[1]),
          y: try reader.decode(coordinateBits, lower: decode[2], upper: decode[3])
        ))
      }
      var colors = try implicitPatchColors(previous, flag: flag, instruction: instruction)
      for _ in 0..<colorCount {
        var values: [Double] = []
        values.reserveCapacity(componentCount)
        for component in 0..<componentCount {
          values.append(try reader.decode(
            componentBits,
            lower: decode[4 + component * 2],
            upper: decode[5 + component * 2]
          ))
        }
        colors.append(values)
      }
      reader.alignToByte()
      let patch = PatchData(flag: flag, controlPoints: points, colors: colors)
      decoded.append(patch)
      previous = patch
      guard decoded.count <= 65_536 else {
        throw PDFGraphicsError.limitExceeded("PDF shading patch limit exceeded.", location: instruction.location)
      }
    }
    guard reader.remainingBits == 0, !decoded.isEmpty else {
      throw malformed("Truncated or empty patch mesh.", instruction)
    }

    let divisions = shadingSubdivision(smoothness: state.smoothness)
    let perPatch = divisions.multipliedReportingOverflow(by: divisions * 2)
    let total = decoded.count.multipliedReportingOverflow(by: perPatch.partialValue)
    guard !perPatch.overflow, !total.overflow, total.partialValue <= 1_000_000 else {
      throw PDFGraphicsError.limitExceeded("PDF shading triangle limit exceeded.", location: instruction.location)
    }
    var triangles: [GraphicsShadingTriangle] = []
    triangles.reserveCapacity(total.partialValue)
    for patch in decoded {
      var grid: [[GraphicsShadingVertex]] = []
      grid.reserveCapacity(divisions + 1)
      for row in 0...divisions {
        let v = Double(row) / Double(divisions)
        var vertices: [GraphicsShadingVertex] = []
        vertices.reserveCapacity(divisions + 1)
        for column in 0...divisions {
          let u = Double(column) / Double(divisions)
          let point = type == 6
            ? coonsPoint(patch.controlPoints, u: u, v: v)
            : tensorPoint(patch.controlPoints, u: u, v: v)
          let input = bilinearComponents(patch.colors, u: u, v: v)
          let components = functions.isEmpty ? input : try evaluate(functions, input: input)
          vertices.append(.init(
            position: state.matrix.transform(point),
            paint: try colorSpace.makePaint(components)
          ))
        }
        grid.append(vertices)
      }
      triangles.append(contentsOf: self.triangles(grid))
    }
    return (
      decoded.map {
        GraphicsShadingPatch(
          type: type,
          continuationFlag: $0.flag,
          controlPoints: $0.controlPoints,
          cornerComponents: $0.colors
        )
      },
      triangles
    )
  }

  private func implicitPatchPoints(
    _ previous: PatchData?,
    flag: Int,
    type: Int,
    instruction: PDFContentInstruction
  ) throws -> [GraphicsPoint] {
    guard flag != 0 else { return [] }
    guard let previous, previous.controlPoints.count == (type == 6 ? 12 : 16) else {
      throw malformed("Patch continuation lacks a prior patch.", instruction)
    }
    let indices: [Int] = switch flag {
    case 1: [3, 4, 5, 6]
    case 2: [6, 7, 8, 9]
    case 3: [9, 10, 11, 0]
    default: throw malformed("Invalid patch continuation flag.", instruction)
    }
    return indices.map { previous.controlPoints[$0] }
  }

  private func implicitPatchColors(
    _ previous: PatchData?,
    flag: Int,
    instruction: PDFContentInstruction
  ) throws -> [[Double]] {
    guard flag != 0 else { return [] }
    guard let previous, previous.colors.count == 4 else {
      throw malformed("Patch continuation lacks prior colors.", instruction)
    }
    return switch flag {
    case 1: [previous.colors[1], previous.colors[2]]
    case 2: [previous.colors[2], previous.colors[3]]
    case 3: [previous.colors[3], previous.colors[0]]
    default: throw malformed("Invalid patch continuation flag.", instruction)
    }
  }

  private func coonsPoint(_ points: [GraphicsPoint], u: Double, v: Double) -> GraphicsPoint {
    precondition(points.count == 12)
    let bottom = cubic(points[0], points[11], points[10], points[9], at: u)
    let top = cubic(points[3], points[4], points[5], points[6], at: u)
    let left = cubic(points[0], points[1], points[2], points[3], at: v)
    let right = cubic(points[9], points[8], points[7], points[6], at: v)
    let bilinear = GraphicsPoint(
      x: (1 - u) * (1 - v) * points[0].x + (1 - u) * v * points[3].x
        + u * v * points[6].x + u * (1 - v) * points[9].x,
      y: (1 - u) * (1 - v) * points[0].y + (1 - u) * v * points[3].y
        + u * v * points[6].y + u * (1 - v) * points[9].y
    )
    return .init(
      x: (1 - v) * bottom.x + v * top.x + (1 - u) * left.x + u * right.x - bilinear.x,
      y: (1 - v) * bottom.y + v * top.y + (1 - u) * left.y + u * right.y - bilinear.y
    )
  }

  private func tensorPoint(_ points: [GraphicsPoint], u: Double, v: Double) -> GraphicsPoint {
    precondition(points.count == 16)
    let storedToGrid = [0, 11, 10, 9, 1, 12, 15, 8, 2, 13, 14, 7, 3, 4, 5, 6]
    let horizontal = bernstein(u)
    let vertical = bernstein(v)
    var result = GraphicsPoint(x: 0, y: 0)
    for row in 0..<4 {
      for column in 0..<4 {
        let point = points[storedToGrid[row * 4 + column]]
        let weight = horizontal[column] * vertical[row]
        result.x += point.x * weight
        result.y += point.y * weight
      }
    }
    return result
  }

  private func cubic(
    _ first: GraphicsPoint,
    _ control1: GraphicsPoint,
    _ control2: GraphicsPoint,
    _ last: GraphicsPoint,
    at value: Double
  ) -> GraphicsPoint {
    let weights = bernstein(value)
    return .init(
      x: first.x * weights[0] + control1.x * weights[1] + control2.x * weights[2] + last.x * weights[3],
      y: first.y * weights[0] + control1.y * weights[1] + control2.y * weights[2] + last.y * weights[3]
    )
  }

  private func bernstein(_ value: Double) -> [Double] {
    let inverse = 1 - value
    return [
      inverse * inverse * inverse,
      3 * value * inverse * inverse,
      3 * value * value * inverse,
      value * value * value,
    ]
  }

  private func bilinearComponents(_ colors: [[Double]], u: Double, v: Double) -> [Double] {
    precondition(colors.count == 4)
    return colors[0].indices.map { component in
      (1 - u) * (1 - v) * colors[0][component]
        + (1 - u) * v * colors[1][component]
        + u * v * colors[2][component]
        + u * (1 - v) * colors[3][component]
    }
  }

  private func shadingSubdivision(smoothness: Double) -> Int {
    min(32, max(4, Int(ceil(1 / sqrt(max(smoothness, 1e-6))))))
  }
}
