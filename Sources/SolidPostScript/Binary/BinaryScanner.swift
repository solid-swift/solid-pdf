import Foundation

struct ScannedObject {
  let object: Object
  let implicitlyExecutable: Bool

  init(_ object: Object, implicitlyExecutable: Bool = false) {
    self.object = object
    self.implicitlyExecutable = implicitlyExecutable
  }
}

struct ScannerFailure: Swift.Error {
  enum Command {
    case executableName(String)
    case string(String)
  }

  let error: Error
  let command: Command
}

extension Scanner {
  func nextObject(context: isolated Context) throws -> ScannedObject? {
    guard let lexeme = try nextLexeme(binaryEnabled: context.objectFormat.binaryEnabled) else {
      return nil
    }

    switch lexeme {
    case .token(let token):
      return ScannedObject(try object(from: token, context: context))
    case .binary(let type):
      return try binaryObject(type: type, context: context)
    case .procedureOpen:
      return ScannedObject(try procedure(context: context))
    case .procedureClose, .unmatchedClose:
      throw Error.syntaxError
    }
  }

  private func procedure(context: isolated Context) throws -> Object {
    var objects: [Object] = []

    while let lexeme = try nextLexeme(binaryEnabled: context.objectFormat.binaryEnabled) {
      switch lexeme {
      case .token(let token):
        objects.append(try object(from: token, context: context))
      case .binary(let type):
        objects.append(try binaryObject(type: type, context: context).object)
      case .procedureOpen:
        objects.append(try procedure(context: context))
      case .procedureClose:
        try context.limitCheck(size: objects.count, objectType: .array)
        return try context.packingMode == .packed
          ? .packedArray(objects, vm: context.allocationMode, kind: .executable)
          : .array(objects, access: .unlimited, vm: context.allocationMode, kind: .executable)
      case .unmatchedClose:
        throw Error.syntaxError
      }
    }

    throw Error.syntaxError
  }

  private func object(from token: Token, context: isolated Context) throws -> Object {
    switch token {
    case .integer(let int): return int.numericObject
    case .real(let real): return try real.numericObject
    case .string(let string):
      try context.limitCheck(size: string.count, objectType: .string)
      return .string(string, access: .unlimited, vm: context.allocationMode, kind: .literal)
    case .name(let name, kind: let kind):
      if name.starts(with: "/") {
        return try NameValue(value: String(name.dropFirst())).lookup(in: context)
      } else {
        return .name(name, kind: kind)
      }
    }
  }

  private func binaryObject(type: UInt8, context: isolated Context) throws -> ScannedObject {
    do {
      switch type {
      case 128...131:
        return try binaryObjectSequence(type: type, context: context)
      case 132:
        return ScannedObject(.integer(try readInt32(order: .bigEndian)))
      case 133:
        return ScannedObject(.integer(try readInt32(order: .littleEndian)))
      case 134:
        return ScannedObject(.integer(Int32(try readInt16(order: .bigEndian))))
      case 135:
        return ScannedObject(.integer(Int32(try readInt16(order: .littleEndian))))
      case 136:
        return ScannedObject(.integer(Int32(Int8(bitPattern: try readBinaryByte()))))
      case 137:
        return ScannedObject(try fixedPointToken())
      case 138:
        return ScannedObject(try BinaryNumberCodec.ieee(readUInt32(order: .bigEndian)))
      case 139:
        return ScannedObject(try BinaryNumberCodec.ieee(readUInt32(order: .littleEndian)))
      case 140:
        return ScannedObject(try BinaryNumberCodec.native(readBinaryData(count: 4)))
      case 141:
        let byte = try readBinaryByte()
        guard byte <= 1 else { throw Error.syntaxError }
        return ScannedObject(.boolean(byte == 1))
      case 142:
        return ScannedObject(try binaryString(length: Int(readBinaryByte()), context: context))
      case 143:
        return ScannedObject(try binaryString(length: Int(readUInt16(order: .bigEndian)), context: context))
      case 144:
        return ScannedObject(try binaryString(length: Int(readUInt16(order: .littleEndian)), context: context))
      case 145:
        return ScannedObject(try systemName(index: Int(readBinaryByte()), kind: .literal))
      case 146:
        return ScannedObject(try systemName(index: Int(readBinaryByte()), kind: .executable))
      case 149:
        return ScannedObject(try homogeneousNumberArray(context: context))
      default:
        throw Error.syntaxError
      }
    } catch let failure as ScannerFailure {
      throw failure
    } catch let error as Error {
      throw ScannerFailure(error: error, command: .string("bin token, type=\(type)"))
    }
  }

  private func fixedPointToken() throws -> Object {
    let representation = try readBinaryByte()
    switch representation {
    case 0...31:
      return try BinaryNumberCodec.fixed(readInt32(order: .bigEndian), scale: Int(representation))
    case 32...47:
      return try BinaryNumberCodec.fixed(readInt16(order: .bigEndian), scale: Int(representation - 32))
    case 128...159:
      return try BinaryNumberCodec.fixed(readInt32(order: .littleEndian), scale: Int(representation - 128))
    case 160...175:
      return try BinaryNumberCodec.fixed(readInt16(order: .littleEndian), scale: Int(representation - 160))
    default:
      throw Error.syntaxError
    }
  }

  private func homogeneousNumberArray(context: isolated Context) throws -> Object {
    let representation = try readBinaryByte()
    let headerPrefix = Data([149, representation])
    let order: ObjectFormat.ByteOrder = representation < 128 ? .bigEndian : .littleEndian
    let countBytes = try readBinaryData(count: 2)
    var countReader = BinaryDataReader(data: countBytes)
    let count = Int(try countReader.readUInt16(order: order))

    let partialHeader = headerPrefix + countBytes
    let header = try EncodedNumberString.header(from: partialHeader)
    let (payloadSize, overflow) = count.multipliedReportingOverflow(by: header.width)
    guard !overflow else { throw Error.limitCheck }
    try context.limitCheck(size: count, objectType: .array)

    let objects = try EncodedNumberString.decode(partialHeader + readBinaryData(count: payloadSize))
    return try .array(objects, access: .unlimited, vm: context.allocationMode, kind: .literal)
  }

  private func binaryString(length: Int, context: isolated Context) throws -> Object {
    try context.limitCheck(size: length, objectType: .string)
    return .string(
      try readBinaryData(count: length),
      access: .unlimited,
      vm: context.allocationMode,
      kind: .literal
    )
  }

  func systemName(index: Int, kind: ObjectKind) throws -> Object {
    guard let name = SystemNameTable.name(at: index) else {
      throw ScannerFailure(error: .undefined, command: .executableName("system\(index)"))
    }
    return .name(name, kind: kind)
  }

  private func readUInt16(order: ObjectFormat.ByteOrder) throws -> UInt16 {
    var reader = BinaryDataReader(data: try readBinaryData(count: 2))
    return try reader.readUInt16(order: order)
  }

  private func readInt16(order: ObjectFormat.ByteOrder) throws -> Int16 {
    var reader = BinaryDataReader(data: try readBinaryData(count: 2))
    return try reader.readInt16(order: order)
  }

  private func readUInt32(order: ObjectFormat.ByteOrder) throws -> UInt32 {
    var reader = BinaryDataReader(data: try readBinaryData(count: 4))
    return try reader.readUInt32(order: order)
  }

  private func readInt32(order: ObjectFormat.ByteOrder) throws -> Int32 {
    var reader = BinaryDataReader(data: try readBinaryData(count: 4))
    return try reader.readInt32(order: order)
  }
}
