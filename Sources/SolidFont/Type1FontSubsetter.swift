import Foundation

enum Type1FontSubsetter {
  static func subset(
    data: Data,
    descriptor: FontDescriptor,
    request: FontSubsetRequest,
    prefix: String,
    limits: FontParsingLimits
  ) throws -> FontSubset {
    guard data.count <= limits.maximumDataBytes else { throw FontError.limitExceeded }
    let subsetName = "\(prefix)+\(descriptor.postScriptName)"
    let program = try Type1Program(data: data)
    let renamed = try program.renamingFont(to: subsetName)
    let glyphs = request.glyphIndexes.enumerated().map {
      FontSubsetGlyph(originalIndex: $0.element, subsetIndex: UInt32($0.offset))
    }
    return try FontSubset(
      data: renamed.data,
      format: .type1,
      postScriptName: subsetName,
      unitsPerEm: descriptor.unitsPerEm,
      glyphs: glyphs,
      type1SegmentLengths: renamed.segmentLengths
    )
  }
}

private struct Type1Program {
  struct Segment {
    let kind: UInt8
    let data: Data
  }

  let segments: [Segment]
  let isPFB: Bool

  init(data: Data) throws {
    if data.first == 0x80 {
      var offset = 0
      var parsed: [Segment] = []
      while offset < data.count {
        guard offset <= data.count - 2, data[offset] == 0x80 else { throw FontError.invalidData }
        let kind = data[offset + 1]
        offset += 2
        if kind == 3 { break }
        guard (kind == 1 || kind == 2), offset <= data.count - 4 else { throw FontError.invalidData }
        let length = Int(data[offset]) | Int(data[offset + 1]) << 8
          | Int(data[offset + 2]) << 16 | Int(data[offset + 3]) << 24
        offset += 4
        guard length >= 0, offset <= data.count - length else { throw FontError.invalidData }
        parsed.append(Segment(kind: kind, data: data.subdata(in: offset..<offset + length)))
        offset += length
      }
      guard !parsed.isEmpty, parsed[0].kind == 1 else { throw FontError.invalidData }
      self.segments = parsed
      self.isPFB = true
    } else {
      guard data.starts(with: Data("%!".utf8)) else { throw FontError.unsupportedFormat }
      self.segments = [Segment(kind: 1, data: data)]
      self.isPFB = false
    }
  }

  func renamingFont(to name: String) throws -> (data: Data, segmentLengths: [Int]) {
    var result = segments
    guard let first = result.indices.first else { throw FontError.invalidData }
    let bytes = result[first].data
    guard let marker = bytes.range(of: Data("/FontName".utf8)) else { throw FontError.invalidData }
    var cursor = marker.upperBound
    while cursor < bytes.endIndex, bytes[cursor] == 0x20 || bytes[cursor] == 0x09 { cursor += 1 }
    guard cursor < bytes.endIndex, bytes[cursor] == 0x2F else { throw FontError.invalidData }
    let nameStart = cursor + 1
    var nameEnd = nameStart
    while nameEnd < bytes.endIndex, !isDelimiter(bytes[nameEnd]) { nameEnd += 1 }
    var renamed = bytes
    renamed.replaceSubrange(nameStart..<nameEnd, with: name.utf8)
    result[first] = Segment(kind: result[first].kind, data: renamed)
    if !isPFB { return (renamed, [renamed.count, 0, 0]) }
    var output = Data()
    for segment in result {
      output.append(0x80)
      output.append(segment.kind)
      let count = UInt32(segment.data.count)
      output.append(UInt8(truncatingIfNeeded: count))
      output.append(UInt8(truncatingIfNeeded: count >> 8))
      output.append(UInt8(truncatingIfNeeded: count >> 16))
      output.append(UInt8(truncatingIfNeeded: count >> 24))
      output.append(segment.data)
    }
    output.append(contentsOf: [0x80, 0x03])
    let lengths = [
      result.filter { $0.kind == 1 }.reduce(0) { $0 + $1.data.count },
      result.filter { $0.kind == 2 }.reduce(0) { $0 + $1.data.count },
      0,
    ]
    return (output, lengths)
  }

  private func isDelimiter(_ byte: UInt8) -> Bool {
    byte <= 0x20 || [0x28, 0x29, 0x3C, 0x3E, 0x5B, 0x5D, 0x7B, 0x7D, 0x2F, 0x25].contains(byte)
  }
}
