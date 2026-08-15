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

  /// The ``file`` value.
  public let file: File

  /// Creates an instance.
  public convenience init(content: Data) throws {
    try self.init(file: DataFile(data: content, mode: .read))
  }

  /// Creates an instance.
  public init(file: File) throws {
    self.file = file
  }

  /// Performs the ``nextToken`` operation.
  public func nextToken() throws -> Token? {

    var chars: [Char] = []

    while true {

      guard let char = try next() else {
        return try token(chars, putBack: 0)
      }

      switch char {
      case Self.whitespace:
        if let token = try token(chars) {
          return token
        }
        try skip(while: Self.whitespace.contains)

      case Self.literalStringDelims.open:
        return try token(chars) ?? literalString()

      case Self.angleDelims.open where try peek().map { $0 == Self.ascii85Marker || $0.isHexDigit } ?? false:
        return try token(chars) ?? encodedString()

      case Self.angleDelims.open where try peek() == Self.angleDelims.open,
        Self.angleDelims.close where try peek() == Self.angleDelims.close:
        return try token(chars) ?? token([char] + take(1), putBack: 0)

      case Self.arrayDelims, Self.procedureDelims, Self.angleDelims.open, Self.angleDelims.close:
        return try token(chars) ?? name(char)

      case Self.nameDelim:
        if let token = try token(chars) {
          return token
        }

        chars.append(char)

        if try peek() == Self.nameDelim {
          chars.append(Self.nameDelim)
          try skip()
        }

      case Self.commentDelim:
        try comment()
        if let token = try token(chars, putBack: 0) {
          return token
        }

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

      guard let number = Self.number(string: string) else {
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

      let chars = try take { $0 != Self.angleDelims.close }

      guard try next() == Self.angleDelims.close else {
        throw Error.syntaxError
      }

      let data: Data
      if chars.first == Self.ascii85Marker {
        let ascii85Chars = chars[chars.index(after: chars.startIndex)..<chars.index(before: chars.endIndex)]
        data = try Ascii85.decode(String(bytes: ascii85Chars, encoding: .ascii).neverNil())
      } else {
        let nowsChars = chars.filter { !Self.whitespace.contains($0) }
        let hexChars = nowsChars.count.isMultiple(of: 2) ? nowsChars : nowsChars + [Self.zero]

        data = try Data(
          baseEncodedString: String(bytes: hexChars, encoding: .ascii).neverNil(),
          encoding: .base16
        )
        .unwrap(or: Error.syntaxError)
      }

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
          chars.append(try escapeLiteralChar())

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

    func escapeLiteralChar() throws -> Char {

      let escaped = try next().unwrap(or: Error.syntaxError)

      return switch escaped {
      case Self.escapes.lineFeed: Self.lineFeed
      case Self.escapes.carriageReturn: Self.carriageReturn
      case Self.escapes.tab: Self.tab
      case Self.escapes.backSpace: Self.backSpace
      case Self.escapes.formFeed: Self.formFeed
      case Self.lineFeed, Self.carriageReturn: try newlineEscape(escaped)
      case Self.octalDigits: try octalEscape(escaped)
      default:
        // Ignore slash
        escaped
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

    func newlineEscape(_ char: Char) throws -> Char {
      if try char == Self.carriageReturn && peek() == Self.lineFeed {
        try skip()
      }
      return Self.space
    }
  }

  static func number(string: String) -> Token? {

    if let int = integer(string: string) {
      return .integer(int)
    } else if let real = real(string: string) {
      return .real(real)
    } else {
      return nil
    }
  }

  static func real(string: String) -> Double? {
    guard let real = Double(string) else {
      return nil
    }
    return real
  }

  static func integer(string: String) -> Int? {
    if let int = Int(string) {
      return int
    } else if let match = string.wholeMatch(of: Self.radixRegex),
      match.output.count == 3,
      let base = match.output[1].substring.map({ Int($0) }) ?? nil,
      let number = match.output[2].substring.map({ Int($0, radix: base) }) ?? nil
    {
      return number
    } else {
      return nil
    }
  }

  var available: Int {
    get throws {
      try file.available
    }
  }

  private func next() throws -> Char? {
    return try file.readByte()
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
    for _ in 0..<1 {
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
    try file.setOffset(file.offset - count)
  }

}

extension Scanner.CharSet {

  fileprivate static func ~= (_ chars: Self, _ char: UInt8) -> Bool {
    chars.contains(char)
  }

}

extension Scanner.Char {

  fileprivate var isHexDigit: Bool { Scanner.hexDigits.contains(self) }
  fileprivate var isOctalDigit: Bool { Scanner.octalDigits.contains(self) }

}
