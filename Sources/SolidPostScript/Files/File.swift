//
//  File.swift
//
//
//  Created by Kevin Wooten on 7/3/24.
//

import Foundation
import SolidCore

/// A synchronous, seekable file used by PostScript file operators.
public protocol File: AnyObject, Sendable {

  typealias Mode = FileMode

  var name: String { get }
  var mode: Mode { get }

  /// Whether this file supports random positioning.
  var isPositionable: Bool { get }

  func readByte() throws -> UInt8?
  func readByte(ifMatches predicate: (UInt8) -> Bool) throws -> (matched: UInt8?, eof: Bool)
  func read(untilMatching predicate: (UInt8) -> Bool) throws -> UInt8?

  func read(max: Int) throws -> Data?
  func readHex(max: Int) throws -> (data: Data, eof: Bool)
  func readLine() throws -> (line: Data, eof: Bool)

  func write(contentsOf: Data) throws
  func writeHex(contentsOf: Data) throws

  var isClosed: Bool { get }
  func close() throws

  var offset: Int { get throws }
  func setOffset(_ offset: Int) throws

  var available: Int { get throws }
  var size: Int { get throws }

  func flush() throws
  func reset() throws
}

extension File {

  /// Files are positionable unless a conformer reports otherwise.
  public var isPositionable: Bool { true }

  /// Performs the ``read`` operation.
  public func read(untilMatching predicate: (UInt8) -> Bool) throws -> UInt8? {
    while true {
      guard let byte = try readByte() else {
        return nil
      }
      guard predicate(byte) else {
        continue
      }
      return byte
    }
  }

  /// Performs the ``readHex`` operation.
  public func readHex(max: Int) throws -> (data: Data, eof: Bool) {

    /// Reads hex digit pair and coverts to equivalent byte.
    func readHexByte() throws -> UInt8? {
      guard
        let charCode1 = try read(untilMatching: { isxdigit(Int32($0)) != 0 }),
        let charCode2 = try read(untilMatching: { isxdigit(Int32($0)) != 0 })
      else {
        return nil
      }

      let index1 = Int(charCode1 & 0x1F ^ 0x10)
      let index2 = Int(charCode2 & 0x1F ^ 0x10)

      return hexCharTable[index1] << 4 | hexCharTable[index2]
    }

    var result = Data(capacity: max)
    while result.count < max {

      guard let byte = try readHexByte() else {
        try close()
        return (result, true)
      }

      result.append(byte)
    }

    return (result, false)
  }

  /// Performs the ``readLine`` operation.
  public func readLine() throws -> (line: Data, eof: Bool) {
    var result = Data()

    while true {

      guard let byte = try readByte() else {
        return (result, true)
      }

      if byte == Scanner.carriageReturn || byte == Scanner.lineFeed {

        if byte == Scanner.carriageReturn {
          if try readByte(ifMatches: { $0 == Scanner.lineFeed }).eof {
            return (result, true)
          }
        }

        break
      }

      result.append(byte)
    }

    return (result, false)
  }

  /// Performs the ``writeHex`` operation.
  public func writeHex(contentsOf data: Data) throws {
    try write(contentsOf: Data(data.baseEncoded(using: .base16Lower).utf8))
  }

}

protocol ContextualFile: File {

  func readByte(context: isolated Context) async throws -> UInt8?
  func readByte(
    ifMatches predicate: (UInt8) -> Bool,
    context: isolated Context
  ) async throws -> (matched: UInt8?, eof: Bool)
  func read(max: Int, context: isolated Context) async throws -> Data?
  func available(context: isolated Context) async throws -> Int
  func write(contentsOf data: Data, context: isolated Context) async throws
  func close(context: isolated Context) async throws
  func flush(context: isolated Context) async throws

}

extension ContextualFile {

  func readByte(context: isolated Context) async throws -> UInt8? { try readByte() }

  func readByte(
    ifMatches predicate: (UInt8) -> Bool,
    context: isolated Context
  ) async throws -> (matched: UInt8?, eof: Bool) {
    try readByte(ifMatches: predicate)
  }

  func read(max: Int, context: isolated Context) async throws -> Data? { try read(max: max) }

  func available(context: isolated Context) async throws -> Int { try available }
}

extension File {

  func readByte(context: isolated Context) async throws -> UInt8? {
    if let contextual = self as? any ContextualFile {
      return try await contextual.readByte(context: context)
    }
    return try readByte()
  }

  func readByte(
    ifMatches predicate: (UInt8) -> Bool,
    context: isolated Context
  ) async throws -> (matched: UInt8?, eof: Bool) {
    if let contextual = self as? any ContextualFile {
      return try await contextual.readByte(ifMatches: predicate, context: context)
    }
    return try readByte(ifMatches: predicate)
  }

  func read(max: Int, context: isolated Context) async throws -> Data? {
    if let contextual = self as? any ContextualFile {
      return try await contextual.read(max: max, context: context)
    }
    return try read(max: max)
  }

  func available(context: isolated Context) async throws -> Int {
    if let contextual = self as? any ContextualFile {
      return try await contextual.available(context: context)
    }
    return try available
  }

  func readHex(max: Int, context: isolated Context) async throws -> (data: Data, eof: Bool) {
    func nextHexDigit() async throws -> UInt8? {
      while let byte = try await readByte(context: context) {
        if isxdigit(Int32(byte)) != 0 { return byte }
      }
      return nil
    }

    var result = Data(capacity: max)
    while result.count < max {
      guard let first = try await nextHexDigit(), let second = try await nextHexDigit() else {
        try await close(context: context)
        return (result, true)
      }
      let firstIndex = Int(first & 0x1F ^ 0x10)
      let secondIndex = Int(second & 0x1F ^ 0x10)
      result.append(hexCharTable[firstIndex] << 4 | hexCharTable[secondIndex])
    }
    return (result, false)
  }

  func readLine(context: isolated Context) async throws -> (line: Data, eof: Bool) {
    var result = Data()
    while let byte = try await readByte(context: context) {
      if byte == Scanner.lineFeed { return (result, false) }
      if byte == Scanner.carriageReturn {
        let lookahead = try await readByte(ifMatches: { $0 == Scanner.lineFeed }, context: context)
        return (result, lookahead.eof)
      }
      result.append(byte)
    }
    return (result, true)
  }

  func write(contentsOf data: Data, context: isolated Context) async throws {
    if let contextual = self as? any ContextualFile {
      try await contextual.write(contentsOf: data, context: context)
    } else {
      try write(contentsOf: data)
    }
  }

  func close(context: isolated Context) async throws {
    if let contextual = self as? any ContextualFile {
      try await contextual.close(context: context)
    } else {
      try close()
    }
  }

  func flush(context: isolated Context) async throws {
    if let contextual = self as? any ContextualFile {
      try await contextual.flush(context: context)
    } else {
      try flush()
    }
  }

}

fileprivate let hexCharTable: [UInt8] = [
  0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,    // 01234567
  0x08, 0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,    // 89:;<=>?
  0x00, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x00,    // @ABCDEFG
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,    // HIJKLMNO
]
