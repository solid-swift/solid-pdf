import Foundation

/// The operator dialect used by a PostScript charstring program.
public enum FontCharStringDialect: Sendable, Hashable {
  /// Adobe Type 1 charstrings.
  case type1
  /// Compact Font Format Type 2 charstrings.
  case type2
}

/// A decoded charstring outline and its horizontal advance.
public struct DecodedFontCharString: Sendable, Hashable {
  /// The decoded outline.
  public let outline: FontOutline
  /// The horizontal advance in glyph coordinates.
  public let advance: FontPoint
  /// StandardEncoding components referenced by a composite Type 1 glyph.
  public let components: [FontCharStringComponent]

  /// Creates a decoded charstring result.
  public init(
    outline: FontOutline,
    advance: FontPoint,
    components: [FontCharStringComponent] = []
  ) {
    self.outline = outline
    self.advance = advance
    self.components = components
  }
}

/// Decodes bounded Type 1 and Type 2 charstring programs into portable outlines.
public enum FontCharStringDecoder {
  /// Decrypts a Type 1 charstring and removes its random prefix.
  public static func decryptType1(_ data: Data, lenIV: Int = 4) throws -> Data {
    guard lenIV >= -1 else { throw FontError.range }
    if lenIV == -1 { return data }
    var cipher = Type1CipherState(seed: Type1CipherState.charStringSeed)
    var decoded = Data(capacity: data.count)
    for byte in data {
      decoded.append(cipher.decrypt(byte))
    }
    guard decoded.count >= lenIV else { throw FontError.invalidData }
    return Data(decoded.dropFirst(lenIV))
  }

  /// Decodes one charstring with bounded local and global subroutines.
  public static func decode(
    _ data: Data,
    dialect: FontCharStringDialect,
    localSubroutines: [Data] = [],
    globalSubroutines: [Data] = [],
    defaultWidth: Double = 0,
    nominalWidth: Double = 0,
    multipleMasterWeights: [Double] = [],
    limits: FontParsingLimits = .default
  ) throws -> DecodedFontCharString {
    guard data.count <= limits.maximumDataBytes,
      localSubroutines.count <= limits.maximumObjects,
      globalSubroutines.count <= limits.maximumObjects,
      multipleMasterWeights.allSatisfy({ $0.isFinite })
    else { throw FontError.limitExceeded }
    var decoder = Decoder(
      dialect: dialect,
      localSubroutines: localSubroutines,
      globalSubroutines: globalSubroutines,
      defaultWidth: defaultWidth,
      nominalWidth: nominalWidth,
      multipleMasterWeights: multipleMasterWeights,
      limits: limits
    )
    try decoder.run(data, depth: 0)
    return DecodedFontCharString(
      outline: FontOutline(elements: decoder.elements),
      advance: FontPoint(x: decoder.width, y: decoder.verticalWidth),
      components: decoder.components
    )
  }
}

private struct Decoder {
  let dialect: FontCharStringDialect
  let localSubroutines: [Data]
  let globalSubroutines: [Data]
  let defaultWidth: Double
  let nominalWidth: Double
  let multipleMasterWeights: [Double]
  let limits: FontParsingLimits
  var stack: [Double] = []
  var elements: [FontOutline.Element] = []
  var components: [FontCharStringComponent] = []
  var point = FontPoint(x: 0, y: 0)
  var width: Double
  var verticalWidth = 0.0
  var widthSeen = false
  var stemCount = 0
  var transient = Array(repeating: 0.0, count: 32)
  var otherSubroutineResults: [Double] = []
  var randomState: UInt32 = 0x7384_1957

  init(
    dialect: FontCharStringDialect,
    localSubroutines: [Data],
    globalSubroutines: [Data],
    defaultWidth: Double,
    nominalWidth: Double,
    multipleMasterWeights: [Double],
    limits: FontParsingLimits
  ) {
    self.dialect = dialect
    self.localSubroutines = localSubroutines
    self.globalSubroutines = globalSubroutines
    self.defaultWidth = defaultWidth
    self.nominalWidth = nominalWidth
    self.multipleMasterWeights = multipleMasterWeights
    self.limits = limits
    self.width = defaultWidth
  }

