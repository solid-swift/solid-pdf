import Foundation

/// A validated Unicode character map extracted from an sfnt face.
public struct SFNTCharacterMap: Sendable, Hashable {
  /// Unicode scalar values mapped to original glyph indexes.
  public let mappings: [UInt32: UInt32]

  /// Parses the preferred Unicode cmap subtable from one sfnt face.
  public init(data: Data, faceIndex: Int = 0, limits: FontParsingLimits = .default) throws {
    let collection = try SFNTCollection(data: data, limits: limits)
    guard collection.faces.indices.contains(faceIndex) else { throw FontError.range }
    guard let cmap = try collection.faces[faceIndex].data(for: 0x636D_6170, in: data) else {
      throw FontError.invalidData
    }
    self.mappings = try Self.parse(cmap, limits: limits)
  }

  /// Returns the only Unicode scalar mapped to `glyphIndex`, or `nil` when absent or ambiguous.
  public func uniqueUnicodeScalar(for glyphIndex: UInt32) -> UInt32? {
    var result: UInt32?
    for (scalar, glyph) in mappings where glyph == glyphIndex {
      if result != nil { return nil }
      result = scalar
    }
    return result
  }

  private static func parse(_ data: Data, limits: FontParsingLimits) throws -> [UInt32: UInt32] {
    guard data.count >= 4 else { throw FontError.invalidData }
    let count = Int(try data.uint16BE(at: 2))
    guard count <= limits.maximumObjects, 4 + count * 8 <= data.count else {
      throw count > limits.maximumObjects ? FontError.limitExceeded : FontError.invalidData
    }
    var candidates: [(priority: Int, offset: Int)] = []
    for index in 0..<count {
      let record = 4 + index * 8
      let platform = try data.uint16BE(at: record)
      let encoding = try data.uint16BE(at: record + 2)
      let offset = Int(try data.uint32BE(at: record + 4))
      let priority: Int
      switch (platform, encoding) {
      case (3, 10): priority = 0
      case (0, _): priority = 1
      case (3, 1): priority = 2
      case (3, 0): priority = 3
      default: continue
      }
      guard offset <= data.count - 2 else { throw FontError.invalidData }
      candidates.append((priority, offset))
    }
    for candidate in candidates.sorted(by: { $0.priority < $1.priority }) {
      let format = try data.uint16BE(at: candidate.offset)
      if [0, 4, 6, 10, 12, 13].contains(format) {
        return try parseSubtable(data, offset: candidate.offset, format: format, limits: limits)
      }
    }
    throw FontError.unsupportedFormat
  }

