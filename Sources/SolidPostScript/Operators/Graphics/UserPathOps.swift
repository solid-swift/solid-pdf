import Foundation

extension Operators {
  static let userPathOps: [OperatorValue] = [
    AppendUserPath.instance,
    CurrentUserPath.instance,
    DeclareUserPathCache.instance,
    UserFill.instance,
    UserEvenOddFill.instance,
    UserStroke.instance,
    UserStrokePath.instance,
    SetUserPathCacheParameters.instance,
    UserPathCacheStatus.instance,
  ]

  enum AppendUserPath: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["uappend"]

    func execute(context: isolated Context) async throws {
      let definition = try UserPathDecoder.decode(context.operands.pop())
      let path = try definition.materialized(matrix: context.graphicsState.matrix, roundTranslation: true)
      try context.applyGraphicsOperation(.path(.appendUserPath)) { state in
        for element in path.elements { try state.path.append(element) }
      }
    }
  }

  enum CurrentUserPath: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["upath"]

    func execute(context: isolated Context) async throws {
      let includeCache: BooleanValue = try context.operands.popAs()
      guard let inverse = context.graphicsState.matrix.inverted else { throw Error.undefinedResult }
      let path = context.graphicsState.path
      let bounds = try userBounds(state: context.graphicsState, inverse: inverse)
      var objects: [Object] = []
      objects.reserveCapacity(path.elements.count * 7 + 6)
      if includeCache.value { objects.append(.executableName("ucache")) }
      objects.append(contentsOf: try numbers([bounds.x, bounds.y, bounds.maxX, bounds.maxY]))
      objects.append(.executableName("setbbox"))
      for element in path.elements {
        switch element {
        case .move(let point):
          let point = inverse.transform(point)
          objects.append(contentsOf: try numbers([point.x, point.y]))
          objects.append(.executableName("moveto"))
        case .line(let point):
          let point = inverse.transform(point)
          objects.append(contentsOf: try numbers([point.x, point.y]))
          objects.append(.executableName("lineto"))
        case .curve(let control1, let control2, let end):
          let points = [control1, control2, end].map(inverse.transform)
          objects.append(contentsOf: try numbers(points.flatMap { [$0.x, $0.y] }))
          objects.append(.executableName("curveto"))
        case .close:
          objects.append(.executableName("closepath"))
        }
      }
      try context.limitCheck(size: objects.count, objectType: .array)
      let result = try Object.array(
        objects,
        access: .unlimited,
        vm: context.allocationMode,
        kind: .executable
      )
      try context.adopt(result)
      context.operands.push(result)
    }
  }

  enum DeclareUserPathCache: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["ucache"]

    func execute(context: isolated Context) async throws {}
  }

  enum UserFill: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["ufill"]

    func execute(context: isolated Context) async throws {
      try paintUserPath(context: context, rule: .winding)
    }
  }

  enum UserEvenOddFill: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["ueofill"]

    func execute(context: isolated Context) async throws {
      try paintUserPath(context: context, rule: .evenOdd)
    }
  }

  enum UserStroke: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["ustroke"]

    func execute(context: isolated Context) async throws {
      let optionalMatrix: GraphicsMatrix?
      if try isMatrix(context.operands.peek()) {
        optionalMatrix = try readMatrix(context.operands.pop())
      } else {
        optionalMatrix = nil
      }
      let definition = try UserPathDecoder.decode(context.operands.pop())
      let outline = try context.reducedUserPath(
        definition,
        operation: .stroke(optionalMatrix)
      )
      var paintState = context.graphicsState
      paintState.path = outline
      paintState.pathBoundingBox = nil
      try context.emitGraphicsOperation(
        .paint(.userPathStroke),
        before: paintState,
        after: context.graphicsState
      )
    }
  }

  enum UserStrokePath: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["ustrokepath"]

    func execute(context: isolated Context) async throws {
      let optionalMatrix: GraphicsMatrix?
      if try isMatrix(context.operands.peek()) {
        optionalMatrix = try readMatrix(context.operands.pop())
      } else {
        optionalMatrix = nil
      }
      let definition = try UserPathDecoder.decode(context.operands.pop())
      let outline = try context.reducedUserPath(definition, operation: .stroke(optionalMatrix))
      try context.applyGraphicsOperation(.path(.strokeOutline)) {
        $0.path = outline
        $0.pathBoundingBox = nil
      }
    }
  }

  enum SetUserPathCacheParameters: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setucacheparams"]

    func execute(context: isolated Context) async throws {
      let count = try context.operands.countToMark()
      let values = Array(try context.operands.peek(count: count))
      let limit: Int32
      if let value = values.first {
        let integer = try value.value(as: IntegerValue.self).value
        guard integer >= 0 else { throw Error.rangeCheck }
        limit = min(integer, Int32(UserPathCache.maximumItemBytes))
      } else {
        limit = Int32(UserPathCache.maximumItemBytes)
      }
      _ = try context.operands.pop(count: count + 1)
      context.userParameters.setInteger(limit, for: "MaxUPathItem")
    }
  }

  enum UserPathCacheStatus: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["ucachestatus"]

    func execute(context: isolated Context) async throws {
      let status = context.environment.userPathCache.status()
      let itemLimit = context.userParameters.integer("MaxUPathItem")
      context.operands.push(
        .integer(itemLimit),
        .integer(Int32(clamping: status.maximumEntries)),
        .integer(Int32(clamping: status.entries)),
        .integer(Int32(clamping: status.maximumBytes)),
        .integer(Int32(clamping: status.bytes)),
        .mark
      )
    }
  }

  private static func paintUserPath(
    context: isolated Context,
    rule: GraphicsFillRule
  ) throws {
    let definition = try UserPathDecoder.decode(context.operands.pop())
    let path = try context.reducedUserPath(definition, operation: .fill(rule))
    var paintState = context.graphicsState
    paintState.path = path
    paintState.pathBoundingBox = nil
    try context.emitGraphicsOperation(
      .paint(.userPathFill(rule)),
      before: paintState,
      after: context.graphicsState
    )
  }

  private static func userBounds(
    state: GraphicsCanonicalState,
    inverse: GraphicsMatrix
  ) throws -> GraphicsRect {
    if state.path.isEmpty { return GraphicsRect(x: 0, y: 0, width: 0, height: 0) }
    let deviceBounds: GraphicsRect
    if let explicit = state.pathBoundingBox {
      deviceBounds = explicit
    } else {
      let points = state.path.elements.flatMap(\.points)
      guard !points.isEmpty else { return GraphicsRect(x: 0, y: 0, width: 0, height: 0) }
      deviceBounds = .bounding(points)
    }
    return .bounding([
      GraphicsPoint(x: deviceBounds.x, y: deviceBounds.y),
      GraphicsPoint(x: deviceBounds.maxX, y: deviceBounds.y),
      GraphicsPoint(x: deviceBounds.maxX, y: deviceBounds.maxY),
      GraphicsPoint(x: deviceBounds.x, y: deviceBounds.maxY),
    ].map(inverse.transform))
  }

  private static func numbers(_ values: [Double]) throws -> [Object] {
    try values.map { try Object.real($0) }
  }

  private static func isMatrix(_ object: Object) throws -> Bool {
    guard let array = object.value as? ArrayValue else { return false }
    try array.access.check(.read)
    return array.count == 6
  }
}

