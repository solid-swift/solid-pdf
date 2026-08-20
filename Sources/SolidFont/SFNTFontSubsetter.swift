import Foundation

enum SFNTFontSubsetter {
  static func subset(
    data: Data,
    faceIndex: Int,
    descriptor: FontDescriptor,
    request: FontSubsetRequest,
    forcesCompleteFace: Bool,
    prefix: String,
    limits: FontParsingLimits
  ) throws -> FontSubset {
    let collection = try SFNTCollection(data: data, limits: limits)
    guard collection.faces.indices.contains(faceIndex) else { throw FontError.range }
    let face = collection.faces[faceIndex]
    if let cff = try face.data(for: Tag.cff, in: data) {
      let cffDescriptor = try FontDescriptor(
        postScriptName: descriptor.postScriptName,
        familyName: descriptor.familyName,
        styleName: descriptor.styleName,
        unitsPerEm: descriptor.unitsPerEm
      )
      return try CFFFontSubsetter.subset(
        data: cff,
        faceIndex: 0,
        descriptor: cffDescriptor,
        request: request,
        prefix: prefix,
        limits: limits
      )
    }
    let source = try TrueTypeSource(data: data, face: face, faceIndex: faceIndex, limits: limits)
    let requested = forcesCompleteFace ? (0..<source.glyphCount).map(UInt32.init) : request.glyphIndexes
    let closure = try source.glyphClosure(requested)
    let subsetName = "\(prefix)+\(descriptor.postScriptName)"
    let rebuilt = try source.rebuild(
      glyphs: closure,
      subsetName: subsetName,
      preservesHints: request.preservesHints,
      maximumBytes: limits.maximumDataBytes
    )
    _ = try SFNTCollection(data: rebuilt.data, limits: limits)
    let glyphs = closure.enumerated().map { index, original in
      FontSubsetGlyph(
        originalIndex: original,
        subsetIndex: UInt32(index),
        advance: Double(source.horizontalAdvances[Int(original)]),
        bounds: source.bounds(for: Int(original))
      )
    }
    return try FontSubset(
      data: rebuilt.data,
      format: .trueType,
      postScriptName: subsetName,
      unitsPerEm: UInt32(source.unitsPerEm),
      metrics: .init(
        ascent: Double(source.ascent),
        descent: Double(source.descent),
        bounds: source.fontBounds
      ),
      glyphs: glyphs
    )
  }
}

private enum Tag {
  static let cmap: UInt32 = 0x636D_6170
  static let cvt: UInt32 = 0x6376_7420
  static let fpgm: UInt32 = 0x6670_676D
  static let gasp: UInt32 = 0x6761_7370
  static let glyf: UInt32 = 0x676C_7966
  static let head: UInt32 = 0x6865_6164
  static let hhea: UInt32 = 0x6868_6561
  static let hmtx: UInt32 = 0x686D_7478
  static let loca: UInt32 = 0x6C6F_6361
  static let maxp: UInt32 = 0x6D61_7870
  static let name: UInt32 = 0x6E61_6D65
  static let os2: UInt32 = 0x4F53_2F32
  static let post: UInt32 = 0x706F_7374
  static let prep: UInt32 = 0x7072_6570
  static let vhea: UInt32 = 0x7668_6561
  static let vmtx: UInt32 = 0x766D_7478
  static let cff: UInt32 = 0x4346_4620
}

private struct TrueTypeSource {
  let data: Data
  let face: SFNTFace
  let glyphCount: Int
  let unitsPerEm: UInt16
  let ascent: Int16
  let descent: Int16
  let fontBounds: FontBounds
  let glyphOffsets: [Int]
  let horizontalAdvances: [UInt16]
  let leftSideBearings: [Int16]
  let verticalAdvances: [UInt16]?
  let topSideBearings: [Int16]?
  let characterMap: [UInt32: UInt32]

