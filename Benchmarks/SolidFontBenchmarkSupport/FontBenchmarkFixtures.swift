import Foundation

/// Deterministic, project-authored font-program inputs shared by benchmarks and tests.
public enum FontBenchmarkFixtures {
  /// A minimal valid one-face CFF1 font containing one `endchar` program.
  public static let compactFont: Data = {
    var data = Data([1, 0, 4, 4])
    data.append(contentsOf: [0, 1, 1, 1, 5])
    data.append(contentsOf: "Test".utf8)
    data.append(contentsOf: [0, 1, 1, 1, 7, 29, 0, 0, 0, 28, 17])
    data.append(contentsOf: [0, 0, 0, 0])
    data.append(contentsOf: [0, 1, 1, 1, 2, 14])
    return data
  }()

  /// A bounded synthetic collection of sfnt directories with no tables.
  public static let fontCollection: Data = {
    let faceCount = 16
    let headerLength = 12 + faceCount * 4
    var data = Data([0x74, 0x74, 0x63, 0x66, 0, 1, 0, 0, 0, 0, 0, UInt8(faceCount)])
    for index in 0..<faceCount {
      data.appendUInt32(UInt32(headerLength + index * 12))
    }
    for _ in 0..<faceCount {
      data.append(contentsOf: [0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    }
    return data
  }()

  /// A Type 1 outline program with width, move, lines, close, and end operations.
  public static let type1CharString = Data([
    139, 248, 236, 13,
    139, 139, 21,
    248, 136, 139, 139, 249, 80, 252, 136, 139, 139, 253, 80, 5,
    9, 14,
  ])

  /// A Type 2 program exercising arithmetic, movement, and termination.
  public static let type2CharString = Data([141, 142, 12, 10, 143, 12, 24, 22, 14])
}

private extension Data {
  mutating func appendUInt32(_ value: UInt32) {
    append(UInt8((value >> 24) & 255))
    append(UInt8((value >> 16) & 255))
    append(UInt8((value >> 8) & 255))
    append(UInt8(value & 255))
  }
}
