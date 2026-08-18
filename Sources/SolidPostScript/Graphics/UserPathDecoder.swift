import Foundation

struct DecodedUserPath: Sendable, Hashable {
  enum Operation: Sendable, Hashable {
    case move(GraphicsPoint)
    case relativeMove(GraphicsPoint)
    case line(GraphicsPoint)
    case relativeLine(GraphicsPoint)
    case curve(GraphicsPoint, GraphicsPoint, GraphicsPoint)
    case relativeCurve(GraphicsPoint, GraphicsPoint, GraphicsPoint)
    case arc(center: GraphicsPoint, radius: Double, start: Double, end: Double, clockwise: Bool)
    case tangentArc(corner: GraphicsPoint, following: GraphicsPoint, radius: Double)
    case close
  }

  let cacheRequested: Bool
  let bounds: GraphicsRect
  let operations: [Operation]

  func materialized(matrix: GraphicsMatrix, roundTranslation: Bool) throws -> GraphicsPath {
    var effectiveMatrix = matrix
    if roundTranslation {
      effectiveMatrix.tx.round(.toNearestOrAwayFromZero)
      effectiveMatrix.ty.round(.toNearestOrAwayFromZero)
    }
    var userPath = GraphicsPath()
    for operation in operations {
      switch operation {
      case .move(let point):
        try userPath.append(.move(to: point))
      case .relativeMove(let delta):
        guard let current = userPath.currentPoint else { throw Error.typeCheck }
        try userPath.append(.move(to: GraphicsPoint(x: current.x + delta.x, y: current.y + delta.y)))
      case .line(let point):
        guard userPath.currentPoint != nil else { throw Error.typeCheck }
        try userPath.append(.line(to: point))
      case .relativeLine(let delta):
        guard let current = userPath.currentPoint else { throw Error.typeCheck }
        try userPath.append(.line(to: GraphicsPoint(x: current.x + delta.x, y: current.y + delta.y)))
      case .curve(let first, let second, let end):
        guard userPath.currentPoint != nil else { throw Error.typeCheck }
        try userPath.append(.curve(control1: first, control2: second, end: end))
      case .relativeCurve(let first, let second, let end):
        guard let current = userPath.currentPoint else { throw Error.typeCheck }
        try userPath.append(.curve(
          control1: GraphicsPoint(x: current.x + first.x, y: current.y + first.y),
          control2: GraphicsPoint(x: current.x + second.x, y: current.y + second.y),
          end: GraphicsPoint(x: current.x + end.x, y: current.y + end.y)
        ))
      case .arc(let center, let radius, let start, let end, let clockwise):
        guard radius >= 0 else { throw Error.rangeCheck }
        try Operators.appendArcSegments(
          to: &userPath,
          matrix: .identity,
          center: center,
          radius: radius,
          startDegrees: start,
          endDegrees: end,
          clockwise: clockwise,
          connectsToStart: true
        )
      case .tangentArc(let corner, let following, let radius):
        try appendTangentArc(
          to: &userPath,
          corner: corner,
          following: following,
          radius: radius
        )
      case .close:
        if userPath.currentPoint != nil { try userPath.append(.close) }
      }
      guard userPath.elements.allSatisfy({ $0.points.allSatisfy(bounds.contains) }) else {
        throw Error.rangeCheck
      }
    }
    return userPath.transformed(by: effectiveMatrix)
  }

