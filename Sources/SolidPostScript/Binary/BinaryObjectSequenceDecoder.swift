import Foundation

extension Scanner {
  func binaryObjectSequence(type: UInt8, context: isolated Context) throws -> ScannedObject {
    let format: ObjectFormat = switch type {
    case 128: .ieeeBigEndian
    case 129: .ieeeLittleEndian
    case 130: .nativeBigEndian
    case 131: .nativeLittleEndian
    default: throw Error.syntaxError
    }

    var topLevelCount = 0
    var totalSize = 0

    do {
      let initialHeader = try readBinaryData(count: 3)
      if initialHeader[0] == 0 {
        var countReader = BinaryDataReader(data: initialHeader.subdata(in: 1..<3))
        topLevelCount = Int(try countReader.readUInt16(order: format.byteOrder))
        var sizeReader = BinaryDataReader(data: try readBinaryData(count: 4))
        totalSize = Int(try sizeReader.readUInt32(order: format.byteOrder))
        guard totalSize >= 8 else { throw Error.syntaxError }
        try context.limitCheck(size: totalSize, objectType: .string)
        let body = try readBinaryData(count: totalSize - 8)
        var decoder = BinaryObjectSequenceDecoder(
          body: body,
          topLevelCount: topLevelCount,
          format: format,
          vm: context.allocationMode
        )
        let object = try decoder.decode(context: context)
        return ScannedObject(object, implicitlyExecutable: true)
      }

      topLevelCount = Int(initialHeader[0])
      var sizeReader = BinaryDataReader(data: initialHeader.subdata(in: 1..<3))
      totalSize = Int(try sizeReader.readUInt16(order: format.byteOrder))
      guard totalSize >= 4 else { throw Error.syntaxError }
      try context.limitCheck(size: totalSize, objectType: .string)
      let body = try readBinaryData(count: totalSize - 4)
      var decoder = BinaryObjectSequenceDecoder(
        body: body,
        topLevelCount: topLevelCount,
        format: format,
        vm: context.allocationMode
      )
      let object = try decoder.decode(context: context)
      return ScannedObject(object, implicitlyExecutable: true)
    } catch let failure as ScannerFailure {
      throw failure
    } catch let error as Error {
      throw ScannerFailure(
        error: error,
        command: .string("bin obj seq, type=\(type), elements=\(topLevelCount), size=\(totalSize)")
      )
    }
  }
}

private struct BinaryObjectSequenceDecoder {
  struct Region: Hashable {
    let offset: Int
    let count: Int
  }

  struct Record {
    let kind: ObjectKind
    let type: UInt8
    let length: UInt16
    let value: UInt32
    let valueData: Data
  }

  let body: Data
  let topLevelCount: Int
  let format: ObjectFormat
  let vm: VM

  private var records: [Int: Record] = [:]
  private var arrays: [Region: Object] = [:]
  private var strings: [Region: Object] = [:]

  init(
    body: Data,
    topLevelCount: Int,
    format: ObjectFormat,
    vm: VM
  ) {
    self.body = body
    self.topLevelCount = topLevelCount
    self.format = format
    self.vm = vm
  }

  mutating func decode(context: isolated Context) throws -> Object {
    let arrayBoundary = try validateRecords(context: context)
    let topLevel = Region(offset: 0, count: topLevelCount)
    try validateArray(region: topLevel, upperBound: arrayBoundary)
    try collect(region: topLevel, context: context)

    for region in arrays.keys {
      try populate(region: region, context: context)
    }

    let array = try arrays[topLevel].unwrap(or: Error.syntaxError).value(as: ArrayValue.self)
    return Object(value: array, kind: .executable)
  }

  private mutating func collect(region: Region, context: isolated Context) throws {
    guard region.offset.isMultiple(of: 8) else {
      throw Error.syntaxError
    }
    let (byteCount, countOverflow) = region.count.multipliedReportingOverflow(by: 8)
    let (upperBound, offsetOverflow) = region.offset.addingReportingOverflow(byteCount)
    guard !countOverflow, !offsetOverflow, region.offset >= 0, upperBound <= body.count else {
      throw Error.syntaxError
    }
    guard arrays[region] == nil else { return }

    try context.limitCheck(size: region.count, objectType: .array)
    arrays[region] = try .array(
      Array(repeating: .null, count: region.count),
      access: .unlimited,
      vm: vm,
      kind: .literal
    )

    for index in 0..<region.count {
      let offset = region.offset + index * 8
      let record = try records[offset].unwrap(or: Error.syntaxError)

      switch record.type {
      case 9:
        let offset = record.length == 0 ? 0 : Int(record.value)
        try collect(region: Region(offset: offset, count: Int(record.length)), context: context)
      default:
        break
      }
    }
  }

  private func parseRecord(at offset: Int) throws -> Record {
    guard offset >= 0, offset + 8 <= body.count else {
      throw Error.syntaxError
    }
    var reader = BinaryDataReader(data: body.subdata(in: offset..<offset + 8))
    let typeAndKind = try reader.readByte()
    let tag = try reader.readByte()
    let length = try reader.readUInt16(order: format.byteOrder)
    let valueData = try reader.read(count: 4)
    var valueReader = BinaryDataReader(data: valueData)
    let value = try valueReader.readUInt32(order: format.byteOrder)
    let type = typeAndKind & 0x7F
    let kind: ObjectKind = typeAndKind & 0x80 == 0 ? .literal : .executable

    guard tag == 0 else { throw Error.syntaxError }
    switch type {
    case 0, 10:
      guard length == 0, value == 0 else { throw Error.syntaxError }
    case 1:
      guard length == 0 else { throw Error.syntaxError }
    case 2:
      guard length <= 31 else { throw Error.syntaxError }
    case 3, 6:
      let signedLength = Int16(bitPattern: length)
      guard signedLength == -1 || signedLength > 0 else { throw Error.syntaxError }
    case 4:
      guard length == 0, value <= 1 else { throw Error.syntaxError }
    case 5, 9:
      break
    default:
      throw Error.syntaxError
    }

    return Record(kind: kind, type: type, length: length, value: value, valueData: valueData)
  }

