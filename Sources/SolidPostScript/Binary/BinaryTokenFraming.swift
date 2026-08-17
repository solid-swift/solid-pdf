import Foundation

enum BinaryTokenFraming {

  static func totalLength(of data: Data) throws -> Int? {
    guard let type = data.first else { return nil }

    switch type {
    case 128...131:
      return try objectSequenceLength(of: data, type: type)
    case 132, 133, 138, 139, 140:
      return 5
    case 134, 135:
      return 3
    case 136, 141, 145, 146:
      return 2
    case 137:
      guard data.count >= 2 else { return nil }
      return try 2 + fixedPointWidth(for: data[data.startIndex + 1])
    case 142:
      guard data.count >= 2 else { return nil }
      return 2 + Int(data[data.startIndex + 1])
    case 143, 144:
      guard data.count >= 3 else { return nil }
      let order: ObjectFormat.ByteOrder = type == 143 ? .bigEndian : .littleEndian
      return 3 + Int(readUInt16(data, at: 1, order: order))
    case 149:
      guard data.count >= 4 else { return nil }
      let header = try EncodedNumberString.header(from: Data(data.prefix(4)))
      let (payloadLength, overflow) = header.count.multipliedReportingOverflow(by: header.width)
      guard !overflow else { throw Error.limitCheck }
      return 4 + payloadLength
    default:
      throw Error.syntaxError
    }
  }

  static func fixedPointWidth(for representation: UInt8) throws -> Int {
    switch representation {
    case 0...31, 128...159:
      4
    case 32...47, 160...175:
      2
    default:
      throw Error.syntaxError
    }
  }

  private static func objectSequenceLength(of data: Data, type: UInt8) throws -> Int? {
    guard data.count >= 4 else { return nil }
    let order: ObjectFormat.ByteOrder = type == 128 || type == 130 ? .bigEndian : .littleEndian

    if data[data.startIndex + 1] == 0 {
      guard data.count >= 8 else { return nil }
      let size = Int(readUInt32(data, at: 4, order: order))
      guard size >= 8 else { throw Error.syntaxError }
      return size
    }

    let size = Int(readUInt16(data, at: 2, order: order))
    guard size >= 4 else { throw Error.syntaxError }
    return size
  }

  private static func readUInt16(_ data: Data, at offset: Int, order: ObjectFormat.ByteOrder) -> UInt16 {
    let first = UInt16(data[data.startIndex + offset])
    let second = UInt16(data[data.startIndex + offset + 1])
    return order == .bigEndian ? first << 8 | second : second << 8 | first
  }

  private static func readUInt32(_ data: Data, at offset: Int, order: ObjectFormat.ByteOrder) -> UInt32 {
    let first = UInt32(readUInt16(data, at: offset, order: order))
    let second = UInt32(readUInt16(data, at: offset + 2, order: order))
    return order == .bigEndian ? first << 16 | second : second << 16 | first
  }
}
