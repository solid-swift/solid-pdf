import Foundation

enum EncodedNumberString {
  struct Header {
    let representation: UInt8
    let count: Int
    let width: Int
    let order: ObjectFormat.ByteOrder
    let kind: Kind
  }

  enum Kind {
    case fixed(scale: Int)
    case ieee
    case native
  }

  static func header(from data: Data) throws -> Header {
    var reader = BinaryDataReader(data: data)
    guard try reader.readByte() == 149 else {
      throw Error.syntaxError
    }
    let representation = try reader.readByte()
    let descriptor = try descriptor(for: representation)
    let count = Int(try reader.readUInt16(order: descriptor.order))
    return Header(
      representation: representation,
      count: count,
      width: descriptor.width,
      order: descriptor.order,
      kind: descriptor.kind
    )
  }

  static func decode(_ data: Data) throws -> [Object] {
    let header = try header(from: data)
    let (payloadSize, overflow) = header.count.multipliedReportingOverflow(by: header.width)
    guard !overflow, data.count == 4 + payloadSize else {
      throw Error.syntaxError
    }

    var reader = BinaryDataReader(data: data)
    _ = try reader.read(count: 4)
    return try (0..<header.count).map { _ in
      switch header.kind {
      case .fixed(let scale):
        if header.width == 2 {
          return try BinaryNumberCodec.fixed(reader.readInt16(order: header.order), scale: scale)
        }
        return try BinaryNumberCodec.fixed(reader.readInt32(order: header.order), scale: scale)
      case .ieee:
        return try BinaryNumberCodec.ieee(reader.readUInt32(order: header.order))
      case .native:
        return try BinaryNumberCodec.native(reader.read(count: 4))
      }
    }
  }

  private static func descriptor(
    for representation: UInt8
  ) throws -> (width: Int, order: ObjectFormat.ByteOrder, kind: Kind) {
    switch representation {
    case 0...31:
      (4, .bigEndian, .fixed(scale: Int(representation)))
    case 32...47:
      (2, .bigEndian, .fixed(scale: Int(representation - 32)))
    case 48:
      (4, .bigEndian, .ieee)
    case 49:
      (4, .bigEndian, .native)
    case 128...159:
      (4, .littleEndian, .fixed(scale: Int(representation - 128)))
    case 160...175:
      (2, .littleEndian, .fixed(scale: Int(representation - 160)))
    case 176:
      (4, .littleEndian, .ieee)
    case 177:
      (4, .littleEndian, .native)
    default:
      throw Error.syntaxError
    }
  }
}
