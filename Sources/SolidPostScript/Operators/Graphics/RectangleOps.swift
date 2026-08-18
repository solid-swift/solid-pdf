import Foundation

extension Operators {

  static let rectangleOps: [OperatorValue] = [
    RectangleFill.instance,
    RectangleStroke.instance,
    RectangleClip.instance,
  ]

  enum RectangleFill: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["rectfill"]

    func execute(context: isolated Context) async throws {
      let paths = try rectanglePaths(context: context)
      try context.applyGraphicsOperation(.paint(.fillRectangles(paths))) { _ in }
    }
  }

  enum RectangleStroke: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["rectstroke"]

    func execute(context: isolated Context) async throws {
      let matrix: GraphicsMatrix?
      if let candidate = try? context.operands.peek().value(as: ArrayValue.self), candidate.count == 6 {
        matrix = try readMatrix(context.operands.pop())
      } else {
        matrix = nil
      }
      let paths = try rectanglePaths(context: context)
      try context.applyGraphicsOperation(.paint(.strokeRectangles(paths: paths, matrix: matrix))) { _ in }
    }
  }

  enum RectangleClip: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["rectclip"]

    func execute(context: isolated Context) async throws {
      let paths = try rectanglePaths(context: context)
      var combined = GraphicsPath()
      for path in paths {
        for element in path.elements { try combined.append(element) }
      }
      try context.applyGraphicsOperation(.clip(.intersectRectangles(paths))) {
        $0.clip = try $0.clip.appending(GraphicsClipConstraint(path: combined, rule: .winding))
        $0.path.removeAll()
      }
    }
  }

  static func rectanglePaths(context: isolated Context) throws -> [GraphicsPath] {
    let values: [Double]
    let top = try context.operands.peek()
    switch top.value {
    case let array as ArrayValue:
      _ = try context.operands.pop()
      values = try array.objects(in: array.range).map(numeric)
    case let array as PackedArrayValue:
      _ = try context.operands.pop()
      values = try array.objects(in: array.range).map(numeric)
    case let string as StringValue:
      _ = try context.operands.pop()
      try string.access.check(.read)
      values = try EncodedNumberString.decode(string.characters(in: string.range)).map(numeric)
    default:
      let operands = try context.operands.pop(count: 4)
      values = try operands.reversed().map(numeric)
    }
    guard values.count.isMultiple(of: 4) else { throw Error.rangeCheck }
    guard values.count / 4 <= LanguageLimits.maximumPathElements / 5 else { throw Error.limitCheck }

    return try stride(from: 0, to: values.count, by: 4).map { index in
      try rectanglePath(
        x: values[index],
        y: values[index + 1],
        width: values[index + 2],
        height: values[index + 3],
        matrix: context.graphicsState.matrix
      )
    }
  }

  static func rectanglePath(
    x: Double,
    y: Double,
    width: Double,
    height: Double,
    matrix: GraphicsMatrix
  ) throws -> GraphicsPath {
    let lowerLeft = GraphicsPoint(x: x, y: y)
    let lowerRight = GraphicsPoint(x: x + width, y: y)
    let upperRight = GraphicsPoint(x: x + width, y: y + height)
    let upperLeft = GraphicsPoint(x: x, y: y + height)
    let userPoints = width * height >= 0
      ? [lowerLeft, lowerRight, upperRight, upperLeft]
      : [lowerLeft, upperLeft, upperRight, lowerRight]
    var path = GraphicsPath()
    try path.append(.move(to: matrix.transform(userPoints[0])))
    for point in userPoints.dropFirst() { try path.append(.line(to: matrix.transform(point))) }
    try path.append(.close)
    return path
  }
}
