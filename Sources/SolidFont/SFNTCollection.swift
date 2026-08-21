import Foundation

/// One bounded table record in an sfnt font face.
public struct SFNTTable: Sendable, Hashable {
  /// The four-byte table tag.
  public let tag: UInt32
  /// The table checksum stored by the font.
  public let checksum: UInt32
  /// The byte offset from the beginning of the font asset.
  public let offset: Int
  /// The table byte count.
  public let length: Int

  /// Creates an sfnt table record.
  public init(tag: UInt32, checksum: UInt32, offset: Int, length: Int) throws {
    guard offset >= 0, length >= 0 else { throw FontError.range }
    self.tag = tag
    self.checksum = checksum
    self.offset = offset
    self.length = length
  }
}

/// One validated face in an sfnt or TrueType collection.
public struct SFNTFace: Sendable, Hashable {
  /// The byte offset of this face's sfnt directory.
  public let offset: Int
  /// The sfnt scaler type.
  public let scalerType: UInt32
  /// Table records keyed by tag.
  public let tables: [UInt32: SFNTTable]

  /// Returns the complete bytes for a table.
  public func data(for tag: UInt32, in asset: Data) throws -> Data? {
    guard let table = tables[tag] else { return nil }
    guard table.offset <= asset.count - table.length else { throw FontError.invalidData }
    return asset.subdata(in: table.offset..<table.offset + table.length)
  }
}

/// A validated sfnt font or TrueType/OpenType collection.
public struct SFNTCollection: Sendable, Hashable {
  /// Faces in collection order.
  public let faces: [SFNTFace]

  /// Parses sfnt table directories without interpreting backend-owned glyph data.
  public init(data: Data, limits: FontParsingLimits = .default) throws {
    guard data.count >= 12, data.count <= limits.maximumDataBytes else {
      throw data.count < 12 ? FontError.invalidData : FontError.limitExceeded
    }
    let offsets: [Int]
    if try data.uint32(at: 0) == 0x7474_6366 {
      guard data.count >= 12 else { throw FontError.invalidData }
      let count = Int(try data.uint32(at: 8))
      guard count > 0, count <= limits.maximumObjects, 12 + count * 4 <= data.count else {
        throw count > limits.maximumObjects ? FontError.limitExceeded : FontError.invalidData
      }
      offsets = try (0..<count).map { Int(try data.uint32(at: 12 + $0 * 4)) }
    } else {
      offsets = [0]
    }
    var faces: [SFNTFace] = []
    faces.reserveCapacity(offsets.count)
    for faceOffset in offsets {
      guard faceOffset >= 0, faceOffset <= data.count - 12 else { throw FontError.invalidData }
      let scalerType = try data.uint32(at: faceOffset)
      guard scalerType == 0x0001_0000 || scalerType == 0x4F54_544F || scalerType == 0x7472_7565 else {
        throw FontError.unsupportedFormat
      }
      let tableCount = Int(try data.uint16(at: faceOffset + 4))
      guard tableCount <= limits.maximumObjects, faceOffset + 12 <= data.count - tableCount * 16 else {
        throw tableCount > limits.maximumObjects ? FontError.limitExceeded : FontError.invalidData
      }
      var tables: [UInt32: SFNTTable] = [:]
      tables.reserveCapacity(tableCount)
      for index in 0..<tableCount {
        let recordOffset = faceOffset + 12 + index * 16
        let tag = try data.uint32(at: recordOffset)
        let checksum = try data.uint32(at: recordOffset + 4)
        let tableOffset = Int(try data.uint32(at: recordOffset + 8))
        let length = Int(try data.uint32(at: recordOffset + 12))
        guard tableOffset <= data.count - length, tables[tag] == nil else { throw FontError.invalidData }
        tables[tag] = try SFNTTable(tag: tag, checksum: checksum, offset: tableOffset, length: length)
      }
      faces.append(SFNTFace(offset: faceOffset, scalerType: scalerType, tables: tables))
    }
    self.faces = faces
  }
}

private extension Data {
  func uint16(at offset: Int) throws -> UInt16 {
    guard offset >= 0, offset <= count - 2 else { throw FontError.invalidData }
    return UInt16(self[offset]) << 8 | UInt16(self[offset + 1])
  }

  func uint32(at offset: Int) throws -> UInt32 {
    guard offset >= 0, offset <= count - 4 else { throw FontError.invalidData }
    return UInt32(self[offset]) << 24 | UInt32(self[offset + 1]) << 16
      | UInt32(self[offset + 2]) << 8 | UInt32(self[offset + 3])
  }
}