  private static func parseSubtable(
    _ data: Data,
    offset: Int,
    format: UInt16,
    limits: FontParsingLimits
  ) throws -> [UInt32: UInt32] {
    switch format {
    case 0:
      guard offset <= data.count - 262, try data.uint16BE(at: offset + 2) >= 262 else {
        throw FontError.invalidData
      }
      return Dictionary(uniqueKeysWithValues: (0..<256).compactMap { scalar in
        let glyph = UInt32(data[offset + 6 + scalar])
        return glyph == 0 ? nil : (UInt32(scalar), glyph)
      })
    case 4:
      return try parseFormat4(data, offset: offset, limits: limits)
    case 6:
      let length = Int(try data.uint16BE(at: offset + 2))
      let first = UInt32(try data.uint16BE(at: offset + 6))
      let count = Int(try data.uint16BE(at: offset + 8))
      guard count <= limits.maximumObjects, length >= 10 + count * 2,
        offset <= data.count - length
      else { throw FontError.invalidData }
      return Dictionary(uniqueKeysWithValues: try (0..<count).compactMap { index in
        let glyph = UInt32(try data.uint16BE(at: offset + 10 + index * 2))
        return glyph == 0 ? nil : (first + UInt32(index), glyph)
      })
    case 10:
      let length = Int(try data.uint32BE(at: offset + 4))
      let first = try data.uint32BE(at: offset + 12)
      let count = Int(try data.uint32BE(at: offset + 16))
      guard count <= limits.maximumObjects, length >= 20 + count * 2,
        offset <= data.count - length
      else { throw FontError.invalidData }
      return Dictionary(uniqueKeysWithValues: try (0..<count).compactMap { index in
        let glyph = UInt32(try data.uint16BE(at: offset + 20 + index * 2))
        return glyph == 0 ? nil : (first + UInt32(index), glyph)
      })
    case 12, 13:
      let length = Int(try data.uint32BE(at: offset + 4))
      let groupCount = Int(try data.uint32BE(at: offset + 12))
      guard groupCount <= limits.maximumObjects, length >= 16 + groupCount * 12,
        offset <= data.count - length
      else { throw FontError.invalidData }
      var result: [UInt32: UInt32] = [:]
      for group in 0..<groupCount {
        let record = offset + 16 + group * 12
        let start = try data.uint32BE(at: record)
        let end = try data.uint32BE(at: record + 4)
        let firstGlyph = try data.uint32BE(at: record + 8)
        guard start <= end, end <= 0x10_FFFF,
          Int(end - start) <= limits.maximumObjects - result.count
        else { throw FontError.limitExceeded }
        for scalar in start...end {
          let glyph = format == 12 ? firstGlyph + (scalar - start) : firstGlyph
          if glyph != 0 { result[scalar] = glyph }
        }
      }
      return result
    default:
      throw FontError.unsupportedFormat
    }
  }

  private static func parseFormat4(
    _ data: Data,
    offset: Int,
    limits: FontParsingLimits
  ) throws -> [UInt32: UInt32] {
    let length = Int(try data.uint16BE(at: offset + 2))
    let segmentCount = Int(try data.uint16BE(at: offset + 6)) / 2
    guard segmentCount > 0, segmentCount <= limits.maximumObjects,
      length >= 16 + segmentCount * 8, offset <= data.count - length
    else { throw FontError.invalidData }
    let endCodes = offset + 14
    let startCodes = endCodes + segmentCount * 2 + 2
    let deltas = startCodes + segmentCount * 2
    let rangeOffsets = deltas + segmentCount * 2
    var result: [UInt32: UInt32] = [:]
    for segment in 0..<segmentCount {
      let start = UInt32(try data.uint16BE(at: startCodes + segment * 2))
      let end = UInt32(try data.uint16BE(at: endCodes + segment * 2))
      let delta = UInt32(try data.uint16BE(at: deltas + segment * 2))
      let rangeOffset = Int(try data.uint16BE(at: rangeOffsets + segment * 2))
      guard start <= end else { throw FontError.invalidData }
      if start == 0xFFFF { continue }
      guard Int(end - start) <= limits.maximumObjects - result.count else {
        throw FontError.limitExceeded
      }
      for scalar in start...end {
        let glyph: UInt32
        if rangeOffset == 0 {
          glyph = (scalar + delta) & 0xFFFF
        } else {
          let address = rangeOffsets + segment * 2 + rangeOffset + Int(scalar - start) * 2
          let raw = UInt32(try data.uint16BE(at: address))
          glyph = raw == 0 ? 0 : (raw + delta) & 0xFFFF
        }
        if glyph != 0 { result[scalar] = glyph }
      }
    }
    return result
  }
}

private extension Data {
  func uint16BE(at offset: Int) throws -> UInt16 {
    guard offset >= 0, offset <= count - 2 else { throw FontError.invalidData }
    return UInt16(self[offset]) << 8 | UInt16(self[offset + 1])
  }

  func uint32BE(at offset: Int) throws -> UInt32 {
    guard offset >= 0, offset <= count - 4 else { throw FontError.invalidData }
    return UInt32(self[offset]) << 24 | UInt32(self[offset + 1]) << 16
      | UInt32(self[offset + 2]) << 8 | UInt32(self[offset + 3])
  }
}