  mutating func run(_ data: Data, depth: Int) throws {
    guard depth <= limits.maximumSubroutineDepth,
      elements.count <= limits.maximumOutlineElements
    else { throw FontError.limitExceeded }
    var index = data.startIndex
    while index < data.endIndex {
      let byte = data[index]
      index += 1
      if byte >= 32 || byte == 28 || byte == 255 {
        stack.append(try number(byte, data: data, index: &index))
        guard stack.count <= limits.maximumOperandStack else { throw FontError.limitExceeded }
        continue
      }
      if byte == 12 {
        guard index < data.endIndex else { throw FontError.invalidData }
        let escaped = data[index]
        index += 1
        try escapedOperator(escaped)
        continue
      }
      if byte == 11 {
        guard depth > 0 else { throw FontError.invalidData }
        return
      }
      if dialect == .type2, byte == 19 || byte == 20 {
        try consumeStems()
        let maskBytes = (stemCount + 7) / 8
        guard maskBytes <= data.distance(from: index, to: data.endIndex) else { throw FontError.invalidData }
        index += maskBytes
        continue
      }
      try operation(byte, depth: depth)
      if byte == 14 { return }
    }
  }

  mutating func operation(_ operation: UInt8, depth: Int) throws {
    switch operation {
    case 1, 3, 18, 23:
      try consumeStems()
    case 4:
      try takeWidthIfNeeded(expected: 1)
      try move(dx: 0, dy: try pop())
    case 5:
      let values = takeAll()
      guard values.count.isMultiple(of: 2) else { throw FontError.invalidData }
      for index in stride(from: 0, to: values.count, by: 2) {
        try line(dx: values[index], dy: values[index + 1])
      }
    case 6, 7:
      var horizontal = operation == 6
      for value in takeAll() {
        try line(dx: horizontal ? value : 0, dy: horizontal ? 0 : value)
        horizontal.toggle()
      }
    case 8:
      let values = takeAll()
      guard values.count.isMultiple(of: 6) else { throw FontError.invalidData }
      for index in stride(from: 0, to: values.count, by: 6) {
        try curve(Array(values[index..<index + 6]))
      }
    case 9:
      if dialect == .type1 { elements.append(.close); stack.removeAll() } else { throw FontError.invalidData }
    case 10:
      let operand = try integer(try pop())
      let index = dialect == .type2 ? operand + subroutineBias(localSubroutines.count) : operand
      guard localSubroutines.indices.contains(index) else { throw FontError.invalidData }
      try run(localSubroutines[index], depth: depth + 1)
    case 13 where dialect == .type1:
      let values = try exact(2)
      point = FontPoint(x: values[0], y: 0)
      width = values[1]
      widthSeen = true
    case 14:
      if dialect == .type2 { try takeWidthIfNeeded(expected: 0) }
      stack.removeAll()
    case 21:
      try takeWidthIfNeeded(expected: 2)
      let values = try exact(2)
      try move(dx: values[0], dy: values[1])
    case 22:
      try takeWidthIfNeeded(expected: 1)
      try move(dx: try pop(), dy: 0)
    case 24 where dialect == .type2:
      let values = takeAll()
      guard values.count >= 8, (values.count - 2).isMultiple(of: 6) else { throw FontError.invalidData }
      for start in stride(from: 0, to: values.count - 2, by: 6) {
        try curve(Array(values[start..<start + 6]))
      }
      try line(dx: values[values.count - 2], dy: values.last!)
    case 25 where dialect == .type2:
      let values = takeAll()
      guard values.count >= 8, (values.count - 6).isMultiple(of: 2) else { throw FontError.invalidData }
      for start in stride(from: 0, to: values.count - 6, by: 2) {
        try line(dx: values[start], dy: values[start + 1])
      }
      try curve(Array(values.suffix(6)))
    case 26 where dialect == .type2, 27 where dialect == .type2:
      var values = takeAll()
      let vertical = operation == 26
      var initial = 0.0
      if values.count.isMultiple(of: 2) == false { initial = values.removeFirst() }
      guard values.count.isMultiple(of: 4) else { throw FontError.invalidData }
      for start in stride(from: 0, to: values.count, by: 4) {
        let group = Array(values[start..<start + 4])
        try curve(vertical
          ? [initial, group[0], group[1], group[2], 0, group[3]]
          : [group[0], initial, group[1], group[2], group[3], 0])
        initial = 0
      }
    case 29 where dialect == .type2:
      let operand = try integer(try pop()) + subroutineBias(globalSubroutines.count)
      guard globalSubroutines.indices.contains(operand) else { throw FontError.invalidData }
      try run(globalSubroutines[operand], depth: depth + 1)
    case 30, 31:
      try alternatingCurves(startsVertical: operation == 30)
    default:
      throw FontError.unsupportedFormat
    }
  }

