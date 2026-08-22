import SolidPDF

final class PDFContentExecutor {
  private let parser: PDFContentParser
  private let handler: PDFContentInstructionHandler
  private let maximumOperators: Int
  private var operands: [(PDFObject, PDFContentLocation)] = []
  private var operatorCount = 0
  private var compatibilityDepth = 0
  private var markedContentDepth = 0
  private var markedContentOwners: [PDFObjectReference?] = []
  private var inTextObject = false
  private var lastLocation: PDFContentLocation?

  init(
    parser: PDFContentParser,
    handler: PDFContentInstructionHandler,
    maximumOperators: Int
  ) {
    self.parser = parser
    self.handler = handler
    self.maximumOperators = maximumOperators
  }

  func execute() async throws {
    do {
      while let token = try await parser.next() {
        lastLocation = token.location
        switch token.value {
        case .object(let object):
          operands.append((object, token.location))
        case .keyword(let name):
          try await execute(name, location: combinedLocation(through: token.location))
          operands.removeAll(keepingCapacity: true)
        }
      }
      guard operands.isEmpty else {
        throw malformed("Content stream ended with unused operands.", operatorName: nil, at: operands[0].1)
      }
      guard compatibilityDepth == 0 else {
        throw malformed("Compatibility section is not balanced.", operatorName: "BX", at: lastLocation)
      }
      guard markedContentDepth == 0 else {
        throw malformed("Marked-content sequence is not balanced.", operatorName: "BMC", at: lastLocation)
      }
      guard !inTextObject else {
        throw malformed("Text object is not balanced.", operatorName: "BT", at: lastLocation)
      }
      try await handler.finish(at: lastLocation)
      await parser.close()
    } catch {
      await parser.close()
      throw error
    }
  }

  private func execute(_ name: String, location: PDFContentLocation) async throws {
    operatorCount += 1
    guard operatorCount <= maximumOperators else {
      throw PDFGraphicsError.limitExceeded("PDF page operator limit exceeded.", location: location)
    }
    if let owner = markedContentOwners.last,
      owner != location.segments.last?.streamReference
    {
      throw malformed(
        "A marked-content sequence crosses a content-stream boundary.",
        operatorName: name,
        at: location
      )
    }
    if name == "BX" {
      try requireOperandCount(0, name: name, location: location)
      compatibilityDepth += 1
      return
    }
    if name == "EX" {
      try requireOperandCount(0, name: name, location: location)
      guard compatibilityDepth > 0 else {
        throw malformed("Compatibility section underflow.", operatorName: name, at: location)
      }
      compatibilityDepth -= 1
      return
    }
    if name == "BI" {
      try requireOperandCount(0, name: name, location: location)
      guard !inTextObject else {
        throw malformed("Inline image inside a text object.", operatorName: name, at: location)
      }
      let image = try await parser.parseInlineImage(startingAt: location) { [handler] dictionary in
        try await handler.inlineImageByteCount(dictionary: dictionary, location: location)
      }
      try await handler.executeInlineImage(image)
      return
    }
    guard Self.knownOperators.contains(name) else {
      if compatibilityDepth > 0 { return }
      throw malformed("Unknown PDF content operator.", operatorName: name, at: location)
    }
    try validateGraphicsObjectState(name, location: location)
    try validateStructuralOperator(name, location: location)
    try await handler.execute(PDFContentInstruction(
      operands: operands.map(\.0),
      name: name,
      location: location
    ))
  }

  private func validateGraphicsObjectState(_ name: String, location: PDFContentLocation) throws {
    if name == "BT" {
      guard !inTextObject else { throw malformed("Nested text object.", operatorName: name, at: location) }
      inTextObject = true
      return
    }
    if name == "ET" {
      guard inTextObject else { throw malformed("Text-object underflow.", operatorName: name, at: location) }
      inTextObject = false
      return
    }
    if Self.textOnlyOperators.contains(name), !inTextObject {
      throw malformed("Text operator outside a text object.", operatorName: name, at: location)
    }
    if Self.pageOnlyOperators.contains(name), inTextObject {
      throw malformed("Page graphics operator inside a text object.", operatorName: name, at: location)
    }
  }

