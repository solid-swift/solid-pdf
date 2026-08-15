//
//  Ascii85.swift
//
//
//  Created by Kevin Wooten on 6/25/24.
//

import Foundation

/// An PostScript ascii85.
public enum Ascii85 {

  // Error handling for the ASCII85 decoding process
  /// A PostScript decoding error.
  public enum DecodingError: Swift.Error {
    case invalidCharacter
    case invalidLength
  }

  /// Performs the ``decode`` operation.
  public static func decode(_ input: some StringProtocol) throws -> Data {

    guard input.allSatisfy({ $0.isASCII && $0 >= "!" && $0 <= "u" || $0 == "z" }) else {
      throw DecodingError.invalidCharacter
    }

    // Ensure the length of the filtered input is valid
    guard !input.isEmpty && input.count % 5 == 0 else {
      throw DecodingError.invalidLength
    }

    var decodedBytes: [UInt8] = []

    // Process each group of 5 characters
    var buffer: [UInt32] = Array(repeating: 0, count: 5)
    var byteCount = 0

    for (index, character) in input.enumerated() {

      if character == "z" {
        // "z" is a special case that represents 4 zero bytes
        decodedBytes.append(contentsOf: [0, 0, 0, 0])
        byteCount += 4
        continue
      }

      // Map the ASCII85 character to its base85 value
      guard let value = character.asciiValue else {
        throw DecodingError.invalidCharacter
      }

      buffer[index % 5] = UInt32(value - 33)

      // If we have 5 characters, decode them to 4 bytes
      if index % 5 == 4 {
        let combined = buffer.reduce(0) { $0 * 85 + $1 }
        decodedBytes.append(UInt8((combined >> 24) & 0xFF))
        decodedBytes.append(UInt8((combined >> 16) & 0xFF))
        decodedBytes.append(UInt8((combined >> 8) & 0xFF))
        decodedBytes.append(UInt8(combined & 0xFF))
        byteCount += 4
      }
    }

    // Handle padding if the input length was not a multiple of 5
    let paddingCount = input.count % 5
    if paddingCount > 0 {
      buffer[paddingCount] = 84
      let combined = buffer.reduce(0) { $0 * 85 + $1 }
      for i in 0..<paddingCount - 1 {
        decodedBytes.append(UInt8((combined >> (8 * (3 - i))) & 0xFF))
      }
    }

    return Data(decodedBytes)
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
      var encodedBlock = [Character](repeating: "!", count: byteCount + 1)
      for i in (0..<byteCount + 1).reversed() {
        encodedBlock[i] = ascii85Table[Int(buffer % 85)]
        buffer /= 85
      }
      encodedString.append(contentsOf: encodedBlock)
    }

    return encodedString
  }
}