  private mutating func validateRecords(context: isolated Context) throws -> Int {
    var arrayBoundary = body.count
    var offset = 0

    while offset < arrayBoundary {
      guard offset + 8 <= arrayBoundary else { throw Error.syntaxError }
      let record = try parseRecord(at: offset)
      records[offset] = record

      switch record.type {
      case 3 where Int16(bitPattern: record.length) > 0,
        6 where Int16(bitPattern: record.length) > 0:
        let region = Region(offset: Int(record.value), count: Int(record.length))
        try validateString(region: region, context: context)
        arrayBoundary = min(arrayBoundary, region.offset)
      case 5 where record.length > 0:
        let region = Region(offset: Int(record.value), count: Int(record.length))
        try validateString(region: region, context: context)
        arrayBoundary = min(arrayBoundary, region.offset)
      default:
        break
      }

      offset += 8
    }

    guard offset == arrayBoundary else { throw Error.syntaxError }
    for record in records.values where record.type == 9 && record.length > 0 {
      try validateArray(
        region: Region(offset: Int(record.value), count: Int(record.length)),
        upperBound: arrayBoundary
      )
    }
    return arrayBoundary
  }

  private func validateString(region: Region, context: isolated Context) throws {
    let (upperBound, overflow) = region.offset.addingReportingOverflow(region.count)
    guard !overflow, region.offset >= 0, upperBound <= body.count else {
      throw Error.syntaxError
    }
    try context.limitCheck(size: region.count, objectType: .string)
  }

  private func validateArray(region: Region, upperBound: Int) throws {
    guard region.offset.isMultiple(of: 8) else { throw Error.syntaxError }
    let (byteCount, countOverflow) = region.count.multipliedReportingOverflow(by: 8)
    let (regionUpperBound, offsetOverflow) = region.offset.addingReportingOverflow(byteCount)
    guard !countOverflow, !offsetOverflow, region.offset >= 0, regionUpperBound <= upperBound else {
      throw Error.syntaxError
    }
  }

  private mutating func populate(region: Region, context: isolated Context) throws {
    let array = try arrays[region].unwrap(or: Error.syntaxError).value(as: ArrayValue.self)
    for index in 0..<region.count {
      let record = try records[region.offset + index * 8].unwrap(or: Error.syntaxError)
      try array.updateObject(materialize(record, context: context), at: UInt(index))
    }
  }

  private mutating func materialize(_ record: Record, context: isolated Context) throws -> Object {
    switch record.type {
    case 0:
      return Object(value: NullValue.instance, kind: record.kind)
    case 1:
      return Object(value: IntegerValue(value: Int32(bitPattern: record.value)), kind: record.kind)
    case 2:
      let object: Object
      if record.length == 0 {
        object = try floatingReal(bits: record.value, data: record.valueData)
      } else {
        object = try BinaryNumberCodec.fixed(Int32(bitPattern: record.value), scale: Int(record.length))
      }
      return Object(value: object.value, kind: record.kind)
    case 3:
      return try name(record: record, context: context)
    case 4:
      return Object(value: BooleanValue(value: record.value == 1), kind: record.kind)
    case 5:
      let string = try string(
        region: Region(offset: record.length == 0 ? 0 : Int(record.value), count: Int(record.length)),
        context: context
      )
      return Object(value: string.value, kind: record.kind)
    case 6:
      let name = try name(record: record, context: context).value(as: NameValue.self)
      return try name.lookup(in: context)
    case 9:
      let offset = record.length == 0 ? 0 : Int(record.value)
      let array = try arrays[Region(offset: offset, count: Int(record.length))]
        .unwrap(or: Error.syntaxError)
        .value(as: ArrayValue.self)
      return Object(value: array, kind: record.kind)
    case 10:
      return Object(value: MarkValue.instance, kind: record.kind)
    default:
      throw Error.syntaxError
    }
  }

  private func floatingReal(bits: UInt32, data: Data) throws -> Object {
    switch format.realFormat {
    case .ieee:
      return try BinaryNumberCodec.ieee(bits)
    case .native:
      return try BinaryNumberCodec.native(data)
    }
  }

  private mutating func name(record: Record, context: isolated Context) throws -> Object {
    if Int16(bitPattern: record.length) == -1 {
      guard let name = SystemNameTable.name(at: Int(record.value)) else {
        throw ScannerFailure(error: .undefined, command: .executableName("system\(record.value)"))
      }
      return .name(name, kind: record.kind)
    }

    let region = Region(offset: Int(record.value), count: Int(record.length))
    try validateString(region: region, context: context)
    guard record.length <= 127,
      let value = String(data: body.subdata(in: region.offset..<region.offset + region.count), encoding: .isoLatin1)
    else {
      throw Error.limitCheck
    }
    return .name(value, kind: record.kind)
  }

  private mutating func string(region: Region, context: isolated Context) throws -> Object {
    if let string = strings[region] {
      return string
    }
    try validateString(region: region, context: context)
    let string = Object.string(
      body.subdata(in: region.offset..<region.offset + region.count),
      access: .unlimited,
      vm: vm,
      kind: .literal
    )
    strings[region] = string
    return string
  }
}