  private func appendTangentArc(
    to path: inout GraphicsPath,
    corner: GraphicsPoint,
    following: GraphicsPoint,
    radius: Double
  ) throws {
    guard radius >= 0 else { throw Error.rangeCheck }
    guard let current = path.currentPoint else { throw Error.typeCheck }
    guard let incoming = normalized(current.x - corner.x, current.y - corner.y),
      let outgoing = normalized(following.x - corner.x, following.y - corner.y)
    else { throw Error.undefinedResult }
    let cross = incoming.x * outgoing.y - incoming.y * outgoing.x
    let dot = min(1, max(-1, incoming.x * outgoing.x + incoming.y * outgoing.y))
    let angle = acos(dot)
    if abs(cross) < 1e-14 || angle == 0 || abs(.pi - angle) < 1e-14 || radius == 0 {
      try path.append(.line(to: corner))
      return
    }
    let distance = radius / tan(angle / 2)
    guard distance.isFinite else { throw Error.undefinedResult }
    let first = GraphicsPoint(x: corner.x + incoming.x * distance, y: corner.y + incoming.y * distance)
    let second = GraphicsPoint(x: corner.x + outgoing.x * distance, y: corner.y + outgoing.y * distance)
    let normal = cross > 0
      ? GraphicsPoint(x: -incoming.y, y: incoming.x)
      : GraphicsPoint(x: incoming.y, y: -incoming.x)
    let center = GraphicsPoint(x: first.x + normal.x * radius, y: first.y + normal.y * radius)
    let start = atan2(first.y - center.y, first.x - center.x) * 180 / .pi
    let end = atan2(second.y - center.y, second.x - center.x) * 180 / .pi
    try path.append(.line(to: first))
    try Operators.appendArcSegments(
      to: &path,
      matrix: .identity,
      center: center,
      radius: radius,
      startDegrees: start,
      endDegrees: end,
      clockwise: cross > 0,
      connectsToStart: false
    )
  }

  private func normalized(_ x: Double, _ y: Double) -> GraphicsPoint? {
    let length = hypot(x, y)
    guard length.isFinite, length > 0 else { return nil }
    return GraphicsPoint(x: x / length, y: y / length)
  }
}

enum UserPathDecoder {
  private enum Code: UInt8 {
    case setBoundingBox = 0
    case move = 1
    case relativeMove = 2
    case line = 3
    case relativeLine = 4
    case curve = 5
    case relativeCurve = 6
    case arc = 7
    case arcNegative = 8
    case tangentArc = 9
    case close = 10
    case cache = 11
  }

  static func decode(_ object: Object) throws -> DecodedUserPath {
    let objects = try readableObjects(object)
    if objects.count == 2, objects[1].value is StringValue {
      return try decodeEncoded(data: objects[0], operators: objects[1])
    }
    return try decodeOrdinary(objects)
  }

  private static func decodeOrdinary(_ objects: [Object]) throws -> DecodedUserPath {
    var operands: [Double] = []
    var encoded: [(Code, [Double])] = []
    for object in objects {
      if let numeric = object.value as? NumericConvertible {
        guard object.kind == .literal else { throw Error.typeCheck }
        operands.append(numeric.real)
      } else {
        guard let code = code(for: object) else { throw Error.typeCheck }
        guard operands.count == operandCount(for: code) else { throw Error.typeCheck }
        encoded.append((code, operands))
        operands.removeAll(keepingCapacity: true)
      }
    }
    guard operands.isEmpty else { throw Error.typeCheck }
    return try validate(encoded)
  }

  private static func decodeEncoded(data: Object, operators: Object) throws -> DecodedUserPath {
    let numericObjects: [Object]
    switch data.value {
    case let string as StringValue:
      try string.access.check(.read)
      do {
        numericObjects = try EncodedNumberString.decode(string.characters(in: string.range))
      } catch {
        throw Error.typeCheck
      }
    default:
      numericObjects = try readableObjects(data)
    }
    let numbers = try numericObjects.map { object -> Double in
      guard object.kind == .literal, let numeric = object.value as? NumericConvertible else {
        throw Error.typeCheck
      }
      return numeric.real
    }
    let operatorString = try operators.value(as: StringValue.self)
    try operatorString.access.check(.read)
    let bytes = try operatorString.characters(in: operatorString.range)
    var expanded: [Code] = []
    var index = bytes.startIndex
    while index < bytes.endIndex {
      let byte = bytes[index]
      index = bytes.index(after: index)
      if byte > 32 {
        guard index < bytes.endIndex, let code = Code(rawValue: bytes[index]) else { throw Error.typeCheck }
        index = bytes.index(after: index)
        let count = Int(byte) - 32
        guard expanded.count <= LanguageLimits.maximumPathElements - count else { throw Error.limitCheck }
        expanded.append(contentsOf: repeatElement(code, count: count))
      } else {
        guard let code = Code(rawValue: byte) else { throw Error.typeCheck }
        expanded.append(code)
      }
    }

    var offset = 0
    let encoded = try expanded.map { code -> (Code, [Double]) in
      let count = operandCount(for: code)
      guard offset <= numbers.count - count else { throw Error.typeCheck }
      defer { offset += count }
      return (code, Array(numbers[offset..<(offset + count)]))
    }
    guard offset == numbers.count else { throw Error.typeCheck }
    return try validate(encoded)
  }