  mutating func escapedOperator(_ operation: UInt8) throws {
    switch (dialect, operation) {
    case (.type1, 6):
      let values = try exact(5)
      let base = try byte(values[3])
      let accent = try byte(values[4])
      components = [
        FontCharStringComponent(characterCode: base, offset: FontPoint(x: 0, y: 0)),
        FontCharStringComponent(
          characterCode: accent,
          offset: FontPoint(x: values[1] - values[0], y: values[2])
        ),
      ]
    case (.type1, 7):
      let values = try exact(4)
      point = FontPoint(x: values[0], y: values[1])
      width = values[2]
      verticalWidth = values[3]
      widthSeen = true
    case (_, 12):
      let divisor = try pop()
      let dividend = try pop()
      guard divisor != 0 else { throw FontError.invalidData }
      stack.append(dividend / divisor)
    case (.type1, 16):
      try callOtherSubroutine()
    case (.type1, 17):
      guard let value = otherSubroutineResults.popLast() else { throw FontError.invalidData }
      stack.append(value)
    case (.type1, 33):
      let values = try exact(2)
      point = FontPoint(x: values[0], y: values[1])
    case (.type2, 3):
      try binary { $0 != 0 && $1 != 0 ? 1 : 0 }
    case (.type2, 4):
      try binary { $0 != 0 || $1 != 0 ? 1 : 0 }
    case (.type2, 5):
      stack.append(try pop() == 0 ? 1 : 0)
    case (.type2, 9):
      stack.append(abs(try pop()))
    case (.type2, 10):
      try binary(+)
    case (.type2, 11):
      try binary(-)
    case (.type2, 14):
      stack.append(-(try pop()))
    case (.type2, 15):
      try binary { $0 == $1 ? 1 : 0 }
    case (.type2, 18):
      _ = try pop()
    case (.type2, 20):
      let index = try integer(try pop())
      let value = try pop()
      guard transient.indices.contains(index) else { throw FontError.invalidData }
      transient[index] = value
    case (.type2, 21):
      let index = try integer(try pop())
      guard transient.indices.contains(index) else { throw FontError.invalidData }
      stack.append(transient[index])
    case (.type2, 22):
      let second = try pop()
      let first = try pop()
      let comparison = try pop()
      let comparisonBase = try pop()
      stack.append(comparisonBase <= comparison ? first : second)
    case (.type2, 23):
      randomState = randomState &* 1_664_525 &+ 1_013_904_223
      stack.append((Double(randomState) + 1) / (Double(UInt32.max) + 2))
    case (.type2, 24):
      try binary(*)
    case (.type2, 26):
      let value = try pop()
      guard value >= 0 else { throw FontError.invalidData }
      stack.append(value.squareRoot())
    case (.type2, 27):
      guard let value = stack.last else { throw FontError.invalidData }
      stack.append(value)
    case (.type2, 28):
      let first = try pop()
      let second = try pop()
      stack.append(first)
      stack.append(second)
    case (.type2, 29):
      let index = try integer(try pop())
      guard index >= 0, index < stack.count else { throw FontError.invalidData }
      stack.append(stack[stack.count - index - 1])
    case (.type2, 30):
      let shift = try integer(try pop())
      let count = try integer(try pop())
      guard count >= 0, count <= stack.count else { throw FontError.invalidData }
      if count > 1 {
        let normalized = ((shift % count) + count) % count
        if normalized > 0 {
          let start = stack.count - count
          let values = Array(stack[start...])
          stack.replaceSubrange(start..., with: values[(count - normalized)...] + values[..<(count - normalized)])
        }
      }
    case (.type2, 34):
      let v = try exact(7)
      try curve([v[0], 0, v[1], v[2], v[3], 0])
      try curve([v[4], 0, v[5], -v[2], v[6], 0])
    case (.type2, 35):
      let v = try exact(13)
      try curve(Array(v[0..<6])); try curve(Array(v[6..<12]))
    case (.type2, 36):
      let v = try exact(9)
      try curve(Array(v[0..<6])); try curve([v[6], v[7], v[8], 0, 0, 0])
    case (.type2, 37):
      let v = try exact(11)
      let dx = v[0] + v[2] + v[4] + v[6] + v[8]
      let dy = v[1] + v[3] + v[5] + v[7] + v[9]
      let last = abs(dx) > abs(dy) ? [v[6], v[7], v[8], v[9], v[10], -dy] : [v[6], v[7], v[8], v[9], -dx, v[10]]
      try curve(Array(v[0..<6])); try curve(last)
    default:
      throw FontError.unsupportedFormat
    }
    guard stack.count <= limits.maximumOperandStack else { throw FontError.limitExceeded }
  }