extension Context {
  func reducedUserPath(
    _ definition: DecodedUserPath,
    operation: UserPathReducedOperation
  ) throws -> GraphicsPath {
    let state = graphicsState
    let originalMatrix = state.matrix
    var normalizedMatrix = originalMatrix
    normalizedMatrix.tx = 0
    normalizedMatrix.ty = 0
    let normalizedOperation: UserPathReducedOperation
    switch operation {
    case .fill:
      normalizedOperation = operation
    case .stroke(var matrix):
      matrix?.tx = 0
      matrix?.ty = 0
      normalizedOperation = .stroke(matrix)
    }
    let key = UserPathCacheKey(
      definition: definition,
      operation: normalizedOperation,
      matrix: normalizedMatrix,
      flatness: state.flatness,
      lineWidth: state.lineWidth,
      lineCap: state.lineCap,
      lineJoin: state.lineJoin,
      miterLimit: state.miterLimit,
      dash: state.dash,
      strokeAdjustment: state.strokeAdjustment,
      device: graphicsDeviceDescriptor
    )
    let build = {
      let path = try definition.materialized(matrix: normalizedMatrix, roundTranslation: true)
      switch normalizedOperation {
      case .fill:
        return try GraphicsPathGeometry.flattened(path, flatness: state.flatness)
      case .stroke(let optionalMatrix):
        let matrix = optionalMatrix?.concatenated(with: normalizedMatrix) ?? normalizedMatrix
        guard matrix.inverted != nil else { throw Error.undefinedResult }
        return try GraphicsPathGeometry.strokeOutline(path: path, state: state, matrix: matrix)
      }
    }
    let reduced = definition.cacheRequested
      ? try environment.userPathCache.path(
        for: key,
        maximumItemBytes: Int(userParameters.integer("MaxUPathItem")),
        build: build
      )
      : try build()
    var translation = GraphicsMatrix.identity
    translation.tx = originalMatrix.tx.rounded(.toNearestOrAwayFromZero)
    translation.ty = originalMatrix.ty.rounded(.toNearestOrAwayFromZero)
    return reduced.transformed(by: translation)
  }
}