  init(data: Data, face: SFNTFace, faceIndex: Int, limits: FontParsingLimits) throws {
    guard let head = try face.data(for: Tag.head, in: data), head.count >= 54,
      let maxp = try face.data(for: Tag.maxp, in: data), maxp.count >= 6,
      let hhea = try face.data(for: Tag.hhea, in: data), hhea.count >= 36,
      let hmtx = try face.data(for: Tag.hmtx, in: data),
      let loca = try face.data(for: Tag.loca, in: data),
      try face.data(for: Tag.glyf, in: data) != nil
    else { throw FontError.invalidData }
    let glyphCount = Int(try maxp.u16(4))
    guard glyphCount > 0, glyphCount <= limits.maximumGlyphs else { throw FontError.limitExceeded }
    let units = try head.u16(18)
    guard units > 0 else { throw FontError.invalidData }
    self.data = data
    self.face = face
    self.glyphCount = glyphCount
    self.unitsPerEm = units
    self.ascent = try hhea.i16(4)
    self.descent = try hhea.i16(6)
    self.fontBounds = FontBounds(
      minimumX: Double(try head.i16(36)),
      minimumY: Double(try head.i16(38)),
      maximumX: Double(try head.i16(40)),
      maximumY: Double(try head.i16(42))
    )
    let longLocations = try head.i16(50) == 1
    let locationBytes = longLocations ? 4 : 2
    guard loca.count >= (glyphCount + 1) * locationBytes else { throw FontError.invalidData }
    self.glyphOffsets = try (0...glyphCount).map { index in
      longLocations ? Int(try loca.u32(index * 4)) : Int(try loca.u16(index * 2)) * 2
    }
    guard glyphOffsets.elementsEqual(glyphOffsets.sorted()),
      let glyfLength = face.tables[Tag.glyf]?.length,
      glyphOffsets.last! <= glyfLength
    else { throw FontError.invalidData }
    let horizontalMetricCount = Int(try hhea.u16(34))
    let horizontal = try Self.metrics(
      hmtx,
      glyphCount: glyphCount,
      longMetricCount: horizontalMetricCount
    )
    self.horizontalAdvances = horizontal.advances
    self.leftSideBearings = horizontal.bearings
    if let vhea = try face.data(for: Tag.vhea, in: data), vhea.count >= 36,
      let vmtx = try face.data(for: Tag.vmtx, in: data)
    {
      let vertical = try Self.metrics(
        vmtx,
        glyphCount: glyphCount,
        longMetricCount: Int(try vhea.u16(34))
      )
      self.verticalAdvances = vertical.advances
      self.topSideBearings = vertical.bearings
    } else {
      self.verticalAdvances = nil
      self.topSideBearings = nil
    }
    self.characterMap = (try? SFNTCharacterMap(data: data, faceIndex: faceIndex).mappings) ?? [:]
  }

  func glyphClosure(_ requested: [UInt32]) throws -> [UInt32] {
    guard requested.allSatisfy({ Int($0) < glyphCount }) else { throw FontError.range }
    var selected = Set(requested)
    selected.insert(0)
    var pending = Array(selected)
    while let glyph = pending.popLast() {
      for component in try components(of: Int(glyph)) where selected.insert(component).inserted {
        pending.append(component)
      }
    }
    return selected.sorted()
  }

  func bounds(for glyph: Int) -> FontBounds? {
    guard let bytes = try? glyphData(glyph), bytes.count >= 10 else { return nil }
    return FontBounds(
      minimumX: Double((try? bytes.i16(2)) ?? 0),
      minimumY: Double((try? bytes.i16(4)) ?? 0),
      maximumX: Double((try? bytes.i16(6)) ?? 0),
      maximumY: Double((try? bytes.i16(8)) ?? 0)
    )
  }