  mutating func callOtherSubroutine() throws {
    let subroutine = try integer(try pop())
    let argumentCount = try integer(try pop())
    guard argumentCount >= 0, argumentCount <= stack.count else { throw FontError.invalidData }
    let arguments = Array(stack.suffix(argumentCount))
    stack.removeLast(argumentCount)
    switch subroutine {
    case 0...3:
      // Adobe flex protocol. The actual curve points remain on the Type 1
      // charstring stack and are emitted by the following setcurrentpoint.
      otherSubroutineResults = arguments.reversed()
    case 14...18:
      guard !multipleMasterWeights.isEmpty, arguments.count.isMultiple(of: multipleMasterWeights.count + 1) else {
        throw FontError.invalidData
      }
      var results: [Double] = []
      let width = multipleMasterWeights.count + 1
      for start in stride(from: 0, to: arguments.count, by: width) {
        var value = arguments[start]
        for index in multipleMasterWeights.indices {
          value += arguments[start + index + 1] * multipleMasterWeights[index]
        }
        results.append(value)
      }
      otherSubroutineResults = results.reversed()
    default:
      throw FontError.unsupportedFormat
    }
  }

  mutating func binary(_ operation: (Double, Double) -> Double) throws {
    let right = try pop()
    let left = try pop()
    let result = operation(left, right)
    guard result.isFinite else { throw FontError.invalidData }
    stack.append(result)
  }

  mutating func consumeStems() throws {
    if dialect == .type2, !widthSeen, stack.count.isMultiple(of: 2) == false {
      width = nominalWidth + stack.removeFirst(); widthSeen = true
    }
    guard stack.count.isMultiple(of: 2) else { throw FontError.invalidData }
    stemCount += stack.count / 2
    stack.removeAll()
  }

  mutating func takeWidthIfNeeded(expected: Int) throws {
    guard dialect == .type2, !widthSeen else { return }
    if stack.count == expected + 1 { width = nominalWidth + stack.removeFirst() }
    widthSeen = true
  }

  mutating func move(dx: Double, dy: Double) throws {
    point = FontPoint(x: point.x + dx, y: point.y + dy)
    elements.append(.move(point))
    stack.removeAll()
  }

  mutating func line(dx: Double, dy: Double) throws {
    point = FontPoint(x: point.x + dx, y: point.y + dy)
    elements.append(.line(point))
  }

