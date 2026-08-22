import Foundation

struct PDFShadingBitReader {
  private let data: Data
  private var bitOffset = 0

  init(_ data: Data) { self.data = data }

  var remainingBits: Int { data.count * 8 - bitOffset }

  mutating func read(_ count: Int) throws -> UInt64 {
    guard count >= 0, count <= 32, remainingBits >= count else { throw PDFObjectAccess.TypeMismatch.integer }
    var result: UInt64 = 0
    for _ in 0..<count {
      result = result << 1 | UInt64((data[bitOffset / 8] >> (7 - bitOffset % 8)) & 1)
      bitOffset += 1
    }
    return result
  }

  mutating func alignToByte() {
    bitOffset = min(data.count * 8, (bitOffset + 7) & ~7)
  }

  mutating func decode(_ count: Int, lower: Double, upper: Double) throws -> Double {
    let raw = try read(count)
    let maximum = Double((UInt64(1) << UInt64(count)) - 1)
    return lower + (upper - lower) * Double(raw) / maximum
  }
}