  private func validateStructuralOperator(_ name: String, location: PDFContentLocation) throws {
    switch name {
    case "BMC":
      try requireOperandCount(1, name: name, location: location)
      guard case .name = operands[0].0 else {
        throw malformed("BMC tag is not a name.", operatorName: name, at: location)
      }
      markedContentDepth += 1
      markedContentOwners.append(location.segments.last?.streamReference)
    case "BDC":
      try requireOperandCount(2, name: name, location: location)
      guard case .name = operands[0].0 else {
        throw malformed("BDC tag is not a name.", operatorName: name, at: location)
      }
      switch operands[1].0 {
      case .name, .dictionary: break
      default: throw malformed("BDC properties are invalid.", operatorName: name, at: location)
      }
      markedContentDepth += 1
      markedContentOwners.append(location.segments.last?.streamReference)
    case "EMC":
      try requireOperandCount(0, name: name, location: location)
      guard markedContentDepth > 0 else {
        throw malformed("Marked-content sequence underflow.", operatorName: name, at: location)
      }
      markedContentDepth -= 1
      markedContentOwners.removeLast()
    case "MP":
      try requireOperandCount(1, name: name, location: location)
      guard case .name = operands[0].0 else {
        throw malformed("MP tag is not a name.", operatorName: name, at: location)
      }
    case "DP":
      try requireOperandCount(2, name: name, location: location)
      guard case .name = operands[0].0 else {
        throw malformed("DP tag is not a name.", operatorName: name, at: location)
      }
      switch operands[1].0 {
      case .name, .dictionary: break
      default: throw malformed("DP properties are invalid.", operatorName: name, at: location)
      }
    default: break
    }
  }

  private func requireOperandCount(
    _ count: Int,
    name: String,
    location: PDFContentLocation
  ) throws {
    guard operands.count == count else {
      throw malformed("PDF operator has the wrong operand count.", operatorName: name, at: location)
    }
  }

  private func combinedLocation(through end: PDFContentLocation) -> PDFContentLocation {
    guard let first = operands.first?.1 else { return end }
    return PDFContentLocation(
      revision: end.revision,
      pageIndex: end.pageIndex,
      pageReference: end.pageReference,
      decodedOffset: first.decodedOffset,
      segments: first.segments + end.segments,
      resourceStack: end.resourceStack
    )
  }

  private func malformed(
    _ message: String,
    operatorName: String?,
    at location: PDFContentLocation?
  ) -> PDFGraphicsError {
    let fallback = location ?? PDFContentLocation(
      revision: lastLocation!.revision,
      pageIndex: lastLocation!.pageIndex,
      pageReference: lastLocation!.pageReference,
      decodedOffset: lastLocation!.decodedOffset,
      segments: []
    )
    return .malformedContent(message: message, operatorName: operatorName, location: fallback)
  }

  private static let textOnlyOperators: Set<String> = [
    "Tc", "Tw", "Tz", "TL", "Tf", "Tr", "Ts", "Td", "TD", "Tm", "T*", "Tj", "TJ", "'", "\"",
  ]

  private static let pageOnlyOperators: Set<String> = [
    "m", "l", "c", "v", "y", "h", "re", "S", "s", "f", "F", "f*", "B", "B*", "b", "b*", "n",
    "W", "W*", "sh", "Do", "BI",
  ]

  private static let knownOperators: Set<String> = [
    "q", "Q", "cm", "w", "J", "j", "M", "d", "ri", "i", "gs",
    "m", "l", "c", "v", "y", "h", "re",
    "S", "s", "f", "F", "f*", "B", "B*", "b", "b*", "n", "W", "W*",
    "CS", "cs", "SC", "SCN", "sc", "scn", "G", "g", "RG", "rg", "K", "k",
    "sh", "Do", "BI", "ID", "EI",
    "BT", "ET", "Tc", "Tw", "Tz", "TL", "Tf", "Tr", "Ts", "Td", "TD", "Tm", "T*", "Tj", "TJ", "'", "\"",
    "d0", "d1",
    "MP", "DP", "BMC", "BDC", "EMC",
    "BX", "EX",
  ]
}
