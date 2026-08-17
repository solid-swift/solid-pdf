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
  ]

  enum NewPath: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["newpath"]

    func execute(context: isolated Context) async throws {
      try context.applyGraphicsOperation(.path(.new)) { $0.path.removeAll() }
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
      try context.applyGraphicsOperation(.path(.move(to: user))) { try $0.path.append(.move(to: device)) }
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
        try $0.path.append(.move(to: end))
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
      try context.applyGraphicsOperation(.path(.line(to: user))) { try $0.path.append(.line(to: device)) }
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
        try $0.path.append(.line(to: end))
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
        try $0.path.append(.curve(
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
        try $0.path.append(.curve(control1: control1, control2: control2, end: end))
      }
    }
  }

  enum ClosePath: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["closepath"]

    func execute(context: isolated Context) async throws {
      try context.applyGraphicsOperation(.path(.close)) {
        guard $0.path.currentPoint != nil else { return }
        try $0.path.append(.close)
      }
    }
  }
}
