import Foundation

struct StatementScanner {

  enum Completion: Equatable {
    case empty
    case complete
    case incomplete
    case invalid
  }

  private let bytes: [UInt8]
  private let binaryEnabled: Bool
  private var index = 0
  private var procedureDepth = 0
  private var foundToken = false
  private var terminatedByLineEnd = false

  init(data: Data, binaryEnabled: Bool) {
    self.bytes = Array(data)
    self.binaryEnabled = binaryEnabled
  }

  mutating func completion() -> Completion {
    do {
      while index < bytes.count {
        try scanNext()
      }
      guard procedureDepth == 0 else { return .incomplete }
      guard foundToken else { return .empty }
      return terminatedByLineEnd ? .complete : .incomplete
    } catch is IncompleteStatement {
      return .incomplete
    } catch {
      return .invalid
    }
  }

  mutating func expectsBinaryData() -> Bool {
    do {
      while index < bytes.count {
        try scanNext()
      }
      return false
    } catch let incomplete as IncompleteStatement {
      return incomplete.reason == .binary
    } catch {
      return false
    }
  }

  private mutating func scanNext() throws {
    let byte = bytes[index]

    if Scanner.whitespace.contains(byte) {
      if byte == Scanner.lineFeed || byte == Scanner.carriageReturn {
        terminatedByLineEnd = true
      }
      index += 1
      return
    }
    if byte == Scanner.commentDelim {
      scanComment()
      return
    }
    if binaryEnabled, (128...159).contains(byte) {
      terminatedByLineEnd = false
      try scanBinaryToken()
      return
    }

    terminatedByLineEnd = false
    switch byte {
    case Scanner.literalStringDelims.open:
      try scanLiteralString()
      foundToken = true
    case Scanner.angleDelims.close where nextByte == Scanner.angleDelims.close:
      foundToken = true
      index += 2
    case Scanner.literalStringDelims.close, Scanner.angleDelims.close:
      throw Error.syntaxError
    case Scanner.angleDelims.open:
      try scanAngleToken()
      foundToken = true
    case Scanner.char("{"):
      procedureDepth += 1
      foundToken = true
      index += 1
    case Scanner.char("}"):
      guard procedureDepth > 0 else { throw Error.syntaxError }
      procedureDepth -= 1
      index += 1
    case Scanner.ascii85Marker where nextByte == Scanner.angleDelims.close:
      throw Error.syntaxError
    case let delimiter where Scanner.arrayDelims.contains(delimiter):
      foundToken = true
      index += 1
    default:
      scanNameOrNumber()
      foundToken = true
    }
  }

  private mutating func scanComment() {
    index += 1
    while index < bytes.count {
      let byte = bytes[index]
      index += 1
      if byte == Scanner.lineFeed || byte == Scanner.formFeed {
        terminatedByLineEnd = byte == Scanner.lineFeed
        return
      }
      if byte == Scanner.carriageReturn {
        if index < bytes.count, bytes[index] == Scanner.lineFeed { index += 1 }
        terminatedByLineEnd = true
        return
      }
    }
  }

  private mutating func scanLiteralString() throws {
    var depth = 1
    index += 1

    while index < bytes.count {
      let byte = bytes[index]
      index += 1
      switch byte {
      case Scanner.literalStringDelims.open:
        depth += 1
      case Scanner.literalStringDelims.close:
        depth -= 1
        if depth == 0 { return }
      case Scanner.escapeMarker:
        guard index < bytes.count else { throw IncompleteStatement(reason: .lexical) }
        let escaped = bytes[index]
        index += 1
        if escaped == Scanner.carriageReturn, index < bytes.count, bytes[index] == Scanner.lineFeed {
          index += 1
        } else if Scanner.octalDigits.contains(escaped) {
          var remaining = 2
          while remaining > 0, index < bytes.count, Scanner.octalDigits.contains(bytes[index]) {
            index += 1
            remaining -= 1
          }
        }
      default:
        break
      }
    }
    throw IncompleteStatement(reason: .lexical)
  }

  private mutating func scanAngleToken() throws {
    guard let nextByte else { throw IncompleteStatement(reason: .lexical) }
    if nextByte == Scanner.angleDelims.open {
      index += 2
      return
    }
    if nextByte == Scanner.ascii85Marker {
      try scanAscii85String()
      return
    }
    try scanHexadecimalString()
  }

  private mutating func scanHexadecimalString() throws {
    index += 1
    while index < bytes.count {
      let byte = bytes[index]
      index += 1
      if byte == Scanner.angleDelims.close { return }
      guard Scanner.whitespace.contains(byte) || Scanner.hexDigits.contains(byte) else {
        throw Error.syntaxError
      }
    }
    throw IncompleteStatement(reason: .lexical)
  }

  private mutating func scanAscii85String() throws {
    let payloadStart = index + 2
    index = payloadStart
    var tupleLength = 0

    while index < bytes.count {
      if bytes[index] == Scanner.ascii85Marker,
        index + 1 < bytes.count,
        bytes[index + 1] == Scanner.angleDelims.close
      {
        let payload = Data(bytes[payloadStart..<index])
        guard let encoded = String(data: payload, encoding: .ascii) else { throw Error.syntaxError }
        do {
          _ = try Ascii85.decode(encoded)
        } catch {
          throw Error.syntaxError
        }
        index += 2
        return
      }
      let byte = bytes[index]
      if Scanner.whitespace.contains(byte) {
        index += 1
        continue
      }
      if byte == Scanner.char("z") {
        guard tupleLength == 0 else { throw Error.syntaxError }
        index += 1
        continue
      }
      guard (Scanner.char("!")...Scanner.char("u")).contains(byte) else {
        throw Error.syntaxError
      }
      tupleLength = (tupleLength + 1) % 5
      index += 1
    }
    throw IncompleteStatement(reason: .lexical)
  }

  private mutating func scanBinaryToken() throws {
    let data = Data(bytes[index...])
    guard let length = try BinaryTokenFraming.totalLength(of: data) else {
      throw IncompleteStatement(reason: .binary)
    }
    guard data.count >= length else { throw IncompleteStatement(reason: .binary) }
    if bytes[index] == 141, bytes[index + 1] > 1 { throw Error.syntaxError }
    index += length
    foundToken = true
  }

  private mutating func scanNameOrNumber() {
    if bytes[index] == Scanner.nameDelim {
      index += 1
      if index < bytes.count, bytes[index] == Scanner.nameDelim {
        index += 1
      }
    }
    while index < bytes.count {
      let byte = bytes[index]
      if Scanner.whitespace.contains(byte) || Self.delimiters.contains(byte) {
        return
      }
      if binaryEnabled, (128...159).contains(byte) { return }
      index += 1
    }
  }

  private var nextByte: UInt8? {
    let next = index + 1
    return next < bytes.count ? bytes[next] : nil
  }

  private static let delimiters: Set<UInt8> = [
    Scanner.literalStringDelims.open,
    Scanner.literalStringDelims.close,
    Scanner.angleDelims.open,
    Scanner.angleDelims.close,
    Scanner.char("["),
    Scanner.char("]"),
    Scanner.char("{"),
    Scanner.char("}"),
    Scanner.nameDelim,
    Scanner.commentDelim,
  ]
}

private struct IncompleteStatement: Swift.Error {
  enum Reason {
    case lexical
    case binary
  }

  let reason: Reason
}
