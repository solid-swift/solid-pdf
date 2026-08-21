import Foundation

extension Operators {

  static let pathOps: [OperatorValue] = [
    NewPath.instance,
    CurrentPoint.instance,
    MoveTo.instance,
    RelativeMoveTo.instance,
    LineTo.instance,
    RelativeLineTo.instance,
    CurveTo.instance,
    RelativeCurveTo.instance,
    ClosePath.instance,
    SetBoundingBox.instance,
    PathBoundingBox.instance,
    PathForAll.instance,
    FlattenPath.instance,
    ReversePath.instance,
    StrokePathOutline.instance,
    CurrentClippingPath.instance,
  ]

  enum NewPath: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["newpath"]

    func execute(context: isolated Context) async throws {
      try context.applyGraphicsOperation(.path(.new)) { $0.clearPath() }
    }
  }

  enum CurrentPoint: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currentpoint"]

    func execute(context: isolated Context) async throws {
      guard let point = context.graphicsState.path.currentPoint else { throw Error.noCurrentPoint }
      guard let inverse = context.graphicsState.matrix.inverted else { throw Error.undefinedResult }
      let userPoint = inverse.transform(point)
      context.operands.push(try .real(userPoint.y), try .real(userPoint.x))
    }
  }

  enum MoveTo: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["moveto"]

    func execute(context: isolated Context) async throws {
      let operands = try context.operands.pop(count: 2)
      let user = GraphicsPoint(x: try numeric(operands[1]), y: try numeric(operands[0]))
      let device = context.graphicsState.matrix.transform(user)
      try context.applyGraphicsOperation(.path(.move(to: user))) { try $0.appendPath(.move(to: device)) }
    }
  }

  enum RelativeMoveTo: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["rmoveto"]

    func execute(context: isolated Context) async throws {
      let operands = try context.operands.pop(count: 2)
      let delta = GraphicsPoint(x: try numeric(operands[1]), y: try numeric(operands[0]))
      guard let current = context.graphicsState.path.currentPoint else { throw Error.noCurrentPoint }
      let deviceDelta = context.graphicsState.matrix.transformDistance(delta)
      let end = GraphicsPoint(x: current.x + deviceDelta.x, y: current.y + deviceDelta.y)
      try context.applyGraphicsOperation(.path(.relativeMove(dx: delta.x, dy: delta.y))) {
        try $0.appendPath(.move(to: end))
      }
    }
  }

  enum LineTo: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["lineto"]

    func execute(context: isolated Context) async throws {
      guard context.graphicsState.path.currentPoint != nil else { throw Error.noCurrentPoint }
      let operands = try context.operands.pop(count: 2)
      let user = GraphicsPoint(x: try numeric(operands[1]), y: try numeric(operands[0]))
      let device = context.graphicsState.matrix.transform(user)
      try context.applyGraphicsOperation(.path(.line(to: user))) { try $0.appendPath(.line(to: device)) }
    }
  }

  enum RelativeLineTo: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["rlineto"]

    func execute(context: isolated Context) async throws {
      let operands = try context.operands.pop(count: 2)
      let delta = GraphicsPoint(x: try numeric(operands[1]), y: try numeric(operands[0]))
      guard let current = context.graphicsState.path.currentPoint else { throw Error.noCurrentPoint }
      let deviceDelta = context.graphicsState.matrix.transformDistance(delta)
      let end = GraphicsPoint(x: current.x + deviceDelta.x, y: current.y + deviceDelta.y)
      try context.applyGraphicsOperation(.path(.relativeLine(dx: delta.x, dy: delta.y))) {
        try $0.appendPath(.line(to: end))
      }
    }
  }

  enum CurveTo: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["curveto"]

    func execute(context: isolated Context) async throws {
      guard context.graphicsState.path.currentPoint != nil else { throw Error.noCurrentPoint }
      let operands = try context.operands.pop(count: 6)
      let control1 = GraphicsPoint(x: try numeric(operands[5]), y: try numeric(operands[4]))
      let control2 = GraphicsPoint(x: try numeric(operands[3]), y: try numeric(operands[2]))
      let end = GraphicsPoint(x: try numeric(operands[1]), y: try numeric(operands[0]))
      let matrix = context.graphicsState.matrix
      try context.applyGraphicsOperation(.path(.curve(control1: control1, control2: control2, end: end))) {
        try $0.appendPath(.curve(
          control1: matrix.transform(control1),
          control2: matrix.transform(control2),
          end: matrix.transform(end)
        ))
      }
    }
  }

  enum RelativeCurveTo: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["rcurveto"]

    func execute(context: isolated Context) async throws {
      let operands = try context.operands.pop(count: 6)
      let first = GraphicsPoint(x: try numeric(operands[5]), y: try numeric(operands[4]))
      let second = GraphicsPoint(x: try numeric(operands[3]), y: try numeric(operands[2]))
      let third = GraphicsPoint(x: try numeric(operands[1]), y: try numeric(operands[0]))
      guard let current = context.graphicsState.path.currentPoint else { throw Error.noCurrentPoint }
      let matrix = context.graphicsState.matrix
      let firstDevice = matrix.transformDistance(first)
      let secondDevice = matrix.transformDistance(second)
      let thirdDevice = matrix.transformDistance(third)
      let control1 = GraphicsPoint(x: current.x + firstDevice.x, y: current.y + firstDevice.y)
      let control2 = GraphicsPoint(x: current.x + secondDevice.x, y: current.y + secondDevice.y)
      let end = GraphicsPoint(x: current.x + thirdDevice.x, y: current.y + thirdDevice.y)
      try context.applyGraphicsOperation(.path(.relativeCurve(control1: first, control2: second, end: third))) {
        try $0.appendPath(.curve(control1: control1, control2: control2, end: end))
      }
    }
  }

  enum ClosePath: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["closepath"]

    func execute(context: isolated Context) async throws {
      try context.applyGraphicsOperation(.path(.close)) {
        guard $0.path.currentPoint != nil, !$0.path.currentSubpathIsClosed else { return }
        try $0.appendPath(.close)
      }
    }
  }

  enum SetBoundingBox: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setbbox"]

    func execute(context: isolated Context) async throws {
      let operands = try context.operands.pop(count: 4)
      let lowerLeft = GraphicsPoint(x: try numeric(operands[3]), y: try numeric(operands[2]))
      let upperRight = GraphicsPoint(x: try numeric(operands[1]), y: try numeric(operands[0]))
      guard upperRight.x >= lowerLeft.x, upperRight.y >= lowerLeft.y else { throw Error.rangeCheck }
      let matrix = context.graphicsState.matrix
      let corners = [
        matrix.transform(lowerLeft),
        matrix.transform(GraphicsPoint(x: upperRight.x, y: lowerLeft.y)),
        matrix.transform(upperRight),
        matrix.transform(GraphicsPoint(x: lowerLeft.x, y: upperRight.y)),
      ]
      let bounds = GraphicsRect.bounding(corners)
      try context.applyGraphicsOperation(.path(.setBoundingBox(bounds))) { $0.pathBoundingBox = bounds }
    }
  }

  enum PathBoundingBox: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["pathbbox"]

    func execute(context: isolated Context) async throws {
      let state = context.graphicsState
      let deviceBounds: GraphicsRect
      if let explicit = state.pathBoundingBox {
        deviceBounds = explicit
      } else {
        let points = state.path.boundingPoints
        guard !points.isEmpty else { throw Error.noCurrentPoint }
        deviceBounds = GraphicsRect.bounding(points)
      }
      guard let inverse = state.matrix.inverted else { throw Error.undefinedResult }
      let corners = [
        GraphicsPoint(x: deviceBounds.x, y: deviceBounds.y),
        GraphicsPoint(x: deviceBounds.maxX, y: deviceBounds.y),
        GraphicsPoint(x: deviceBounds.maxX, y: deviceBounds.maxY),
        GraphicsPoint(x: deviceBounds.x, y: deviceBounds.maxY),
      ].map(inverse.transform)
      let bounds = GraphicsRect.bounding(corners)
      context.operands.push(
        try .real(bounds.maxY), try .real(bounds.maxX), try .real(bounds.y), try .real(bounds.x)
      )
    }
  }

  enum PathForAll: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["pathforall"]

    func execute(context: isolated Context) async throws {
      let procedures = try context.operands.pop(count: 4)
      try procedures.forEach { try $0.checkProcedure() }
      guard !context.graphicsState.pathContainsProtectedOutline else { throw Error.invalidAccess }
      guard let inverse = context.graphicsState.matrix.inverted else { throw Error.undefinedResult }
      let path = context.graphicsState.path
      try await context.executeLoop(named: "pathforall") {
        for element in path.elements {
          switch element {
          case .move(let point):
            let point = inverse.transform(point)
            try await context.execute(proc: procedures[3], ops: [try .real(point.x), try .real(point.y)])
          case .line(let point):
            let point = inverse.transform(point)
            try await context.execute(proc: procedures[2], ops: [try .real(point.x), try .real(point.y)])
          case .curve(let control1, let control2, let end):
            let points = [control1, control2, end].map(inverse.transform)
            try await context.execute(proc: procedures[1], ops: try points.flatMap {
              [try Object.real($0.x), try Object.real($0.y)]
            })
          case .close:
            try await context.execute(proc: procedures[0])
          }
        }
      }
    }
  }

  enum FlattenPath: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["flattenpath"]

    func execute(context: isolated Context) async throws {
      let path = try GraphicsPathGeometry.flattened(
        context.graphicsState.path,
        flatness: context.graphicsState.flatness
      )
      try context.applyGraphicsOperation(.path(.flatten)) { $0.path = path }
    }
  }

  enum ReversePath: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["reversepath"]

    func execute(context: isolated Context) async throws {
      let path = try context.graphicsState.path.reversedPath()
      try context.applyGraphicsOperation(.path(.reverse)) { $0.path = path }
    }
  }

  enum StrokePathOutline: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["strokepath"]

    func execute(context: isolated Context) async throws {
      let outline = try GraphicsPathGeometry.strokeOutline(
        path: context.graphicsState.path,
        state: context.graphicsState
      )
      try context.applyGraphicsOperation(.path(.strokeOutline)) {
        $0.path = outline
        $0.pathBoundingBox = nil
      }
    }
  }

  enum CurrentClippingPath: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["clippath"]

    func execute(context: isolated Context) async throws {
      let path = try GraphicsPathGeometry.clippingPath(context.graphicsState.resolvedClip)
      try context.applyGraphicsOperation(.path(.clippingPath)) {
        $0.path = path
        $0.pathBoundingBox = nil
        $0.pathContainsProtectedOutline = false
      }
    }
  }
}
