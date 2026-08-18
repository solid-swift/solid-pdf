import Foundation

extension Operators {

  static let arcOps: [OperatorValue] = [
    Arc.instance,
    ArcNegative.instance,
    TangentArc.instance,
    ArcTangentReturning.instance,
  ]

  enum Arc: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["arc"]

    func execute(context: isolated Context) async throws {
      let operands = try context.operands.pop(count: 5)
      let center = GraphicsPoint(x: try numeric(operands[4]), y: try numeric(operands[3]))
      let radius = try numeric(operands[2])
      let start = try numeric(operands[1])
      let end = try numeric(operands[0])
      guard radius >= 0 else { throw Error.rangeCheck }
      try appendArc(
        context: context,
        operation: .arc(center: center, radius: radius, startDegrees: start, endDegrees: end),
        center: center,
        radius: radius,
        startDegrees: start,
        endDegrees: end,
        clockwise: false
      )
    }
  }

  enum ArcNegative: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["arcn"]

    func execute(context: isolated Context) async throws {
      let operands = try context.operands.pop(count: 5)
      let center = GraphicsPoint(x: try numeric(operands[4]), y: try numeric(operands[3]))
      let radius = try numeric(operands[2])
      let start = try numeric(operands[1])
      let end = try numeric(operands[0])
      guard radius >= 0 else { throw Error.rangeCheck }
      try appendArc(
        context: context,
        operation: .arcNegative(center: center, radius: radius, startDegrees: start, endDegrees: end),
        center: center,
        radius: radius,
        startDegrees: start,
        endDegrees: end,
        clockwise: true
      )
    }
  }

  enum TangentArc: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["arct"]

    func execute(context: isolated Context) async throws {
      _ = try appendTangentArc(context: context)
    }
  }

  enum ArcTangentReturning: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["arcto"]

    func execute(context: isolated Context) async throws {
      let tangents = try appendTangentArc(context: context)
      context.operands.push(
        try .real(tangents.second.y),
        try .real(tangents.second.x),
        try .real(tangents.first.y),
        try .real(tangents.first.x)
      )
    }
  }

  static func appendTangentArc(
    context: isolated Context
  ) throws -> (first: GraphicsPoint, second: GraphicsPoint) {
    guard let currentDevice = context.graphicsState.path.currentPoint else { throw Error.noCurrentPoint }
    guard let inverse = context.graphicsState.matrix.inverted else { throw Error.undefinedResult }
    let current = inverse.transform(currentDevice)
    let operands = try context.operands.pop(count: 5)
    let corner = GraphicsPoint(x: try numeric(operands[4]), y: try numeric(operands[3]))
    let following = GraphicsPoint(x: try numeric(operands[2]), y: try numeric(operands[1]))
    let radius = try numeric(operands[0])
    guard radius >= 0 else { throw Error.rangeCheck }

    let incoming = normalized(x: current.x - corner.x, y: current.y - corner.y)
    let outgoing = normalized(x: following.x - corner.x, y: following.y - corner.y)
    guard let incoming, let outgoing else { throw Error.undefinedResult }
    let cross = incoming.x * outgoing.y - incoming.y * outgoing.x
    let dot = min(1, max(-1, incoming.x * outgoing.x + incoming.y * outgoing.y))
    let angle = acos(dot)

    let first: GraphicsPoint
    let second: GraphicsPoint
    if abs(cross) < 1e-14 || angle == 0 || abs(.pi - angle) < 1e-14 || radius == 0 {
      first = corner
      second = corner
      try context.applyGraphicsOperation(.path(.arcTo(corner: corner, following: following, radius: radius))) {
        try $0.path.append(.line(to: $0.matrix.transform(corner)))
      }
      return (first, second)
    }

    let distance = radius / tan(angle / 2)
    guard distance.isFinite else { throw Error.undefinedResult }
    first = GraphicsPoint(x: corner.x + incoming.x * distance, y: corner.y + incoming.y * distance)
    second = GraphicsPoint(x: corner.x + outgoing.x * distance, y: corner.y + outgoing.y * distance)
    let normal = cross > 0
      ? GraphicsPoint(x: -incoming.y, y: incoming.x)
      : GraphicsPoint(x: incoming.y, y: -incoming.x)
    let center = GraphicsPoint(x: first.x + normal.x * radius, y: first.y + normal.y * radius)
    let start = atan2(first.y - center.y, first.x - center.x) * 180 / .pi
    let end = atan2(second.y - center.y, second.x - center.x) * 180 / .pi
    let clockwise = cross > 0

    try context.applyGraphicsOperation(.path(.arcTo(corner: corner, following: following, radius: radius))) { state in
      try state.path.append(.line(to: state.matrix.transform(first)))
      try appendArcSegments(
        to: &state.path,
        matrix: state.matrix,
        center: center,
        radius: radius,
        startDegrees: start,
        endDegrees: end,
        clockwise: clockwise,
        connectsToStart: false
      )
    }
    return (first, second)
  }

  static func appendArc(
    context: isolated Context,
    operation: GraphicsOperation.Path,
    center: GraphicsPoint,
    radius: Double,
    startDegrees: Double,
    endDegrees: Double,
    clockwise: Bool
  ) throws {
    try context.applyGraphicsOperation(.path(operation)) { state in
      try appendArcSegments(
        to: &state.path,
        matrix: state.matrix,
        center: center,
        radius: radius,
        startDegrees: startDegrees,
        endDegrees: endDegrees,
        clockwise: clockwise,
        connectsToStart: true
      )
    }
  }

  static func appendArcSegments(
    to path: inout GraphicsPath,
    matrix: GraphicsMatrix,
    center: GraphicsPoint,
    radius: Double,
    startDegrees: Double,
    endDegrees: Double,
    clockwise: Bool,
    connectsToStart: Bool
  ) throws {
    var sweep = endDegrees - startDegrees
    if clockwise {
      while sweep > 0 { sweep -= 360 }
    } else {
      while sweep < 0 { sweep += 360 }
    }
    guard sweep.isFinite else { throw Error.rangeCheck }
    let requiredSegments = max(1, ceil(abs(sweep) / 90))
    guard requiredSegments <= Double(LanguageLimits.maximumPathElements - path.elements.count) else {
      throw Error.limitCheck
    }
    let segmentCount = Int(requiredSegments)
    let segmentSweep = sweep / Double(segmentCount)
    let startRadians = startDegrees * .pi / 180
    let startPoint = point(onCircle: center, radius: radius, radians: startRadians)
    if connectsToStart {
      try path.append(path.currentPoint == nil ? .move(to: matrix.transform(startPoint)) : .line(to: matrix.transform(startPoint)))
    }

    for index in 0..<segmentCount {
      let angle0 = startRadians + Double(index) * segmentSweep * .pi / 180
      let angle1 = angle0 + segmentSweep * .pi / 180
      let coefficient = 4 / 3 * tan((angle1 - angle0) / 4)
      let point0 = point(onCircle: center, radius: radius, radians: angle0)
      let point1 = point(onCircle: center, radius: radius, radians: angle1)
      let control1 = GraphicsPoint(
        x: point0.x - coefficient * radius * sin(angle0),
        y: point0.y + coefficient * radius * cos(angle0)
      )
      let control2 = GraphicsPoint(
        x: point1.x + coefficient * radius * sin(angle1),
        y: point1.y - coefficient * radius * cos(angle1)
      )
      try path.append(.curve(
        control1: matrix.transform(control1),
        control2: matrix.transform(control2),
        end: matrix.transform(point1)
      ))
    }
  }

  private static func point(onCircle center: GraphicsPoint, radius: Double, radians: Double) -> GraphicsPoint {
    GraphicsPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
  }

  private static func normalized(x: Double, y: Double) -> GraphicsPoint? {
    let length = hypot(x, y)
    guard length.isFinite, length > 0 else { return nil }
    return GraphicsPoint(x: x / length, y: y / length)
  }
}