  mutating func curve(_ v: [Double]) throws {
    guard v.count == 6 else { throw FontError.invalidData }
    let first = FontPoint(x: point.x + v[0], y: point.y + v[1])
    let second = FontPoint(x: first.x + v[2], y: first.y + v[3])
    point = FontPoint(x: second.x + v[4], y: second.y + v[5])
    elements.append(.cubic(control1: first, control2: second, end: point))
  }

  mutating func alternatingCurves(startsVertical: Bool) throws {
    let values = takeAll()
    guard values.count >= 4 else { throw FontError.invalidData }
    var vertical = startsVertical
    var offset = 0
    while offset < values.count {
      let remaining = values.count - offset
      guard remaining >= 4 else { throw FontError.invalidData }
      if vertical {
        let tail = remaining == 5 ? values[offset + 4] : 0
        try curve([0, values[offset], values[offset + 1], values[offset + 2], tail, values[offset + 3]])
      } else {
        let tail = remaining == 5 ? values[offset + 4] : 0
        try curve([values[offset], 0, values[offset + 1], values[offset + 2], values[offset + 3], tail])
      }
      offset += remaining == 5 ? 5 : 4
      vertical.toggle()
    }
  }

  mutating func pairs(_ body: (Double, Double) throws -> Void) throws {
    let values = takeAll()
    guard values.count.isMultiple(of: 2) else { throw FontError.invalidData }
    for index in stride(from: 0, to: values.count, by: 2) { try body(values[index], values[index + 1]) }
  }

  mutating func groups(of count: Int, _ body: ([Double]) throws -> Void) throws {
    let values = takeAll()
    guard values.count.isMultiple(of: count) else { throw FontError.invalidData }
    for index in stride(from: 0, to: values.count, by: count) {
      try body(Array(values[index..<index + count]))
    }
  }

  mutating func exact(_ count: Int) throws -> [Double] {
    guard stack.count == count else { throw FontError.invalidData }
    return takeAll()
  }

  mutating func pop() throws -> Double {
    guard let value = stack.popLast() else { throw FontError.invalidData }
    return value
  }
  mutating func takeAll() -> [Double] { defer { stack.removeAll(keepingCapacity: true) }; return stack }

  func subroutineBias(_ count: Int) -> Int { count < 1_240 ? 107 : count < 33_900 ? 1_131 : 32_768 }

  func integer(_ value: Double) throws -> Int {
    guard value.isFinite, value.rounded(.towardZero) == value, value >= Double(Int.min), value <= Double(Int.max) else {
      throw FontError.invalidData
    }
    return Int(value)
  }

  func byte(_ value: Double) throws -> UInt8 {
    let value = try integer(value)
    guard value >= Int(UInt8.min), value <= Int(UInt8.max) else { throw FontError.invalidData }
    return UInt8(value)
  }

  func number(_ first: UInt8, data: Data, index: inout Data.Index) throws -> Double {
    switch first {
    case 32...246: return Double(Int(first) - 139)
    case 247...250:
      guard index < data.endIndex else { throw FontError.invalidData }
      defer { index += 1 }
      return Double((Int(first) - 247) * 256 + Int(data[index]) + 108)
    case 251...254:
      guard index < data.endIndex else { throw FontError.invalidData }
      defer { index += 1 }
      return Double(-(Int(first) - 251) * 256 - Int(data[index]) - 108)
    case 28:
      guard data.distance(from: index, to: data.endIndex) >= 2 else { throw FontError.invalidData }
      let value = Int16(bitPattern: UInt16(data[index]) << 8 | UInt16(data[index + 1]))
      index += 2
      return Double(value)
    case 255:
      guard data.distance(from: index, to: data.endIndex) >= 4 else { throw FontError.invalidData }
      let bits = UInt32(data[index]) << 24 | UInt32(data[index + 1]) << 16
        | UInt32(data[index + 2]) << 8 | UInt32(data[index + 3])
      index += 4
      return dialect == .type2 ? Double(Int32(bitPattern: bits)) / 65_536 : Double(Int32(bitPattern: bits))
    default: throw FontError.invalidData
    }
  }
}
