import Foundation
import SolidColor

extension Operators {
  static let shadingOps: [OperatorValue] = [ShadingFill.instance]

  enum ShadingFill: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["shfill"]

    func execute(context: isolated Context) async throws {
      let source = try context.operands.pop()
      let shading = try await compileShading(
        source,
        matrix: context.graphicsState.matrix,
        includeBackground: false,
        reusableDataRequired: false,
        context: context
      )
      var state = context.graphicsState
      if let bounds = shading.bounds {
        let path = try rectanglePath(
          x: bounds.x,
          y: bounds.y,
          width: bounds.width,
          height: bounds.height,
          matrix: context.graphicsState.matrix
        )
        state.clip = try state.clip.appending(.init(path: path, rule: .winding))
      }
      try context.emitGraphicsOperation(.paint(.shading(shading)), before: state, after: state)
    }
  }

  static func validateShadingDictionaryStructure(_ dictionary: DictionaryValue) throws {
    try dictionary.access.check(.read)
    let type = try dictionary.objectValue(forKey: "ShadingType", as: IntegerValue.self).value
    guard (1...7).contains(type) else { throw Error.rangeCheck }
    _ = try dictionary.object(forKey: "ColorSpace")
    if let bounds = try dictionary.object(forKeyIfExists: "BBox") {
      let values = try numericArray(bounds)
      guard values.count == 4, values.allSatisfy(\.isFinite), values[0] <= values[2], values[1] <= values[3]
      else { throw Error.rangeCheck }
    }
    if let background = try dictionary.object(forKeyIfExists: "Background") {
      _ = try numericArray(background)
    }
    _ = try dictionary.objectValue(forKeyIfExists: "AntiAlias", as: BooleanValue.self)
    switch type {
    case 1:
      _ = try dictionary.object(forKey: "Function")
    case 2, 3:
      _ = try dictionary.object(forKey: "Coords")
      _ = try dictionary.object(forKey: "Function")
    case 4:
      _ = try dictionary.object(forKey: "DataSource")
    case 5:
      _ = try dictionary.object(forKey: "DataSource")
      _ = try dictionary.objectValue(forKey: "VerticesPerRow", as: IntegerValue.self)
    case 6, 7:
      _ = try dictionary.object(forKey: "DataSource")
    default:
      preconditionFailure("Validated shading type")
    }
  }

  private struct ShadingCommon {
    let type: Int
    let colorSelection: PostScriptColorSelection
    let background: GraphicsPaint?
    let bounds: GraphicsRect?
    let antialias: Bool

    var colorSpace: PostScriptColorSpace { colorSelection.source }
  }

  private struct ShadingFunctions {
    let values: [ColorFunction]
    let inputCount: Int
    let outputCount: Int

    func evaluate(_ inputs: [Double]) throws -> [Double] {
      guard inputs.count == inputCount else { throw Error.rangeCheck }
      do {
        if values.count == 1 { return try values[0].evaluate(inputs) }
        return try values.map { function in
          let result = try function.evaluate(inputs)
          guard result.count == 1 else { throw Error.rangeCheck }
          return result[0]
        }
      } catch let error as Error {
        throw error
      } catch {
        throw Error.undefinedResult
      }
    }

    func validateDomain(_ required: ClosedRange<Double>) throws {
      guard values.allSatisfy({ function in
        function.domain.count == 1
          && function.domain[0].lowerBound <= required.lowerBound
          && function.domain[0].upperBound >= required.upperBound
      }) else { throw Error.rangeCheck }
    }
  }

  private struct ShadingVertexData {
    let position: GraphicsPoint
    let components: [Double]
  }

  private struct ShadingPatchData {
    let controlPoints: [GraphicsPoint]
    let colors: [[Double]]
  }

  static func compileShading(
    _ object: Object,
    matrix: GraphicsMatrix,
    includeBackground: Bool,
    reusableDataRequired: Bool,
    context: isolated Context
  ) async throws -> GraphicsShading {
    let dictionary = try object.value(as: DictionaryValue.self)
    try validateShadingDictionaryStructure(dictionary)
    let common = try await parseShadingCommon(
      dictionary,
      includeBackground: includeBackground,
      context: context
    )
    switch common.type {
    case 1:
      return try await compileFunctionShading(dictionary, common: common, matrix: matrix, context: context)
    case 2:
      return try await compileAxialShading(dictionary, common: common, matrix: matrix, context: context)
    case 3:
      return try await compileRadialShading(dictionary, common: common, matrix: matrix, context: context)
    case 4, 5:
      return try await compileTriangleShading(
        dictionary,
        common: common,
        matrix: matrix,
        reusableDataRequired: reusableDataRequired,
        context: context
      )
    case 6, 7:
      return try await compilePatchShading(
        dictionary,
        common: common,
        matrix: matrix,
        reusableDataRequired: reusableDataRequired,
        context: context
      )
    default:
      throw Error.rangeCheck
    }
  }

  private static func parseShadingCommon(
    _ dictionary: DictionaryValue,
    includeBackground: Bool,
    context: isolated Context
  ) async throws -> ShadingCommon {
    let type = Int(try dictionary.objectValue(forKey: "ShadingType", as: IntegerValue.self).value)
    guard (1...7).contains(type) else { throw Error.rangeCheck }
    let colorSpace = try await parseColorSpace(dictionary.object(forKey: "ColorSpace"), context: context)
    if case .pattern = colorSpace { throw Error.rangeCheck }
    let colorSelection = try await selectColorSpace(colorSpace, context: context)
    let hasFunction = try dictionary.object(forKeyIfExists: "Function") != nil
    if hasFunction, case .indexed = colorSpace { throw Error.rangeCheck }
    let background: GraphicsPaint?
    if includeBackground, let value = try dictionary.object(forKeyIfExists: "Background") {
      let components = try numericArray(value)
      guard components.count == colorSpace.componentCount else { throw Error.rangeCheck }
      background = graphicsPaint(try await resolveColor(components, in: colorSelection, context: context))
    } else {
      background = nil
    }
    let bounds = try dictionary.object(forKeyIfExists: "BBox").map { object -> GraphicsRect in
      let values = try numericArray(object)
      guard values.count == 4,
        values.allSatisfy(\.isFinite),
        values[0] <= values[2],
        values[1] <= values[3]
      else { throw Error.rangeCheck }
      return GraphicsRect(x: values[0], y: values[1], width: values[2] - values[0], height: values[3] - values[1])
    }
    let antialias = try dictionary.objectValue(forKeyIfExists: "AntiAlias", as: BooleanValue.self)?.value ?? false
    return ShadingCommon(
      type: type,
      colorSelection: colorSelection,
      background: background,
      bounds: bounds,
      antialias: antialias
    )
  }

  private static func parseShadingFunctions(
    _ object: Object,
    inputCount: Int,
    outputCount: Int,
    requiredDomain: [ClosedRange<Double>]? = nil,
    context: isolated Context
  ) async throws -> ShadingFunctions {
    let objects: [Object]
    if object.value is DictionaryValue {
      objects = [object]
    } else {
      objects = try arrayObjects(object)
    }
    guard !objects.isEmpty else { throw Error.rangeCheck }
    var functions: [ColorFunction] = []
    functions.reserveCapacity(objects.count)
    for value in objects {
      functions.append(try await parseColorFunction(value, context: context))
    }
    guard functions.allSatisfy({ $0.inputCount == inputCount }),
      (functions.count == 1 && functions[0].outputCount == outputCount)
        || (functions.count == outputCount && functions.allSatisfy { $0.outputCount == 1 })
    else { throw Error.rangeCheck }
    if let requiredDomain {
      guard requiredDomain.count == inputCount,
        functions.allSatisfy({ function in
          zip(function.domain, requiredDomain).allSatisfy { functionRange, required in
            functionRange.lowerBound <= required.lowerBound && functionRange.upperBound >= required.upperBound
          }
        })
      else { throw Error.rangeCheck }
    }
    return ShadingFunctions(values: functions, inputCount: inputCount, outputCount: outputCount)
  }

  private static func resolveShadingPaint(
    _ components: [Double],
    common: ShadingCommon,
    context: isolated Context
  ) async throws -> GraphicsPaint {
    guard components.count == common.colorSpace.componentCount else { throw Error.rangeCheck }
    return graphicsPaint(try await resolveColor(components, in: common.colorSelection, context: context))
  }

  private static func compileFunctionShading(
    _ dictionary: DictionaryValue,
    common: ShadingCommon,
    matrix: GraphicsMatrix,
    context: isolated Context
  ) async throws -> GraphicsShading {
    let domainValues = try dictionary.object(forKeyIfExists: "Domain").map(numericArray) ?? [0, 1, 0, 1]
    guard domainValues.count == 4,
      domainValues.allSatisfy(\.isFinite),
      domainValues[0] <= domainValues[1],
      domainValues[2] <= domainValues[3]
    else { throw Error.rangeCheck }
    let shadingMatrix = try dictionary.object(forKeyIfExists: "Matrix").map(readMatrix) ?? .identity
    let functions = try await parseShadingFunctions(
      dictionary.object(forKey: "Function"),
      inputCount: 2,
      outputCount: common.colorSpace.componentCount,
      requiredDomain: [domainValues[0]...domainValues[1], domainValues[2]...domainValues[3]],
      context: context
    )
    let domain = GraphicsRect(
      x: domainValues[0],
      y: domainValues[2],
      width: domainValues[1] - domainValues[0],
      height: domainValues[3] - domainValues[2]
    )
    let transform = shadingMatrix.concatenated(with: matrix)
    let divisions = shadingSubdivision(smoothness: context.graphicsState.smoothness, minimum: 4, maximum: 64)
    var vertices: [[GraphicsShadingVertex]] = []
    vertices.reserveCapacity(divisions + 1)
    for row in 0...divisions {
      var values: [GraphicsShadingVertex] = []
      values.reserveCapacity(divisions + 1)
      let y = domain.y + domain.height * Double(row) / Double(divisions)
      for column in 0...divisions {
        let x = domain.x + domain.width * Double(column) / Double(divisions)
        let paint = try await resolveShadingPaint(
          functions.evaluate([x, y]), common: common, context: context
        )
        values.append(.init(position: transform.transform(.init(x: x, y: y)), paint: paint))
      }
      vertices.append(values)
    }
    let triangles = gridTriangles(vertices)
    return GraphicsShading(
      type: 1,
      colorSpace: common.colorSpace.description,
      background: common.background,
      bounds: common.bounds,
      clipPath: try shadingClipPath(common.bounds, matrix: matrix),
      antialias: common.antialias,
      geometry: .function(domain: domain, matrix: shadingMatrix, functions: functions.values),
      mesh: .init(triangles: triangles)
    )
  }

  private static func compileAxialShading(
    _ dictionary: DictionaryValue,
    common: ShadingCommon,
    matrix: GraphicsMatrix,
    context: isolated Context
  ) async throws -> GraphicsShading {
    let coordinates = try numericArray(dictionary.object(forKey: "Coords"))
    let domain = try dictionary.object(forKeyIfExists: "Domain").map(numericArray) ?? [0, 1]
    let extend = try dictionary.object(forKeyIfExists: "Extend").map(booleanArray) ?? [false, false]
    guard coordinates.count == 4,
      coordinates.allSatisfy(\.isFinite),
      domain.count == 2,
      domain.allSatisfy(\.isFinite),
      extend.count == 2
    else { throw Error.rangeCheck }
    let functions = try await parseShadingFunctions(
      dictionary.object(forKey: "Function"),
      inputCount: 1,
      outputCount: common.colorSpace.componentCount,
      requiredDomain: [min(domain[0], domain[1])...max(domain[0], domain[1])],
      context: context
    )
    let start = GraphicsPoint(x: coordinates[0], y: coordinates[1])
    let end = GraphicsPoint(x: coordinates[2], y: coordinates[3])
    let deviceStart = matrix.transform(start)
    let deviceEnd = matrix.transform(end)
    let dx = deviceEnd.x - deviceStart.x
    let dy = deviceEnd.y - deviceStart.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared.isFinite, lengthSquared > 0 else { throw Error.rangeCheck }
    let media = context.graphicsDeviceDescriptor.mediaBounds
    let corners = [
      GraphicsPoint(x: media.x, y: media.y), GraphicsPoint(x: media.maxX, y: media.y),
      GraphicsPoint(x: media.maxX, y: media.maxY), GraphicsPoint(x: media.x, y: media.maxY),
    ]
    let projections = corners.map { (($0.x - deviceStart.x) * dx + ($0.y - deviceStart.y) * dy) / lengthSquared }
    let lower = extend[0] ? min(0, projections.min() ?? 0) : 0
    let upper = extend[1] ? max(1, projections.max() ?? 1) : 1
    let perpendicularLength = hypot(media.width, media.height) * 2 + hypot(dx, dy)
    let length = sqrt(lengthSquared)
    let normal = GraphicsPoint(x: -dy / length * perpendicularLength, y: dx / length * perpendicularLength)
    let divisions = shadingSubdivision(smoothness: context.graphicsState.smoothness, minimum: 8, maximum: 256)
    var strips: [[GraphicsShadingVertex]] = []
    strips.reserveCapacity(divisions + 1)
    for index in 0...divisions {
      let ratio = lower + (upper - lower) * Double(index) / Double(divisions)
      let clampedRatio = min(1, max(0, ratio))
      let parameter = domain[0] + (domain[1] - domain[0]) * clampedRatio
      let paint = try await resolveShadingPaint(
        functions.evaluate([parameter]), common: common, context: context
      )
      let center = GraphicsPoint(x: deviceStart.x + dx * ratio, y: deviceStart.y + dy * ratio)
      strips.append([
        .init(position: .init(x: center.x - normal.x, y: center.y - normal.y), paint: paint),
        .init(position: .init(x: center.x + normal.x, y: center.y + normal.y), paint: paint),
      ])
    }
    return GraphicsShading(
      type: 2,
      colorSpace: common.colorSpace.description,
      background: common.background,
      bounds: common.bounds,
      clipPath: try shadingClipPath(common.bounds, matrix: matrix),
      antialias: common.antialias,
      geometry: .axial(
        start: start,
        end: end,
        domainStart: domain[0],
        domainEnd: domain[1],
        extendStart: extend[0],
        extendEnd: extend[1],
        functions: functions.values
      ),
      mesh: .init(triangles: gridTriangles(strips))
    )
  }

  private static func compileRadialShading(
    _ dictionary: DictionaryValue,
    common: ShadingCommon,
    matrix: GraphicsMatrix,
    context: isolated Context
  ) async throws -> GraphicsShading {
    let coordinates = try numericArray(dictionary.object(forKey: "Coords"))
    let domain = try dictionary.object(forKeyIfExists: "Domain").map(numericArray) ?? [0, 1]
    let extend = try dictionary.object(forKeyIfExists: "Extend").map(booleanArray) ?? [false, false]
    guard coordinates.count == 6,
      coordinates.allSatisfy(\.isFinite),
      coordinates[2] >= 0,
      coordinates[5] >= 0,
      domain.count == 2,
      domain.allSatisfy(\.isFinite),
      extend.count == 2,
      coordinates[0] != coordinates[3] || coordinates[1] != coordinates[4] || coordinates[2] != coordinates[5]
    else { throw Error.rangeCheck }
    let functions = try await parseShadingFunctions(
      dictionary.object(forKey: "Function"),
      inputCount: 1,
      outputCount: common.colorSpace.componentCount,
      requiredDomain: [min(domain[0], domain[1])...max(domain[0], domain[1])],
      context: context
    )
    let start = GraphicsPoint(x: coordinates[0], y: coordinates[1])
    let end = GraphicsPoint(x: coordinates[3], y: coordinates[4])
    let startRadius = coordinates[2]
    let endRadius = coordinates[5]
    var lower = 0.0
    var upper = 1.0
    let media = context.graphicsDeviceDescriptor.mediaBounds
    let deviceScale = max(
      hypot(matrix.a, matrix.b),
      hypot(matrix.c, matrix.d),
      Double.leastNonzeroMagnitude
    )
    let targetRadius = hypot(media.width, media.height) * 2 / deviceScale
    if extend[1], endRadius != startRadius {
      upper = max(1, (targetRadius - startRadius) / (endRadius - startRadius))
      upper = min(upper, 1_024)
    }
    if extend[0], startRadius != endRadius {
      lower = min(0, (0 - startRadius) / (endRadius - startRadius))
      lower = max(lower, -1_024)
    }
    let rings = shadingSubdivision(smoothness: context.graphicsState.smoothness, minimum: 12, maximum: 128)
    let segments = max(24, min(256, rings * 2))
    var vertices: [[GraphicsShadingVertex]] = []
    vertices.reserveCapacity(rings + 1)
    for ring in 0...rings {
      let ratio = lower + (upper - lower) * Double(ring) / Double(rings)
      let radius = max(0, startRadius + (endRadius - startRadius) * ratio)
      let center = GraphicsPoint(
        x: start.x + (end.x - start.x) * ratio,
        y: start.y + (end.y - start.y) * ratio
      )
      let parameterRatio = min(1, max(0, ratio))
      let parameter = domain[0] + (domain[1] - domain[0]) * parameterRatio
      let paint = try await resolveShadingPaint(
        functions.evaluate([parameter]), common: common, context: context
      )
      vertices.append((0...segments).map { segment in
        let angle = Double(segment) / Double(segments) * 2 * Double.pi
        return GraphicsShadingVertex(
          position: matrix.transform(.init(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
          )),
          paint: paint
        )
      })
    }
    return GraphicsShading(
      type: 3,
      colorSpace: common.colorSpace.description,
      background: common.background,
      bounds: common.bounds,
      clipPath: try shadingClipPath(common.bounds, matrix: matrix),
      antialias: common.antialias,
      geometry: .radial(
        startCenter: start,
        startRadius: startRadius,
        endCenter: end,
        endRadius: endRadius,
        domainStart: domain[0],
        domainEnd: domain[1],
        extendStart: extend[0],
        extendEnd: extend[1],
        functions: functions.values
      ),
      mesh: .init(triangles: gridTriangles(vertices))
    )
  }

  private static func compileTriangleShading(
    _ dictionary: DictionaryValue,
    common: ShadingCommon,
    matrix: GraphicsMatrix,
    reusableDataRequired: Bool,
    context: isolated Context
  ) async throws -> GraphicsShading {
    let function: ShadingFunctions?
    if let functionObject = try dictionary.object(forKeyIfExists: "Function") {
      function = try await parseShadingFunctions(
        functionObject,
        inputCount: 1,
        outputCount: common.colorSpace.componentCount,
        context: context
      )
    } else {
      function = nil
    }
    let componentCount = function == nil ? common.colorSpace.componentCount : 1
    let source = try dictionary.object(forKey: "DataSource")
    let records: [(flag: Int, vertex: ShadingVertexData)]
    let functionInputRange: ClosedRange<Double>
    if source.value is ArrayValue || source.value is PackedArrayValue {
      let values = try numericArray(source)
      let recordStride = 2 + componentCount + (common.type == 4 ? 1 : 0)
      guard !values.isEmpty, values.count.isMultiple(of: recordStride) else { throw Error.rangeCheck }
      records = try Swift.stride(from: 0, to: values.count, by: recordStride).map { offset in
        let flagValue = common.type == 4 ? values[offset] : 0
        guard flagValue.isFinite, flagValue.rounded() == flagValue, (0...2).contains(flagValue)
        else { throw Error.rangeCheck }
        let flag = Int(flagValue)
        let coordinateOffset = common.type == 4 ? offset + 1 : offset
        return (
          flag,
          ShadingVertexData(
            position: .init(x: values[coordinateOffset], y: values[coordinateOffset + 1]),
            components: Array(values[(coordinateOffset + 2)..<(offset + recordStride)]).map {
              function == nil ? $0 : min(1, max(0, $0))
            }
          )
        )
      }
      functionInputRange = 0...1
    } else {
      let bitsPerCoordinate = try allowedShadingBits(
        dictionary.objectValue(forKey: "BitsPerCoordinate", as: IntegerValue.self).value,
        values: [1, 2, 4, 8, 12, 16, 24, 32]
      )
      let bitsPerComponent = try allowedShadingBits(
        dictionary.objectValue(forKey: "BitsPerComponent", as: IntegerValue.self).value,
        values: [1, 2, 4, 8, 12, 16]
      )
      let bitsPerFlag = common.type == 4
        ? try allowedShadingBits(
          dictionary.objectValue(forKey: "BitsPerFlag", as: IntegerValue.self).value,
          values: [2, 4, 8]
        )
        : 0
      let decode = try numericArray(dictionary.object(forKey: "Decode"))
      guard decode.count == 4 + componentCount * 2 else { throw Error.rangeCheck }
      functionInputRange = min(decode[4], decode[5])...max(decode[4], decode[5])
      let data = try await shadingData(
        source,
        reusableRequired: reusableDataRequired,
        context: context
      )
      var reader = ShadingBitReader(data: data)
      var decoded: [(Int, ShadingVertexData)] = []
      while reader.remainingBits >= bitsPerFlag + bitsPerCoordinate * 2 + bitsPerComponent * componentCount {
        let flag = bitsPerFlag == 0 ? 0 : try reader.read(bitsPerFlag)
        let x = try reader.decode(bitsPerCoordinate, lower: decode[0], upper: decode[1])
        let y = try reader.decode(bitsPerCoordinate, lower: decode[2], upper: decode[3])
        var components: [Double] = []
        components.reserveCapacity(componentCount)
        for index in 0..<componentCount {
          components.append(try reader.decode(
            bitsPerComponent,
            lower: decode[4 + index * 2],
            upper: decode[5 + index * 2]
          ))
        }
        reader.alignToByte()
        decoded.append((flag, .init(position: .init(x: x, y: y), components: components)))
      }
      guard reader.remainingBits == 0 else { throw Error.rangeCheck }
      records = decoded
    }
    try function?.validateDomain(functionInputRange)
    guard records.allSatisfy({ record in
      (0...2).contains(record.flag)
        && record.vertex.position.x.isFinite
        && record.vertex.position.y.isFinite
        && record.vertex.components.allSatisfy(\.isFinite)
    }) else { throw Error.rangeCheck }
    guard !records.isEmpty, records.count <= 1_000_000 else { throw Error.limitCheck }
    let rawTriangles: [(ShadingVertexData, ShadingVertexData, ShadingVertexData)]
    if common.type == 4 {
      rawTriangles = try freeFormTriangles(records)
    } else {
      let verticesPerRow = Int(try dictionary.objectValue(forKey: "VerticesPerRow", as: IntegerValue.self).value)
      guard verticesPerRow >= 2, records.count.isMultiple(of: verticesPerRow), records.count / verticesPerRow >= 2
      else { throw Error.rangeCheck }
      rawTriangles = latticeTriangles(records.map(\.vertex), verticesPerRow: verticesPerRow)
    }
    var triangles: [GraphicsShadingTriangle] = []
    triangles.reserveCapacity(rawTriangles.count)
    let subdivisionDepth: Int = switch common.colorSpace.description {
    case .deviceGray, .deviceRGB, .deviceCMYK, .indexed:
      0
    default:
      min(3, max(1, Int(ceil(-log2(max(context.graphicsState.smoothness, 1e-6)))) - 3))
    }
    let subdivisionFactor = 1 << (subdivisionDepth * 2)
    let maximumTriangleCount = rawTriangles.count.multipliedReportingOverflow(by: subdivisionFactor)
    guard !maximumTriangleCount.overflow, maximumTriangleCount.partialValue <= 1_000_000
    else { throw Error.limitCheck }
    for triangle in rawTriangles {
      triangles.append(contentsOf: try await resolvedTriangles(
        triangle,
        function: function,
        common: common,
        matrix: matrix,
        depth: subdivisionDepth,
        context: context
      ))
    }
    guard triangles.count <= 1_000_000 else { throw Error.limitCheck }
    return GraphicsShading(
      type: common.type,
      colorSpace: common.colorSpace.description,
      background: common.background,
      bounds: common.bounds,
      clipPath: try shadingClipPath(common.bounds, matrix: matrix),
      antialias: common.antialias,
      geometry: .triangles(type: common.type, vertexCount: records.count),
      mesh: .init(triangles: triangles)
    )
  }

  private static func freeFormTriangles(
    _ records: [(flag: Int, vertex: ShadingVertexData)]
  ) throws -> [(ShadingVertexData, ShadingVertexData, ShadingVertexData)] {
    var triangles: [(ShadingVertexData, ShadingVertexData, ShadingVertexData)] = []
    var index = 0
    var previous: (ShadingVertexData, ShadingVertexData, ShadingVertexData)?
    while index < records.count {
      let record = records[index]
      switch record.flag {
      case 0:
        guard index + 2 < records.count,
          records[index + 1].flag == 0,
          records[index + 2].flag == 0
        else { throw Error.rangeCheck }
        let triangle = (record.vertex, records[index + 1].vertex, records[index + 2].vertex)
        triangles.append(triangle)
        previous = triangle
        index += 3
      case 1:
        guard let prior = previous else { throw Error.rangeCheck }
        let triangle = (prior.1, prior.2, record.vertex)
        triangles.append(triangle)
        previous = triangle
        index += 1
      case 2:
        guard let prior = previous else { throw Error.rangeCheck }
        let triangle = (prior.0, prior.2, record.vertex)
        triangles.append(triangle)
        previous = triangle
        index += 1
      default:
        throw Error.rangeCheck
      }
    }
    return triangles
  }

  private static func latticeTriangles(
    _ vertices: [ShadingVertexData],
    verticesPerRow: Int
  ) -> [(ShadingVertexData, ShadingVertexData, ShadingVertexData)] {
    let rows = vertices.count / verticesPerRow
    var result: [(ShadingVertexData, ShadingVertexData, ShadingVertexData)] = []
    result.reserveCapacity((rows - 1) * (verticesPerRow - 1) * 2)
    for row in 0..<(rows - 1) {
      for column in 0..<(verticesPerRow - 1) {
        let upperLeft = vertices[row * verticesPerRow + column]
        let upperRight = vertices[row * verticesPerRow + column + 1]
        let lowerLeft = vertices[(row + 1) * verticesPerRow + column]
        let lowerRight = vertices[(row + 1) * verticesPerRow + column + 1]
        result.append((upperLeft, upperRight, lowerLeft))
        result.append((upperRight, lowerLeft, lowerRight))
      }
    }
    return result
  }

  private static func compilePatchShading(
    _ dictionary: DictionaryValue,
    common: ShadingCommon,
    matrix: GraphicsMatrix,
    reusableDataRequired: Bool,
    context: isolated Context
  ) async throws -> GraphicsShading {
    let function: ShadingFunctions?
    if let functionObject = try dictionary.object(forKeyIfExists: "Function") {
      function = try await parseShadingFunctions(
        functionObject,
        inputCount: 1,
        outputCount: common.colorSpace.componentCount,
        context: context
      )
    } else {
      function = nil
    }
    let componentCount = function == nil ? common.colorSpace.componentCount : 1
    let source = try dictionary.object(forKey: "DataSource")
    let patches: [ShadingPatchData]
    let functionInputRange: ClosedRange<Double>
    if source.value is ArrayValue || source.value is PackedArrayValue {
      let decoded = try patchesFromNumbers(
        numericArray(source),
        type: common.type,
        componentCount: componentCount
      )
      patches = function == nil ? decoded : decoded.map { patch in
        ShadingPatchData(
          controlPoints: patch.controlPoints,
          colors: patch.colors.map { $0.map { min(1, max(0, $0)) } }
        )
      }
      functionInputRange = 0...1
    } else {
      let bitsPerCoordinate = try allowedShadingBits(
        dictionary.objectValue(forKey: "BitsPerCoordinate", as: IntegerValue.self).value,
        values: [1, 2, 4, 8, 12, 16, 24, 32]
      )
      let bitsPerComponent = try allowedShadingBits(
        dictionary.objectValue(forKey: "BitsPerComponent", as: IntegerValue.self).value,
        values: [1, 2, 4, 8, 12, 16]
      )
      let bitsPerFlag = try allowedShadingBits(
        dictionary.objectValue(forKey: "BitsPerFlag", as: IntegerValue.self).value,
        values: [2, 4, 8]
      )
      let decode = try numericArray(dictionary.object(forKey: "Decode"))
      guard decode.count == 4 + componentCount * 2 else { throw Error.rangeCheck }
      functionInputRange = min(decode[4], decode[5])...max(decode[4], decode[5])
      let data = try await shadingData(
        source,
        reusableRequired: reusableDataRequired,
        context: context
      )
      patches = try patchesFromBits(
        data,
        type: common.type,
        componentCount: componentCount,
        bitsPerFlag: bitsPerFlag,
        bitsPerCoordinate: bitsPerCoordinate,
        bitsPerComponent: bitsPerComponent,
        decode: decode
      )
    }
    try function?.validateDomain(functionInputRange)
    guard patches.allSatisfy({ patch in
      patch.controlPoints.allSatisfy { $0.x.isFinite && $0.y.isFinite }
        && patch.colors.allSatisfy { $0.allSatisfy(\.isFinite) }
    }) else { throw Error.rangeCheck }
    guard !patches.isEmpty else { throw Error.rangeCheck }
    let divisions = shadingSubdivision(smoothness: context.graphicsState.smoothness, minimum: 4, maximum: 32)
    let triangleCount = patches.count.multipliedReportingOverflow(by: divisions * divisions * 2)
    guard !triangleCount.overflow, triangleCount.partialValue <= 1_000_000 else { throw Error.limitCheck }
    var triangles: [GraphicsShadingTriangle] = []
    triangles.reserveCapacity(triangleCount.partialValue)
    for patch in patches {
      var grid: [[GraphicsShadingVertex]] = []
      grid.reserveCapacity(divisions + 1)
      for row in 0...divisions {
        let v = Double(row) / Double(divisions)
        var values: [GraphicsShadingVertex] = []
        values.reserveCapacity(divisions + 1)
        for column in 0...divisions {
          let u = Double(column) / Double(divisions)
          let point = common.type == 6
            ? coonsPoint(patch.controlPoints, u: u, v: v)
            : tensorPoint(patch.controlPoints, u: u, v: v)
          let inputs = bilinearComponents(patch.colors, u: u, v: v)
          let components = try function?.evaluate(inputs) ?? inputs
          values.append(.init(
            position: matrix.transform(point),
            paint: try await resolveShadingPaint(components, common: common, context: context)
          ))
        }
        grid.append(values)
      }
      triangles.append(contentsOf: gridTriangles(grid))
    }
    return GraphicsShading(
      type: common.type,
      colorSpace: common.colorSpace.description,
      background: common.background,
      bounds: common.bounds,
      clipPath: try shadingClipPath(common.bounds, matrix: matrix),
      antialias: common.antialias,
      geometry: .patches(type: common.type, patchCount: patches.count),
      mesh: .init(triangles: triangles)
    )
  }

  private static func patchesFromNumbers(
    _ values: [Double],
    type: Int,
    componentCount: Int
  ) throws -> [ShadingPatchData] {
    var offset = 0
    var previous: ShadingPatchData?
    var result: [ShadingPatchData] = []
    while offset < values.count {
      let flagValue = values[offset]
      guard flagValue.rounded() == flagValue else { throw Error.rangeCheck }
      let flag = Int(flagValue)
      offset += 1
      let newPointCount = flag == 0 ? (type == 6 ? 12 : 16) : (type == 6 ? 8 : 12)
      let newColorCount = flag == 0 ? 4 : 2
      let required = newPointCount * 2 + newColorCount * componentCount
      guard (0...3).contains(flag), offset <= values.count - required else { throw Error.rangeCheck }
      var points = try implicitPatchPoints(previous, flag: flag, type: type)
      for _ in 0..<newPointCount {
        points.append(.init(x: values[offset], y: values[offset + 1]))
        offset += 2
      }
      var colors = try implicitPatchColors(previous, flag: flag)
      for _ in 0..<newColorCount {
        colors.append(Array(values[offset..<(offset + componentCount)]))
        offset += componentCount
      }
      let patch = ShadingPatchData(controlPoints: points, colors: colors)
      result.append(patch)
      previous = patch
    }
    return result
  }

  private static func patchesFromBits(
    _ data: Data,
    type: Int,
    componentCount: Int,
    bitsPerFlag: Int,
    bitsPerCoordinate: Int,
    bitsPerComponent: Int,
    decode: [Double]
  ) throws -> [ShadingPatchData] {
    var reader = ShadingBitReader(data: data)
    var previous: ShadingPatchData?
    var result: [ShadingPatchData] = []
    while reader.remainingBits >= bitsPerFlag {
      let flag = try reader.read(bitsPerFlag)
      guard (0...3).contains(flag) else { throw Error.rangeCheck }
      let newPointCount = flag == 0 ? (type == 6 ? 12 : 16) : (type == 6 ? 8 : 12)
      let newColorCount = flag == 0 ? 4 : 2
      let required = newPointCount * bitsPerCoordinate * 2 + newColorCount * componentCount * bitsPerComponent
      guard reader.remainingBits >= required else { throw Error.rangeCheck }
      var points = try implicitPatchPoints(previous, flag: flag, type: type)
      for _ in 0..<newPointCount {
        points.append(.init(
          x: try reader.decode(bitsPerCoordinate, lower: decode[0], upper: decode[1]),
          y: try reader.decode(bitsPerCoordinate, lower: decode[2], upper: decode[3])
        ))
      }
      var colors = try implicitPatchColors(previous, flag: flag)
      for _ in 0..<newColorCount {
        var components: [Double] = []
        for component in 0..<componentCount {
          components.append(try reader.decode(
            bitsPerComponent,
            lower: decode[4 + component * 2],
            upper: decode[5 + component * 2]
          ))
        }
        colors.append(components)
      }
      reader.alignToByte()
      let patch = ShadingPatchData(controlPoints: points, colors: colors)
      result.append(patch)
      previous = patch
    }
    guard reader.remainingBits == 0 else { throw Error.rangeCheck }
    return result
  }

  private static func implicitPatchPoints(
    _ previous: ShadingPatchData?,
    flag: Int,
    type: Int
  ) throws -> [GraphicsPoint] {
    guard flag != 0 else { return [] }
    guard let previous else { throw Error.rangeCheck }
    let indices: [Int] = switch flag {
    case 1: [3, 4, 5, 6]
    case 2: [6, 7, 8, 9]
    case 3: [9, 10, 11, 0]
    default: throw Error.rangeCheck
    }
    guard previous.controlPoints.count == (type == 6 ? 12 : 16) else { throw Error.rangeCheck }
    return indices.map { previous.controlPoints[$0] }
  }

  private static func implicitPatchColors(
    _ previous: ShadingPatchData?,
    flag: Int
  ) throws -> [[Double]] {
    guard flag != 0 else { return [] }
    guard let previous, previous.colors.count == 4 else { throw Error.rangeCheck }
    return switch flag {
    case 1: [previous.colors[1], previous.colors[2]]
    case 2: [previous.colors[2], previous.colors[3]]
    case 3: [previous.colors[3], previous.colors[0]]
    default: throw Error.rangeCheck
    }
  }

  private static func resolvedTriangle(
    _ value: (ShadingVertexData, ShadingVertexData, ShadingVertexData),
    function: ShadingFunctions?,
    common: ShadingCommon,
    matrix: GraphicsMatrix,
    context: isolated Context
  ) async throws -> GraphicsShadingTriangle {
    func vertex(_ value: ShadingVertexData) async throws -> GraphicsShadingVertex {
      let components = try function?.evaluate(value.components) ?? value.components
      return GraphicsShadingVertex(
        position: matrix.transform(value.position),
        paint: try await resolveShadingPaint(components, common: common, context: context)
      )
    }
    let first = try await vertex(value.0)
    let second = try await vertex(value.1)
    let third = try await vertex(value.2)
    return .init(first: first, second: second, third: third)
  }

  private static func resolvedTriangles(
    _ value: (ShadingVertexData, ShadingVertexData, ShadingVertexData),
    function: ShadingFunctions?,
    common: ShadingCommon,
    matrix: GraphicsMatrix,
    depth: Int,
    context: isolated Context
  ) async throws -> [GraphicsShadingTriangle] {
    guard depth > 0 else {
      return [try await resolvedTriangle(
        value,
        function: function,
        common: common,
        matrix: matrix,
        context: context
      )]
    }
    func midpoint(_ first: ShadingVertexData, _ second: ShadingVertexData) -> ShadingVertexData {
      ShadingVertexData(
        position: .init(
          x: (first.position.x + second.position.x) / 2,
          y: (first.position.y + second.position.y) / 2
        ),
        components: zip(first.components, second.components).map { ($0 + $1) / 2 }
      )
    }
    let ab = midpoint(value.0, value.1)
    let bc = midpoint(value.1, value.2)
    let ca = midpoint(value.2, value.0)
    var result: [GraphicsShadingTriangle] = []
    for child in [(value.0, ab, ca), (ab, value.1, bc), (ca, bc, value.2), (ab, bc, ca)] {
      result.append(contentsOf: try await resolvedTriangles(
        child,
        function: function,
        common: common,
        matrix: matrix,
        depth: depth - 1,
        context: context
      ))
    }
    return result
  }

  private static func gridTriangles(_ vertices: [[GraphicsShadingVertex]]) -> [GraphicsShadingTriangle] {
    guard vertices.count >= 2, let columns = vertices.first?.count, columns >= 2 else { return [] }
    var result: [GraphicsShadingTriangle] = []
    result.reserveCapacity((vertices.count - 1) * (columns - 1) * 2)
    for row in 0..<(vertices.count - 1) {
      for column in 0..<(columns - 1) {
        let upperLeft = vertices[row][column]
        let upperRight = vertices[row][column + 1]
        let lowerLeft = vertices[row + 1][column]
        let lowerRight = vertices[row + 1][column + 1]
        result.append(.init(first: upperLeft, second: upperRight, third: lowerLeft))
        result.append(.init(first: upperRight, second: lowerRight, third: lowerLeft))
      }
    }
    return result
  }

  private static func coonsPoint(_ points: [GraphicsPoint], u: Double, v: Double) -> GraphicsPoint {
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
    return GraphicsPoint(
      x: (1 - v) * bottom.x + v * top.x + (1 - u) * left.x + u * right.x - bilinear.x,
      y: (1 - v) * bottom.y + v * top.y + (1 - u) * left.y + u * right.y - bilinear.y
    )
  }

  private static func tensorPoint(_ points: [GraphicsPoint], u: Double, v: Double) -> GraphicsPoint {
    precondition(points.count == 16)
    let storedToGrid = [0, 11, 10, 9, 1, 12, 15, 8, 2, 13, 14, 7, 3, 4, 5, 6]
    let bu = bernstein(u)
    let bv = bernstein(v)
    var result = GraphicsPoint(x: 0, y: 0)
    for row in 0..<4 {
      for column in 0..<4 {
        let point = points[storedToGrid[row * 4 + column]]
        let weight = bu[row] * bv[column]
        result.x += point.x * weight
        result.y += point.y * weight
      }
    }
    return result
  }

  private static func bernstein(_ value: Double) -> [Double] {
    let inverse = 1 - value
    return [
      inverse * inverse * inverse,
      3 * value * inverse * inverse,
      3 * value * value * inverse,
      value * value * value,
    ]
  }

  private static func cubic(
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

  private static func bilinearComponents(_ colors: [[Double]], u: Double, v: Double) -> [Double] {
    precondition(colors.count == 4)
    return colors[0].indices.map { component in
      (1 - u) * (1 - v) * colors[0][component]
        + (1 - u) * v * colors[1][component]
        + u * v * colors[2][component]
        + u * (1 - v) * colors[3][component]
    }
  }

  private static func booleanArray(_ object: Object) throws -> [Bool] {
    try arrayObjects(object).map { try $0.value(as: BooleanValue.self).value }
  }

  private static func shadingClipPath(
    _ bounds: GraphicsRect?,
    matrix: GraphicsMatrix
  ) throws -> GraphicsPath? {
    guard let bounds else { return nil }
    return try rectanglePath(
      x: bounds.x,
      y: bounds.y,
      width: bounds.width,
      height: bounds.height,
      matrix: matrix
    )
  }

  private static func shadingSubdivision(smoothness: Double, minimum: Int, maximum: Int) -> Int {
    min(maximum, max(minimum, Int(ceil(1 / sqrt(max(smoothness, 1e-6))))))
  }

  private static func allowedShadingBits(_ value: Int32, values: Set<Int>) throws -> Int {
    let result = Int(value)
    guard values.contains(result) else { throw Error.rangeCheck }
    return result
  }

  private static func shadingData(
    _ object: Object,
    reusableRequired: Bool,
    context: isolated Context
  ) async throws -> Data {
    if let string = object.value as? StringValue {
      try string.access.check(.read)
      return Data(try string.characters(in: string.range))
    }
    let file = try object.value(as: FileValue.self)
    try file.checkReadable()
    if reusableRequired, !file.file.isPositionable { throw Error.invalidAccess }
    if file.file.isPositionable { try context.setLogicalOffset(0, in: file.file) }
    var data = Data()
    while let chunk = try await context.read(max: 64 * 1_024, from: file.file), !chunk.isEmpty {
      let total = data.count.addingReportingOverflow(chunk.count)
      guard !total.overflow, total.partialValue <= 64 * 1_024 * 1_024 else { throw Error.limitCheck }
      data.append(chunk)
    }
    return data
  }
}

private struct ShadingBitReader {
  let data: Data
  var bitOffset = 0

  var remainingBits: Int { data.count * 8 - bitOffset }

  mutating func read(_ count: Int) throws -> Int {
    guard count > 0, count <= 32, remainingBits >= count else { throw Error.rangeCheck }
    var result: UInt64 = 0
    for _ in 0..<count {
      let byte = data[bitOffset / 8]
      result = result << 1 | UInt64((byte >> UInt8(7 - bitOffset % 8)) & 1)
      bitOffset += 1
    }
    guard result <= UInt64(Int.max) else { throw Error.rangeCheck }
    return Int(result)
  }

  mutating func decode(_ count: Int, lower: Double, upper: Double) throws -> Double {
    let value = try read(count)
    let maximum = count == 32 ? Double(UInt32.max) : Double((1 << count) - 1)
    return lower + Double(value) / maximum * (upper - lower)
  }

  mutating func alignToByte() {
    bitOffset = (bitOffset + 7) / 8 * 8
  }
}
