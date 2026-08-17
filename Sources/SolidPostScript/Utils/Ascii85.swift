//
//  Ascii85.swift
//
//
//  Created by Kevin Wooten on 6/25/24.
//

import Foundation

/// An PostScript ascii85.
public enum Ascii85 {

  private static let firstDigit: UInt8 = 33
  private static let lastDigit: UInt8 = 117

  // Error handling for the ASCII85 decoding process
  /// A PostScript decoding error.
  public enum DecodingError: Swift.Error {
    case invalidCharacter
    case invalidLength
  }

  /// Performs the ``decode`` operation.
  public static func decode(_ input: some StringProtocol) throws -> Data {

    var decodedBytes: [UInt8] = []
    var tuple: [UInt64] = []

    for character in input {

      guard let ascii = character.asciiValue else {
        throw DecodingError.invalidCharacter
      }

      if whitespace.contains(ascii) {
        continue
      }

      if character == "z" {
        guard tuple.isEmpty else {
          throw DecodingError.invalidCharacter
        }
        decodedBytes.append(contentsOf: [0, 0, 0, 0])
        continue
      }

      guard ascii >= firstDigit, ascii <= lastDigit else {
        throw DecodingError.invalidCharacter
      }

      tuple.append(UInt64(ascii - firstDigit))

      if tuple.count == 5 {
        decodedBytes.append(contentsOf: try decode(tuple))
        tuple.removeAll(keepingCapacity: true)
      }
    }

    guard tuple.count != 1 else {
      throw DecodingError.invalidLength
    }

    if !tuple.isEmpty {
      let byteCount = tuple.count - 1
      tuple.append(contentsOf: repeatElement(84, count: 5 - tuple.count))
      decodedBytes.append(contentsOf: try decode(tuple).prefix(byteCount))
    }

    return Data(decodedBytes)
  }

  private static let whitespace: Set<UInt8> = [0x00, 0x09, 0x0A, 0x0C, 0x0D, 0x20]

  private static func decode(_ tuple: [UInt64]) throws -> [UInt8] {
    let combined = tuple.reduce(0) { $0 * 85 + $1 }
    guard combined <= UInt32.max else {
      throw DecodingError.invalidCharacter
    }

    return [
      UInt8((combined >> 24) & 0xFF),
      UInt8((combined >> 16) & 0xFF),
      UInt8((combined >> 8) & 0xFF),
      UInt8(combined & 0xFF),
    ]
  }

  static let ascii85Table = Array(
    "!\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuv"
  )

  /// Performs the ``encode`` operation.
  public static func encode(_ data: Data) -> String {

    var encodedString = ""

    // Process data in 4-byte blocks
    var buffer: UInt32 = 0
    var byteCount = 0

    for byte in data {
      buffer = (buffer << 8) | UInt32(byte)
      byteCount += 1

      if byteCount == 4 {
        // Encode 4 bytes into 5 ASCII85 characters
        var encodedBlock = [Character](repeating: "!", count: 5)
        for i in (0..<5).reversed() {
          encodedBlock[i] = ascii85Table[Int(buffer % 85)]
          buffer /= 85
        }
        encodedString.append(contentsOf: encodedBlock)
        buffer = 0
        byteCount = 0
      }
    }

    // Handle padding if data length is not a multiple of 4
    if byteCount > 0 {
      buffer <<= (4 - byteCount) * 8
      var encodedBlock = [Character](repeating: "!", count: 5)
      for i in encodedBlock.indices.reversed() {
        encodedBlock[i] = ascii85Table[Int(buffer % 85)]
        buffer /= 85
      }
      encodedString.append(contentsOf: encodedBlock.prefix(byteCount + 1))
    }

    return encodedString
  }
}
