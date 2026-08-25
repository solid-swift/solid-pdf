import Foundation

struct PDFRC4: Sendable {
  private var state = Array(UInt8.min...UInt8.max)
  private var firstIndex = 0
  private var secondIndex = 0

  init(key: Data) throws {
    guard !key.isEmpty, key.count <= 256 else {
      throw PDFParsingError.malformed(.init(offset: 0, message: "An RC4 key length is invalid."))
    }
    var mixedIndex = 0
    let bytes = [UInt8](key)
    for index in state.indices {
      mixedIndex = (mixedIndex + Int(state[index]) + Int(bytes[index % bytes.count])) & 0xFF
      state.swapAt(index, mixedIndex)
    }
  }

  mutating func process(_ input: Data) -> Data {
    var output = Data(count: input.count)
    output.withUnsafeMutableBytes { (outputBytes: UnsafeMutableRawBufferPointer) in
      input.withUnsafeBytes { (inputBytes: UnsafeRawBufferPointer) in
        for offset in 0..<input.count {
          firstIndex = (firstIndex + 1) & 0xFF
          secondIndex = (secondIndex + Int(state[firstIndex])) & 0xFF
          state.swapAt(firstIndex, secondIndex)
          let keyByte = state[(Int(state[firstIndex]) + Int(state[secondIndex])) & 0xFF]
          outputBytes[offset] = inputBytes[offset] ^ keyByte
        }
      }
    }
    return output
  }

  static func process(_ input: Data, key: Data) throws -> Data {
    var cipher = try Self(key: key)
    return cipher.process(input)
  }
}
