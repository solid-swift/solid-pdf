//
//  Scanner.swift
//
//
//  Created by Kevin Wooten on 6/25/24.
//

import Foundation
import SolidCore

/// A scanner that converts PostScript source bytes into tokens.
public class Scanner {

  enum Lexeme {
    case token(Token)
    case binary(UInt8)
    case procedureOpen
    case procedureClose
    case unmatchedClose(Chars)
  }

  typealias Char = UInt8
  typealias Chars = [UInt8]
  typealias CharSet = Set<Char>
  typealias DelimChars = (open: Char, close: Char)

  static func char(_ ch: Character) -> Char { ch.asciiValue.neverNil() }
  static func chars(_ chs: [Character]) -> Chars { Array(chs.map { $0.asciiValue.neverNil() }) }
  static func charSet(_ chs: Character...) -> CharSet { Set(chars(chs)) }
  static func delims(_ open: Character, _ close: Character) -> DelimChars { (char(open), char(close)) }

  static let null: Char = 0x00
  static let backSpace: Char = 0x08
  static let tab: Char = 0x09
  static let lineFeed: Char = 0x0A
  static let formFeed: Char = 0x0C
  static let carriageReturn: Char = 0x0D
  static let space: Char = 0x20
  static let whitespace: CharSet = [null, tab, lineFeed, formFeed, carriageReturn, space]
  static let octalDigits = charSet("0", "1", "2", "3", "4", "5", "6", "7")
  static let decimalDigits = charSet("0", "1", "2", "3", "4", "5", "6", "7", "8", "9")
  static let hexDigits = decimalDigits.union(charSet("a", "b", "c", "d", "e", "f", "A", "B", "C", "D", "E", "F"))
  static let escapes: (lineFeed: Char, carriageReturn: Char, tab: Char, backSpace: Char, formFeed: Char) =
    (char("n"), char("r"), char("t"), char("b"), char("f"))

  static let literalStringDelims = delims("(", ")")
  static let escapeMarker: Char = char("\\")
  static let literalStringSpecialCharSet: CharSet = [
    literalStringDelims.open,
    literalStringDelims.close,
    escapeMarker,
    char("\r"),
  ]

  static let angleDelims = delims("<", ">")
  static let ascii85Marker = char("~")