  private static func validate(_ encoded: [(Code, [Double])]) throws -> DecodedUserPath {
    var index = 0
    var cacheRequested = false
    if encoded.first?.0 == .cache {
      cacheRequested = true
      index += 1
    }
    guard index < encoded.count, encoded[index].0 == .setBoundingBox else { throw Error.typeCheck }
    let boundsOperands = encoded[index].1
    let bounds = GraphicsRect(
      x: boundsOperands[0],
      y: boundsOperands[1],
      width: boundsOperands[2] - boundsOperands[0],
      height: boundsOperands[3] - boundsOperands[1]
    )
    guard bounds.width >= 0, bounds.height >= 0 else { throw Error.rangeCheck }
    index += 1
    if index < encoded.count {
      guard encoded[index].0 == .move || encoded[index].0 == .arc || encoded[index].0 == .arcNegative else {
        throw Error.typeCheck
      }
    }
    var operations: [DecodedUserPath.Operation] = []
    operations.reserveCapacity(encoded.count - index)
    for (code, values) in encoded[index...] {
      let point: (Int) -> GraphicsPoint = { GraphicsPoint(x: values[$0], y: values[$0 + 1]) }
      switch code {
      case .move: operations.append(.move(point(0)))
      case .relativeMove: operations.append(.relativeMove(point(0)))
      case .line: operations.append(.line(point(0)))
      case .relativeLine: operations.append(.relativeLine(point(0)))
      case .curve: operations.append(.curve(point(0), point(2), point(4)))
      case .relativeCurve: operations.append(.relativeCurve(point(0), point(2), point(4)))
      case .arc:
        operations.append(.arc(center: point(0), radius: values[2], start: values[3], end: values[4], clockwise: false))
      case .arcNegative:
        operations.append(.arc(center: point(0), radius: values[2], start: values[3], end: values[4], clockwise: true))
      case .tangentArc:
        operations.append(.tangentArc(corner: point(0), following: point(2), radius: values[4]))
      case .close: operations.append(.close)
      case .cache, .setBoundingBox: throw Error.typeCheck
      }
    }
    guard operations.count <= LanguageLimits.maximumPathElements else { throw Error.limitCheck }
    return DecodedUserPath(cacheRequested: cacheRequested, bounds: bounds, operations: operations)
  }

  private static func readableObjects(_ object: Object) throws -> [Object] {
    switch object.value {
    case let array as ArrayValue:
      try array.access.check(.read)
      return try Array(array.objects(in: array.range))
    case let array as PackedArrayValue:
      try array.access.check(.read)
      return try Array(array.objects(in: array.range))
    default:
      throw Error.typeCheck
    }
  }

  private static func code(for object: Object) -> Code? {
    let name: String?
    if let value = object.value as? NameValue {
      name = value.value
    } else if let value = object.value as? any OperatorValue {
      name = value.systemDictionaryNames.first?.valueString
    } else {
      return nil
    }
    switch name {
    case "setbbox": return .setBoundingBox
    case "moveto": return .move
    case "rmoveto": return .relativeMove
    case "lineto": return .line
    case "rlineto": return .relativeLine
    case "curveto": return .curve
    case "rcurveto": return .relativeCurve
    case "arc": return .arc
    case "arcn": return .arcNegative
    case "arct": return .tangentArc
    case "closepath": return .close
    case "ucache": return .cache
    default: return nil
    }
  }

  private static func operandCount(for code: Code) -> Int {
    switch code {
    case .cache, .close: 0
    case .setBoundingBox: 4
    case .move, .relativeMove, .line, .relativeLine: 2
    case .curve, .relativeCurve: 6
    case .arc, .arcNegative, .tangentArc: 5
    }
  }
}