  func rebuild(
    glyphs: [UInt32],
    subsetName: String,
    preservesHints: Bool,
    maximumBytes: Int
  ) throws -> (data: Data, mapping: [UInt32: UInt32]) {
    let mapping = Dictionary(uniqueKeysWithValues: glyphs.enumerated().map { ($0.element, UInt32($0.offset)) })
    var glyf = Data()
    var loca: [UInt32] = [0]
    for original in glyphs {
      var bytes = try glyphData(Int(original))
      try rewriteCompositeGlyph(&bytes, mapping: mapping)
      if !preservesHints { try removeInstructions(from: &bytes) }
      glyf.append(bytes)
      while !glyf.count.isMultiple(of: 4) { glyf.append(0) }
      guard glyf.count <= maximumBytes, glyf.count <= Int(UInt32.max) else { throw FontError.limitExceeded }
      loca.append(UInt32(glyf.count))
    }
    var locaData = Data()
    for offset in loca { locaData.appendU32(offset) }
    var hmtx = Data()
    for original in glyphs {
      hmtx.appendU16(horizontalAdvances[Int(original)])
      hmtx.appendI16(leftSideBearings[Int(original)])
    }
    var head = try requiredTable(Tag.head)
    head.replaceI16(1, at: 50)
    head.replaceU32(0, at: 8)
    var hhea = try requiredTable(Tag.hhea)
    hhea.replaceU16(UInt16(glyphs.count), at: 34)
    var maxp = try requiredTable(Tag.maxp)
    maxp.replaceU16(UInt16(glyphs.count), at: 4)
    var tables: [UInt32: Data] = [
      Tag.head: head,
      Tag.hhea: hhea,
      Tag.hmtx: hmtx,
      Tag.maxp: maxp,
      Tag.loca: locaData,
      Tag.glyf: glyf,
      Tag.cmap: makeCMap(mapping: mapping),
      Tag.name: makeName(subsetName),
      Tag.post: makePost(),
    ]
    if let os2 = try face.data(for: Tag.os2, in: data) { tables[Tag.os2] = os2 }
    if let advances = verticalAdvances, let bearings = topSideBearings,
      var vhea = try face.data(for: Tag.vhea, in: data)
    {
      var vmtx = Data()
      for original in glyphs {
        vmtx.appendU16(advances[Int(original)])
        vmtx.appendI16(bearings[Int(original)])
      }
      vhea.replaceU16(UInt16(glyphs.count), at: 34)
      tables[Tag.vhea] = vhea
      tables[Tag.vmtx] = vmtx
    }
    if preservesHints {
      for tag in [Tag.cvt, Tag.fpgm, Tag.prep, Tag.gasp] {
        if let table = try face.data(for: tag, in: data) { tables[tag] = table }
      }
    }
    return (try makeSFNT(tables: tables, maximumBytes: maximumBytes), mapping)
  }

  private func glyphData(_ glyph: Int) throws -> Data {
    let table = try requiredTable(Tag.glyf)
    let lower = glyphOffsets[glyph]
    let upper = glyphOffsets[glyph + 1]
    guard lower <= upper, upper <= table.count else { throw FontError.invalidData }
    return table.subdata(in: lower..<upper)
  }

  private func components(of glyph: Int) throws -> [UInt32] {
    let bytes = try glyphData(glyph)
    guard bytes.count >= 10, try bytes.i16(0) < 0 else { return [] }
    var result: [UInt32] = []
    var offset = 10
    var hasMore = true
    while hasMore {
      guard offset <= bytes.count - 4 else { throw FontError.invalidData }
      let flags = try bytes.u16(offset)
      result.append(UInt32(try bytes.u16(offset + 2)))
      offset += 4 + componentArgumentBytes(flags) + componentTransformBytes(flags)
      hasMore = flags & 0x0020 != 0
    }
    return result
  }

  private func rewriteCompositeGlyph(_ bytes: inout Data, mapping: [UInt32: UInt32]) throws {
    guard bytes.count >= 10, try bytes.i16(0) < 0 else { return }
    var offset = 10
    var hasMore = true
    while hasMore {
      guard offset <= bytes.count - 4 else { throw FontError.invalidData }
      let flags = try bytes.u16(offset)
      let original = UInt32(try bytes.u16(offset + 2))
      guard let subset = mapping[original], subset <= UInt16.max else { throw FontError.invalidData }
      bytes.replaceU16(UInt16(subset), at: offset + 2)
      offset += 4 + componentArgumentBytes(flags) + componentTransformBytes(flags)
      hasMore = flags & 0x0020 != 0
    }
  }

  private func removeInstructions(from bytes: inout Data) throws {
    guard bytes.count >= 10 else { return }
    let contourCount = try bytes.i16(0)
    if contourCount >= 0 {
      let lengthOffset = 10 + Int(contourCount) * 2
      guard lengthOffset <= bytes.count - 2 else { throw FontError.invalidData }
      let length = Int(try bytes.u16(lengthOffset))
      guard lengthOffset + 2 <= bytes.count - length else { throw FontError.invalidData }
      bytes.replaceU16(0, at: lengthOffset)
      bytes.removeSubrange(lengthOffset + 2..<lengthOffset + 2 + length)
      return
    }
    var offset = 10
    var flags: UInt16 = 0
    repeat {
      guard offset <= bytes.count - 4 else { throw FontError.invalidData }
      flags = try bytes.u16(offset)
      offset += 4 + componentArgumentBytes(flags) + componentTransformBytes(flags)
    } while flags & 0x0020 != 0
    if flags & 0x0100 != 0 {
      guard offset <= bytes.count - 2 else { throw FontError.invalidData }
      let length = Int(try bytes.u16(offset))
      guard offset + 2 <= bytes.count - length else { throw FontError.invalidData }
      bytes.replaceU16(0, at: offset)
      bytes.removeSubrange(offset + 2..<offset + 2 + length)
    }
  }

