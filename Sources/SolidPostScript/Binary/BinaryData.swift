import Foundation

struct BinaryDataReader {
  let data: Data
  private(set) var offset = 0

  var remaining: Int { data.count - offset }

  mutating func readByte() throws -> UInt8 {
    guard offset < data.count else {
      throw Error.syntaxError
    }
    defer { offset += 1 }
    return data[offset]
  }

  mutating func read(count: Int) throws -> Data {
    guard count >= 0, count <= remaining else {
      throw Error.syntaxError
    }
    defer { offset += count }
    return data.subdata(in: offset..<offset + count)
  }

  mutating func readUInt16(order: ObjectFormat.ByteOrder) throws -> UInt16 {
    let bytes = try read(count: 2)
    return switch order {
    case .bigEndian:
      UInt16(bytes[0]) << 8 | UInt16(bytes[1])
    case .littleEndian:
      UInt16(bytes[1]) << 8 | UInt16(bytes[0])
    }
  }

  mutating func readInt16(order: ObjectFormat.ByteOrder) throws -> Int16 {
    Int16(bitPattern: try readUInt16(order: order))
  }

  mutating func readUInt32(order: ObjectFormat.ByteOrder) throws -> UInt32 {
    let bytes = try read(count: 4)
    return switch order {
    case .bigEndian:
      UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
    case .littleEndian:
      UInt32(bytes[3]) << 24 | UInt32(bytes[2]) << 16 | UInt32(bytes[1]) << 8 | UInt32(bytes[0])
    }
  }

  mutating func readInt32(order: ObjectFormat.ByteOrder) throws -> Int32 {
    Int32(bitPattern: try readUInt32(order: order))
  }
}

struct BinaryDataWriter {
  private(set) var data = Data()

  var count: Int { data.count }

  mutating func append(_ byte: UInt8) {
    data.append(byte)
  }

  mutating func append(_ bytes: Data) {
    data.append(bytes)
  }

  mutating func appendUInt16(_ value: UInt16, order: ObjectFormat.ByteOrder) {
    switch order {
    case .bigEndian:
      append(UInt8(truncatingIfNeeded: value >> 8))
      append(UInt8(truncatingIfNeeded: value))
    case .littleEndian:
      append(UInt8(truncatingIfNeeded: value))
      append(UInt8(truncatingIfNeeded: value >> 8))
    }
  }

  mutating func appendInt16(_ value: Int16, order: ObjectFormat.ByteOrder) {
    appendUInt16(UInt16(bitPattern: value), order: order)
  }

  mutating func appendUInt32(_ value: UInt32, order: ObjectFormat.ByteOrder) {
    switch order {
    case .bigEndian:
      append(UInt8(truncatingIfNeeded: value >> 24))
      append(UInt8(truncatingIfNeeded: value >> 16))
      append(UInt8(truncatingIfNeeded: value >> 8))
      append(UInt8(truncatingIfNeeded: value))
    case .littleEndian:
      append(UInt8(truncatingIfNeeded: value))
      append(UInt8(truncatingIfNeeded: value >> 8))
      append(UInt8(truncatingIfNeeded: value >> 16))
      append(UInt8(truncatingIfNeeded: value >> 24))
    }
  }

  mutating func appendInt32(_ value: Int32, order: ObjectFormat.ByteOrder) {
    appendUInt32(UInt32(bitPattern: value), order: order)
  }
}

enum BinaryNumberCodec {
  static func fixed(_ value: Int32, scale: Int) throws -> Object {
    guard scale >= 0 else {
      throw Error.syntaxError
    }
    if scale == 0 {
      return .integer(value)
    }
    return try .real(Double(value) / pow(2, Double(scale)), error: .limitCheck)
  }

  static func fixed(_ value: Int16, scale: Int) throws -> Object {
    try fixed(Int32(value), scale: scale)
  }

  static func ieee(_ bits: UInt32) throws -> Object {
    let value = Float(bitPattern: bits)
    guard value.isFinite else {
      throw Error.limitCheck
    }
    return try .real(Double(value), error: .limitCheck)
  }

  static func native(_ data: Data) throws -> Object {
    guard data.count == MemoryLayout<Float>.size else {
      throw Error.syntaxError
    }
    var bits: UInt32 = 0
    withUnsafeMutableBytes(of: &bits) { destination in
      destination.copyBytes(from: data)
    }
    let value = Float(bitPattern: bits)
    guard value.isFinite else {
      throw Error.limitCheck
    }
    return try .real(Double(value), error: .limitCheck)
  }

  static func floatData(_ value: Double, format: ObjectFormat) throws -> Data {
    let float = Float(value)
    guard value.isFinite, float.isFinite, Double(float) != 0 || value == 0 else {
      throw Error.limitCheck
    }

    switch format.realFormat {
    case .ieee:
      var writer = BinaryDataWriter()
      writer.appendUInt32(float.bitPattern, order: format.byteOrder)
      return writer.data
    case .native:
      var value = float
      return withUnsafeBytes(of: &value) { Data($0) }
    }
  }
}