  static let arrayDelims = charSet("[", "]")
  static let procedureDelims = charSet("{", "}")
  static let nameDelim = char("/")
  static let commentDelim = char("%")
  static let zero = char("0")
  // Regex is immutable after initialization, but Regex is not declared Sendable.
  nonisolated(unsafe) static let radixRegex = neverThrow(
    "Invalid regular expression pattern",
    try Regex(#"([0-9]{1,2})#([0-9a-zA-Z]+)"#)
  )
  // Regex is immutable after initialization, but Regex is not declared Sendable.
  nonisolated(unsafe) static let decimalIntegerRegex = neverThrow(
    "Invalid regular expression pattern",
    try Regex(#"[+-]?[0-9]+"#)
  )
  // Regex is immutable after initialization, but Regex is not declared Sendable.
  nonisolated(unsafe) static let realRegex = neverThrow(
    "Invalid regular expression pattern",
    try Regex(#"[+-]?(?:[0-9]+\.[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?|[+-]?[0-9]+[eE][+-]?[0-9]+"#)
  )

  /// The ``file`` value.
  public let file: File
  private var pushback: [Char] = []
  private var history: [Char] = []
  private var contextualInput: [Char]?
  private var contextualOffset = 0
  private var contextualEOF = false

  /// Creates an instance.
  public convenience init(content: Data) throws {
    try self.init(file: DataFile(data: content, mode: .read))
  }

  /// Creates an instance.
  public init(file: File) throws {
    self.file = file
  }

  /// Returns the next context-free lexical token.
  ///
  /// Procedure construction requires interpreter allocation and packing state, so it is performed by the
  /// context-aware scanner used during execution.
  public func nextToken() throws -> Token? {
    guard let lexeme = try nextLexeme(binaryEnabled: false) else {
      return nil
    }
    switch lexeme {
    case .token(let token):
      return token
    case .procedureOpen:
      return .name("{", kind: .executable)
    case .procedureClose:
      return .name("}", kind: .executable)
    case .unmatchedClose(let chars):
      return try .name(String(bytes: chars, encoding: .isoLatin1).unwrap(), kind: .executable)
    case .binary:
      throw Error.unregistered(.internalScannerError)
    }
  }

  func nextContextualObject(context: isolated Context) async throws -> ScannedObject? {
    let savedPushback = pushback
    let savedHistory = history
    var input: [Char] = []
    var reachedEOF = false

    while true {
      pushback = savedPushback
      history = savedHistory
      contextualInput = input
      contextualOffset = 0
      contextualEOF = reachedEOF

      do {
        let object = try nextObject(context: context)
        returnContextualLookahead(to: context)
        contextualInput = nil
        contextualOffset = 0
        contextualEOF = false
        return object
      } catch is ScannerInputRequired {
        do {
          if let byte = try await file.readByte(context: context) {
            input.append(byte)
          } else {
            reachedEOF = true
          }
        } catch {
          returnContextualLookahead(to: context)
          contextualInput = nil
          contextualOffset = 0
          contextualEOF = false
          throw error
        }
      } catch {
        returnContextualLookahead(to: context)
        contextualInput = nil
        contextualOffset = 0
        contextualEOF = false
        throw error
      }
    }
  }

  func nextLexeme(binaryEnabled: Bool) throws -> Lexeme? {

    var chars: [Char] = []

    while true {

      guard let char = try next() else {
        return try token(chars, putBack: 0).map(Lexeme.token)
      }

      if binaryEnabled && (128...159).contains(char) {
        if let token = try token(chars) {
          return .token(token)
        }
        return .binary(char)
      }

      switch char {
      case Self.whitespace:
        if !chars.isEmpty {
          if contextualInput != nil {
            if char == Self.carriageReturn, try peek() == Self.lineFeed {
              try skip()
            }
            return .token(try token(chars, putBack: 0).neverNil())
          }
          return .token(try token(chars).neverNil())
        }
        try skip(while: Self.whitespace.contains)

      case Self.literalStringDelims.open:
        return try token(chars).map(Lexeme.token) ?? .token(literalString())

      case Self.angleDelims.open where try peek() == Self.angleDelims.open,
        Self.angleDelims.close where try peek() == Self.angleDelims.close:
        return try token(chars).map(Lexeme.token) ?? .token(token([char] + take(1), putBack: 0).neverNil())

      case Self.angleDelims.open:
        return try token(chars).map(Lexeme.token) ?? .token(encodedString())

      case Self.literalStringDelims.close, Self.angleDelims.close:
        return try token(chars).map(Lexeme.token) ?? .unmatchedClose([char])

      case Self.procedureDelims:
        if let token = try token(chars) {
          return .token(token)
        }
        return char == Self.char("{") ? .procedureOpen : .procedureClose

      case Self.arrayDelims:
        return try token(chars).map(Lexeme.token) ?? .token(name(char))

      case Self.nameDelim:
        if let token = try token(chars) {
          return .token(token)
        }

        chars.append(char)

        if try peek() == Self.nameDelim {
          chars.append(Self.nameDelim)
          try skip()
        }

      case Self.commentDelim:
        if !chars.isEmpty {
          if contextualInput != nil {
            try rewind()
            return .token(try token(chars, putBack: 0).neverNil())
          }
          try comment()
          return .token(try token(chars, putBack: 0).neverNil())
        }
        try comment()

      case Self.ascii85Marker where try peek() == Self.angleDelims.close:
        if let token = try token(chars) {
          return .token(token)
        }
        try skip()
        return .unmatchedClose([char, Self.angleDelims.close])

      default:
        chars.append(char)
      }
    }

    func token(_ chars: [Char], putBack: Int = 1) throws -> Token? {
      guard let firstChar = chars.first else {
        return nil
      }

      if putBack > 0 {
        try rewind(count: putBack)
      }

      if firstChar == Self.nameDelim {
        let name = try String(bytes: chars.dropFirst(), encoding: .isoLatin1).unwrap()
        return .name(name, kind: .literal)
      }

      let string = try String(bytes: chars, encoding: .isoLatin1).unwrap()

      guard let number = try Self.number(string: string) else {
        return .name(string, kind: .executable)
      }
      return number
    }

    func name(_ char: Char) throws -> Token {
      return try .name(String(bytes: [char], encoding: .isoLatin1).unwrap(), kind: .executable)
    }

    func comment() throws {

      while let char = try next() {
        switch char {
        case Self.lineFeed:
          return

        case Self.carriageReturn:
          if try peek() == Self.lineFeed {
            try skip()
          }
          return

        default:
          continue
        }
      }
    }

    func encodedString() throws -> Token {

      if try peek() == Self.ascii85Marker {
        try skip()

        var chars: [Char] = []
        while let char = try next() {
          if char == Self.ascii85Marker {
            guard try next() == Self.angleDelims.close else {
              throw Error.syntaxError
            }

            do {
              let encoded = try String(bytes: chars, encoding: .ascii).unwrap(or: Error.syntaxError)
              return .string(try Ascii85.decode(encoded))
            } catch is Ascii85.DecodingError {
              throw Error.syntaxError
            }
          }

          chars.append(char)
        }

        throw Error.syntaxError
      }

      let chars = try take { $0 != Self.angleDelims.close }

      guard try next() == Self.angleDelims.close else {
        throw Error.syntaxError
      }

      let nowsChars = chars.filter { !Self.whitespace.contains($0) }
      let hexChars = nowsChars.count.isMultiple(of: 2) ? nowsChars : nowsChars + [Self.zero]

      let data = try Data(
        baseEncodedString: String(bytes: hexChars, encoding: .ascii).neverNil(),
        encoding: .base16
      )
      .unwrap(or: Error.syntaxError)

      return .string(data)
    }

    func literalString() throws -> Token {

      var chars: [Char] = []
      var parenDepth = 1

      while true {
        chars.append(contentsOf: try take { !Self.literalStringSpecialCharSet.contains($0) })

        let char = try next().unwrap(or: Error.syntaxError)

        switch char {
        case Self.literalStringDelims.open:
          chars.append(char)
          parenDepth += 1

        case Self.literalStringDelims.close:
          parenDepth -= 1
          if parenDepth == 0 {
            return .string(Data(chars))
          } else {
            chars.append(char)
          }

        case Self.escapeMarker:
          if let escaped = try escapeLiteralChar() {
            chars.append(escaped)
          }

        case Self.carriageReturn:
          if try peek() == Self.lineFeed {
            try skip()
          }
          chars.append(Self.lineFeed)

        default:
          // Unhandled literal string special character
          throw Error.unregistered(.internalScannerError)
        }
      }
    }

    func escapeLiteralChar() throws -> Char? {

      let escaped = try next().unwrap(or: Error.syntaxError)

      switch escaped {
      case Self.escapes.lineFeed:
        return Self.lineFeed
      case Self.escapes.carriageReturn:
        return Self.carriageReturn
      case Self.escapes.tab:
        return Self.tab
      case Self.escapes.backSpace:
        return Self.backSpace
      case Self.escapes.formFeed:
        return Self.formFeed
      case Self.lineFeed, Self.carriageReturn:
        try newlineEscape(escaped)
        return nil
      case Self.octalDigits:
        return try octalEscape(escaped)
      default:
        // Ignore slash
        return escaped
      }
    }

    func octalEscape(_ octal1: Char) throws -> Char {

      var digits = [octal1]
      if let octal2 = try peek(), octal2.isOctalDigit {
        digits.append(octal2)
        try skip()

        if let octal3 = try peek(), octal3.isOctalDigit {
          digits.append(octal3)
          try skip()
        }
      }

      // Ignore any high order bits overflowed... per PS manual
      let code = try Int(String(bytes: digits, encoding: .ascii).unwrap(), radix: 8)
        .map(UInt8.init(truncatingIfNeeded:))
        .unwrap(or: Error.syntaxError)

      return code
    }

    func newlineEscape(_ char: Char) throws {
      if try char == Self.carriageReturn && peek() == Self.lineFeed {
        try skip()
      }
    }
  }

  static func number(string: String) throws -> Token? {

    if string.wholeMatch(of: decimalIntegerRegex) != nil {
      if let integer = Int32(string) {
        return .integer(integer)
      }
      return .real(try parseReal(string))
    }

    if string.wholeMatch(of: realRegex) != nil {
      return .real(try parseReal(string))
    }

    guard let match = string.wholeMatch(of: radixRegex),
      match.output.count == 3,
      let baseSubstring = match.output[1].substring,
      let digitsSubstring = match.output[2].substring,
      let base = Int(baseSubstring),
      (2...36).contains(base)
    else {
      return nil
    }

    let digits = String(digitsSubstring)
    guard digits.allSatisfy({ digitValue($0).map { $0 < base } ?? false }) else {
      return nil
    }

    var value: UInt32 = 0
    for digit in digits {
      let (multiplied, multiplyOverflow) = value.multipliedReportingOverflow(by: UInt32(base))
      let (next, addOverflow) = multiplied.addingReportingOverflow(UInt32(digitValue(digit).neverNil()))
      guard !multiplyOverflow && !addOverflow else {
        throw Error.limitCheck
      }
      value = next
    }
    return .integer(Int32(bitPattern: value))
  }

  private static func parseReal(_ string: String) throws -> Double {
    guard let real = Double(string), real.isFinite else {
      throw Error.limitCheck
    }

    let significand = string.prefix { $0 != "e" && $0 != "E" }
    let underflowed = real == 0 && significand.contains { $0.isNumber && $0 != "0" }
    guard !underflowed else {
      throw Error.limitCheck
    }
    return real
  }

  private static func digitValue(_ digit: Character) -> Int? {
    switch digit {
    case "0"..."9":
      Int(digit.asciiValue.neverNil() - Character("0").asciiValue.neverNil())
    case "a"..."z":
      Int(digit.asciiValue.neverNil() - Character("a").asciiValue.neverNil()) + 10
    case "A"..."Z":
      Int(digit.asciiValue.neverNil() - Character("A").asciiValue.neverNil()) + 10
    default:
      nil
    }
  }

  var available: Int {
    get throws {
      try file.available + pushback.count
    }
  }

  func readBinaryByte() throws -> UInt8 {
    try next().unwrap(or: Error.syntaxError)
  }

  func readBinaryData(count: Int) throws -> Data {
    guard count >= 0 else {
      throw Error.syntaxError
    }
    return try Data((0..<count).map { _ in try readBinaryByte() })
  }

  private func next() throws -> Char? {
    let byte: Char?
    if let pushed = pushback.popLast() {
      byte = pushed
    } else if let contextualInput {
      if contextualOffset < contextualInput.count {
        byte = contextualInput[contextualOffset]
        contextualOffset += 1
      } else if contextualEOF {
        byte = nil
      } else {
        throw ScannerInputRequired()
      }
    } else {
      byte = try file.readByte()
    }
    if let byte {
      history.append(byte)
      if history.count > 8 {
        history.removeFirst(history.count - 8)
      }
    }
    return byte
  }

  private func returnContextualLookahead(to context: isolated Context) {
    var unread = Data(pushback.reversed())
    if let contextualInput, contextualOffset < contextualInput.count {
      unread.append(contentsOf: contextualInput.dropFirst(contextualOffset))
    }
    pushback.removeAll()
    context.prependReadAhead(unread, to: file)
  }

  private func take(_ count: Int) throws -> [Char] {
    var chars: [Char] = []

    for _ in 0..<count {

      guard let char = try next() else {
        throw Error.unregistered(.internalScannerError)
      }

      chars.append(char)
    }

    return chars
  }

  private func take(while predicate: (Char) -> Bool) throws -> [Char] {

    var chars: [Char] = []

    while true {
      guard let char = try next() else {
        break
      }
      guard predicate(char) else {
        try rewind()
        break
      }

      chars.append(char)
    }

    return chars
  }

  private func skip(count: Int = 1) throws {
    for _ in 0..<count {
      _ = try next()
    }
  }

  private func skip(while predicate: (Char) -> Bool) throws {
    while true {
      guard let char = try next() else {
        break
      }
      guard predicate(char) else {
        try rewind()
        break
      }
    }
  }

  private func peek() throws -> Char? {
    guard let byte = try next() else {
      return nil
    }
    try rewind()
    return byte
  }

  private func rewind(count: Int = 1) throws {
    guard count >= 0, history.count >= count else {
      throw Error.unregistered(.internalScannerError)
    }
    for _ in 0..<count {
      pushback.append(history.removeLast())
    }
  }

}

private struct ScannerInputRequired: Swift.Error {}

extension Scanner.CharSet {

  fileprivate static func ~= (_ chars: Self, _ char: UInt8) -> Bool {
    chars.contains(char)
  }

}

extension Scanner.Char {

  fileprivate var isHexDigit: Bool { Scanner.hexDigits.contains(self) }
  fileprivate var isOctalDigit: Bool { Scanner.octalDigits.contains(self) }

}