  private func requiredTable(_ tag: UInt32) throws -> Data {
    guard let table = try face.data(for: tag, in: data) else { throw FontError.invalidData }
    return table
  }

  private static func metrics(
    _ data: Data,
    glyphCount: Int,
    longMetricCount: Int
  ) throws -> (advances: [UInt16], bearings: [Int16]) {
    guard (1...glyphCount).contains(longMetricCount),
      data.count >= longMetricCount * 4 + (glyphCount - longMetricCount) * 2
    else { throw FontError.invalidData }
    var advances: [UInt16] = []
    var bearings: [Int16] = []
    advances.reserveCapacity(glyphCount)
    bearings.reserveCapacity(glyphCount)
    for glyph in 0..<glyphCount {
      if glyph < longMetricCount {
        advances.append(try data.u16(glyph * 4))
        bearings.append(try data.i16(glyph * 4 + 2))
      } else {
        advances.append(advances.last!)
        bearings.append(try data.i16(longMetricCount * 4 + (glyph - longMetricCount) * 2))
      }
    }
    return (advances, bearings)
  }

  private func componentArgumentBytes(_ flags: UInt16) -> Int { flags & 0x0001 != 0 ? 4 : 2 }

  private func componentTransformBytes(_ flags: UInt16) -> Int {
    if flags & 0x0008 != 0 { return 2 }
    if flags & 0x0040 != 0 { return 4 }
    if flags & 0x0080 != 0 { return 8 }
    return 0
  }

  private func makeCMap(mapping: [UInt32: UInt32]) -> Data {
    let values = characterMap.compactMap { scalar, original -> (UInt32, UInt32)? in
      mapping[original].map { (scalar, $0) }
    }.sorted { $0.0 < $1.0 }
    var groups: [(UInt32, UInt32, UInt32)] = []
    for value in values {
      if let last = groups.last,
        value.0 == last.1 + 1, value.1 == last.2 + (value.0 - last.0)
      {
        groups[groups.count - 1].1 = value.0
      } else {
        groups.append((value.0, value.0, value.1))
      }
    }
    var subtable = Data()
    subtable.appendU16(12)
    subtable.appendU16(0)
    subtable.appendU32(UInt32(16 + groups.count * 12))
    subtable.appendU32(0)
    subtable.appendU32(UInt32(groups.count))
    for group in groups {
      subtable.appendU32(group.0)
      subtable.appendU32(group.1)
      subtable.appendU32(group.2)
    }
    var result = Data()
    result.appendU16(0)
    result.appendU16(1)
    result.appendU16(3)
    result.appendU16(10)
    result.appendU32(12)
    result.append(subtable)
    return result
  }

  private func makeName(_ postScriptName: String) -> Data {
    let family = postScriptName.split(separator: "+", maxSplits: 1).last.map(String.init) ?? postScriptName
    let values: [(UInt16, String)] = [(1, family), (2, "Regular"), (4, family), (6, postScriptName)]
    var strings = Data()
    var records = Data()
    for (nameID, value) in values {
      let encoded = Data(value.utf16.flatMap { [UInt8(truncatingIfNeeded: $0 >> 8), UInt8(truncatingIfNeeded: $0)] })
      records.appendU16(3)
      records.appendU16(1)
      records.appendU16(0x0409)
      records.appendU16(nameID)
      records.appendU16(UInt16(encoded.count))
      records.appendU16(UInt16(strings.count))
      strings.append(encoded)
    }
    var result = Data()
    result.appendU16(0)
    result.appendU16(UInt16(values.count))
    result.appendU16(UInt16(6 + records.count))
    result.append(records)
    result.append(strings)
    return result
  }

