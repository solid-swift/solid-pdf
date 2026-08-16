import Foundation
import SolidCore

struct BinaryObjectSequenceEncoder {
  private enum PayloadKey: Hashable {
    case string(ObjectIdentifier, Range<Int>)
    case name(String)
  }

  private struct ArrayEntry {
    let key: ArrayViewIdentity
    let value: ArrayValue
  }

  private struct PayloadEntry {
    let key: PayloadKey
    let data: Data
  }

  let format: ObjectFormat
  let tag: UInt8

  private var arrays: [ArrayEntry] = []
  private var knownArrays: Set<ArrayViewIdentity> = []
  private var visitingArrays: Set<ArrayViewIdentity> = []
  private var payloads: [PayloadEntry] = []
  private var knownPayloads: Set<PayloadKey> = []
  private var arrayOffsets: [ArrayViewIdentity: UInt32] = [:]
  private var payloadOffsets: [PayloadKey: UInt32] = [:]

  init(format: ObjectFormat, tag: UInt8) {
    self.format = format
    self.tag = tag
  }

  mutating func encode(_ object: Object) throws -> Data {
    guard format.binaryEnabled else {
      throw Error.undefined
    }

    try collect(object, depth: 0)
    try assignOffsets()

    var body = BinaryDataWriter()
    try appendRecord(object, tag: tag, to: &body)
    for entry in arrays {
      for element in try entry.value.objects(in: entry.value.range) {
        try appendRecord(element, tag: 0, to: &body)
      }
    }
    for payload in payloads {
      body.append(payload.data)
    }

    let normalSize = body.count + 4
    var output = BinaryDataWriter()
    if normalSize <= Int(UInt16.max) {
      output.append(format.sequenceToken)
      output.append(1)
      output.appendUInt16(UInt16(normalSize), order: format.byteOrder)
    } else {
      let extendedSize = body.count + 8
      guard let size = UInt32(exactly: extendedSize) else {
        throw Error.limitCheck
      }
      output.append(format.sequenceToken)
      output.append(0)
      output.appendUInt16(1, order: format.byteOrder)
      output.appendUInt32(size, order: format.byteOrder)
    }
    output.append(body.data)
    return output.data
  }

  private mutating func collect(_ object: Object, depth: Int) throws {
    guard depth <= 1_000 else {
      throw Error.limitCheck
    }

    switch object.type {
    case .null, .integer, .boolean, .mark:
      return
    case .real:
      let real = try object.value(as: RealValue.self)
      _ = try BinaryNumberCodec.floatData(real.value, format: format)
    case .name:
      let name = try object.value(as: NameValue.self).value
      guard let data = name.data(using: .isoLatin1), !data.isEmpty, data.count <= 127 else {
        throw Error.limitCheck
      }
      addPayload(key: .name(name), data: data)
    case .string:
      let string = try object.value(as: StringValue.self)
      guard string.count <= UInt(UInt16.max) else { throw Error.limitCheck }
      let key = PayloadKey.string(string.snapshotIdentity, string.refRange)
      addPayload(key: key, data: try string.characters(in: string.range))
    case .array:
      let array = try object.value(as: ArrayValue.self)
      guard array.count <= UInt(UInt16.max) else { throw Error.limitCheck }
      let key = array.arrayViewIdentity
      if visitingArrays.contains(key) {
        throw Error.limitCheck
      }
      guard knownArrays.insert(key).inserted else { return }
      visitingArrays.insert(key)
      arrays.append(ArrayEntry(key: key, value: array))
      for element in try array.objects(in: array.range) {
        try collect(element, depth: depth + 1)
      }
      visitingArrays.remove(key)
    default:
      throw Error.typeCheck
    }
  }

  private mutating func addPayload(key: PayloadKey, data: Data) {
    guard knownPayloads.insert(key).inserted else { return }
    payloads.append(PayloadEntry(key: key, data: data))
  }

  private mutating func assignOffsets() throws {
    var offset = 8
    for array in arrays {
      guard let storedOffset = UInt32(exactly: offset) else { throw Error.limitCheck }
      arrayOffsets[array.key] = storedOffset
      let (byteCount, countOverflow) = Int(array.value.count).multipliedReportingOverflow(by: 8)
      let (nextOffset, offsetOverflow) = offset.addingReportingOverflow(byteCount)
      guard !countOverflow, !offsetOverflow else { throw Error.limitCheck }
      offset = nextOffset
    }
    for payload in payloads {
      guard let storedOffset = UInt32(exactly: offset) else { throw Error.limitCheck }
      payloadOffsets[payload.key] = storedOffset
      let (nextOffset, overflow) = offset.addingReportingOverflow(payload.data.count)
      guard !overflow else { throw Error.limitCheck }
      offset = nextOffset
    }
    guard UInt32(exactly: offset) != nil else { throw Error.limitCheck }
  }

  private func appendRecord(_ object: Object, tag: UInt8, to writer: inout BinaryDataWriter) throws {
    let executableBit: UInt8 = object.kind == .executable ? 0x80 : 0

    switch object.type {
    case .null:
      appendHeader(type: executableBit, tag: tag, length: 0, to: &writer)
      writer.appendUInt32(0, order: format.byteOrder)
    case .integer:
      appendHeader(type: executableBit | 1, tag: tag, length: 0, to: &writer)
      writer.appendInt32(try object.value(as: IntegerValue.self).value, order: format.byteOrder)
    case .real:
      appendHeader(type: executableBit | 2, tag: tag, length: 0, to: &writer)
      writer.append(try BinaryNumberCodec.floatData(object.value(as: RealValue.self).value, format: format))
    case .name:
      let name = try object.value(as: NameValue.self).value
      let data = try name.data(using: .isoLatin1).unwrap(or: Error.limitCheck)
      guard let length = UInt16(exactly: data.count), length > 0, length <= 127,
        let offset = payloadOffsets[.name(name)]
      else {
        throw Error.limitCheck
      }
      appendHeader(type: executableBit | 3, tag: tag, length: length, to: &writer)
      writer.appendUInt32(offset, order: format.byteOrder)
    case .boolean:
      appendHeader(type: executableBit | 4, tag: tag, length: 0, to: &writer)
      let value = try object.value(as: BooleanValue.self).value
      writer.appendUInt32(value ? 1 : 0, order: format.byteOrder)
    case .string:
      let string = try object.value(as: StringValue.self)
      let key = PayloadKey.string(string.snapshotIdentity, string.refRange)
      guard let length = UInt16(exactly: string.count), let offset = payloadOffsets[key] else {
        throw Error.limitCheck
      }
      appendHeader(type: executableBit | 5, tag: tag, length: length, to: &writer)
      writer.appendUInt32(length == 0 ? 0 : offset, order: format.byteOrder)
    case .array:
      let array = try object.value(as: ArrayValue.self)
      let key = array.arrayViewIdentity
      guard let length = UInt16(exactly: array.count), let offset = arrayOffsets[key] else {
        throw Error.limitCheck
      }
      appendHeader(type: executableBit | 9, tag: tag, length: length, to: &writer)
      writer.appendUInt32(length == 0 ? 0 : offset, order: format.byteOrder)
    case .mark:
      appendHeader(type: executableBit | 10, tag: tag, length: 0, to: &writer)
      writer.appendUInt32(0, order: format.byteOrder)
    default:
      throw Error.typeCheck
    }
  }

  private func appendHeader(type: UInt8, tag: UInt8, length: UInt16, to writer: inout BinaryDataWriter) {
    writer.append(type)
    writer.append(tag)
    writer.appendUInt16(length, order: format.byteOrder)
  }
}