  private func makePost() -> Data {
    var result = (try? face.data(for: Tag.post, in: data)) ?? Data(repeating: 0, count: 32)
    if result.count < 32 { result.append(Data(repeating: 0, count: 32 - result.count)) }
    result.replaceU32(0x0003_0000, at: 0)
    return result.prefix(32)
  }

  private func makeSFNT(tables: [UInt32: Data], maximumBytes: Int) throws -> Data {
    let ordered = tables.sorted { $0.key < $1.key }
    guard ordered.count <= UInt16.max else { throw FontError.limitExceeded }
    let maximumPower = 1 << Int(floor(log2(Double(ordered.count))))
    var output = Data()
    output.appendU32(0x0001_0000)
    output.appendU16(UInt16(ordered.count))
    output.appendU16(UInt16(maximumPower * 16))
    output.appendU16(UInt16(Int(log2(Double(maximumPower)))))
    output.appendU16(UInt16(ordered.count * 16 - maximumPower * 16))
    let directoryStart = output.count
    output.append(Data(repeating: 0, count: ordered.count * 16))
    var headOffset: Int?
    for (index, entry) in ordered.enumerated() {
      while !output.count.isMultiple(of: 4) { output.append(0) }
      let offset = output.count
      var table = entry.value
      if entry.key == Tag.head {
        table.replaceU32(0, at: 8)
        headOffset = offset
      }
      output.append(table)
      let record = directoryStart + index * 16
      output.replaceU32(entry.key, at: record)
      output.replaceU32(checksum(table), at: record + 4)
      output.replaceU32(UInt32(offset), at: record + 8)
      output.replaceU32(UInt32(table.count), at: record + 12)
      guard output.count <= maximumBytes else { throw FontError.limitExceeded }
    }
    while !output.count.isMultiple(of: 4) { output.append(0) }
    guard let headOffset else { throw FontError.invalidData }
    let adjustment = 0xB1B0_AFBA &- checksum(output)
    output.replaceU32(adjustment, at: headOffset + 8)
    return output
  }

  private func checksum(_ data: Data) -> UInt32 {
    var sum: UInt32 = 0
    var offset = 0
    while offset < data.count {
      var value: UInt32 = 0
      for index in 0..<4 {
        value <<= 8
        if offset + index < data.count { value |= UInt32(data[offset + index]) }
      }
      sum &+= value
      offset += 4
    }
    return sum
  }
}

private extension Data {
  func u16(_ offset: Int) throws -> UInt16 {
    guard offset >= 0, offset <= count - 2 else { throw FontError.invalidData }
    return UInt16(self[offset]) << 8 | UInt16(self[offset + 1])
  }

  func i16(_ offset: Int) throws -> Int16 { Int16(bitPattern: try u16(offset)) }

  func u32(_ offset: Int) throws -> UInt32 {
    guard offset >= 0, offset <= count - 4 else { throw FontError.invalidData }
    return UInt32(self[offset]) << 24 | UInt32(self[offset + 1]) << 16
      | UInt32(self[offset + 2]) << 8 | UInt32(self[offset + 3])
  }

  mutating func appendU16(_ value: UInt16) {
    append(UInt8(truncatingIfNeeded: value >> 8))
    append(UInt8(truncatingIfNeeded: value))
  }

  mutating func appendI16(_ value: Int16) { appendU16(UInt16(bitPattern: value)) }

  mutating func appendU32(_ value: UInt32) {
    append(UInt8(truncatingIfNeeded: value >> 24))
    append(UInt8(truncatingIfNeeded: value >> 16))
    append(UInt8(truncatingIfNeeded: value >> 8))
    append(UInt8(truncatingIfNeeded: value))
  }

  mutating func replaceU16(_ value: UInt16, at offset: Int) {
    self[offset] = UInt8(truncatingIfNeeded: value >> 8)
    self[offset + 1] = UInt8(truncatingIfNeeded: value)
  }

  mutating func replaceI16(_ value: Int16, at offset: Int) {
    replaceU16(UInt16(bitPattern: value), at: offset)
  }

  mutating func replaceU32(_ value: UInt32, at offset: Int) {
    self[offset] = UInt8(truncatingIfNeeded: value >> 24)
    self[offset + 1] = UInt8(truncatingIfNeeded: value >> 16)
    self[offset + 2] = UInt8(truncatingIfNeeded: value >> 8)
    self[offset + 3] = UInt8(truncatingIfNeeded: value)
  }
}
