import Foundation

enum CFFFontSubsetter {
  static func subset(
    data: Data,
    faceIndex: Int,
    descriptor: FontDescriptor,
    request: FontSubsetRequest,
    prefix: String,
    limits: FontParsingLimits
  ) throws -> FontSubset {
    let collection = try CompactFontCollection(data: data, limits: limits)
    guard collection.faces.indices.contains(faceIndex) else { throw FontError.range }
    let face = collection.faces[faceIndex]
    let selected = request.glyphIndexes
    guard selected.count <= limits.maximumGlyphs,
      selected.allSatisfy({ Int($0) < face.charStrings.count })
    else { throw FontError.range }

    let subsetName = "\(prefix)+\(descriptor.postScriptName)"
    let glyphs = selected.enumerated().map { subsetIndex, originalIndex in
      let identifier = originalIndex == 0 ? nil : face.charset[Int(originalIndex) - 1]
      return FontSubsetGlyph(
        originalIndex: originalIndex,
        subsetIndex: UInt32(subsetIndex),
        name: identifier.flatMap { if case .stringIdentifier(let sid) = $0 { return "sid\(sid)" }; return nil },
        cid: identifier.flatMap { if case .cid(let cid) = $0 { return UInt32(cid) }; return nil }
      )
    }
    let bytes = try CFFWriter(
      face: face,
      globalSubroutines: collection.globalSubroutines,
      strings: collection.strings,
      selectedGlyphs: selected,
      subsetName: subsetName,
      limits: limits
    ).write()
    _ = try CompactFontCollection(data: bytes, limits: limits)
    return try FontSubset(
      data: bytes,
      format: face.isCIDKeyed ? .cidKeyedCFF : .nameKeyedCFF,
      postScriptName: subsetName,
      unitsPerEm: descriptor.unitsPerEm,
      glyphs: glyphs
    )
  }
}

private struct CFFWriter {
  let face: CompactFontFace
  let globalSubroutines: [Data]
  let strings: [String]
  let selectedGlyphs: [UInt32]
  let subsetName: String
  let limits: FontParsingLimits

  func write() throws -> Data {
    let nameIndex = try index([Data(subsetName.utf8)])
    let stringValues = strings + (face.isCIDKeyed ? ["Adobe", "Identity"] : [])
    let stringIndex = try index(stringValues.map { Data($0.utf8) })
    let globalIndex = try index(globalSubroutines)
    let header = Data([1, 0, 4, 4])
    var topDictionary = Data()
    var body = Data()
    for _ in 0..<8 {
      let topIndex = try index([topDictionary])
      let bodyStart = header.count + nameIndex.count + topIndex.count + stringIndex.count + globalIndex.count
      let result = try buildBody(startingAt: bodyStart, stringCount: strings.count)
      body = result.data
      let next = result.topDictionary
      if next == topDictionary {
        var output = header
        output.append(nameIndex)
        output.append(topIndex)
        output.append(stringIndex)
        output.append(globalIndex)
        output.append(body)
        guard output.count <= limits.maximumDataBytes else { throw FontError.limitExceeded }
        return output
      }
      topDictionary = next
    }
    throw FontError.invalidData
  }

  private func buildBody(startingAt start: Int, stringCount: Int) throws -> (data: Data, topDictionary: Data) {
    let charset = try charsetData()
    let encoding = try encodingData()
    var data = Data()
    let charsetOffset = start
    data.append(charset)
    let encodingOffset = start + data.count
    if let encoding { data.append(encoding) }

    if face.isCIDKeyed {
      let fdSelectOffset = start + data.count
      let fdSelect = try fontDictionarySelectionData()
      data.append(fdSelect)

      var fontDictionaryIndex = Data()
      var privateBlocks = Data()
      var privateOffsets: [(size: Int, offset: Int)] = []
      var charStringsOffset = 0
      for _ in 0..<8 {
        let fdArrayOffset = start + data.count
        charStringsOffset = fdArrayOffset + fontDictionaryIndex.count + privateBlocks.count
        let dictionaries = face.fontDictionaries.enumerated().map { index, dictionary -> Data in
          let privateValue: (size: Int, offset: Int) = privateOffsets.indices.contains(index)
            ? privateOffsets[index] : (size: 0, offset: 0)
          return dict([
            ([Double(privateValue.size), Double(privateValue.offset)], 18),
          ])
        }
        let nextFDArray = try index(dictionaries)
        let privateStart = fdArrayOffset + nextFDArray.count
        var nextPrivateBlocks = Data()
        var nextOffsets: [(Int, Int)] = []
        for dictionary in face.fontDictionaries {
          let block = try privateBlock(dictionary)
          nextOffsets.append((block.dictionaryLength, privateStart + nextPrivateBlocks.count))
          nextPrivateBlocks.append(block.data)
        }
        if nextFDArray == fontDictionaryIndex, nextOffsets.elementsEqual(privateOffsets, by: ==) {
          fontDictionaryIndex = nextFDArray
          privateBlocks = nextPrivateBlocks
          break
        }
        fontDictionaryIndex = nextFDArray
        privateBlocks = nextPrivateBlocks
        privateOffsets = nextOffsets
      }
      let fdArrayOffset = start + data.count
      data.append(fontDictionaryIndex)
      data.append(privateBlocks)
      charStringsOffset = start + data.count
      data.append(try charStringsData())
      let registrySID = 391 + stringCount
      let orderingSID = registrySID + 1
      let top = dict([
        ([Double(registrySID), Double(orderingSID), 0], 0x0C1E),
        ([Double(charsetOffset)], 15),
        ([Double(charStringsOffset)], 17),
        ([Double(fdArrayOffset)], 0x0C24),
        ([Double(fdSelectOffset)], 0x0C25),
      ])
      return (data, top)
    }

    let privateData = try privateBlock(face.privateDictionary)
    let privateOffset = start + data.count
    data.append(privateData.data)
    let charStringsOffset = start + data.count
    data.append(try charStringsData())
    let top = dict([
      ([Double(charsetOffset)], 15),
      ([Double(encoding == nil ? 0 : encodingOffset)], 16),
      ([Double(charStringsOffset)], 17),
      ([Double(privateData.dictionaryLength), Double(privateOffset)], 18),
    ])
    return (data, top)
  }

  private func charsetData() throws -> Data {
    var result = Data([0])
    for original in selectedGlyphs.dropFirst() {
      let identifier = face.charset[Int(original) - 1]
      let value: UInt16
      switch identifier {
      case .stringIdentifier(let sid): value = sid
      case .cid(let cid): value = cid
      }
      result.append(UInt8(truncatingIfNeeded: value >> 8))
      result.append(UInt8(truncatingIfNeeded: value))
    }
    return result
  }

  private func encodingData() throws -> Data? {
    guard !face.isCIDKeyed else { return nil }
    let reverse = Dictionary(uniqueKeysWithValues: face.encoding.map { ($0.value, $0.key) })
    let codes = selectedGlyphs.dropFirst().compactMap { reverse[$0] }
    guard codes.count == selectedGlyphs.count - 1, codes.count <= 255 else { return nil }
    var result = Data([0, UInt8(codes.count)])
    result.append(contentsOf: codes)
    return result
  }

  private func fontDictionarySelectionData() throws -> Data {
    guard selectedGlyphs.count <= 255 else {
      var result = Data([3])
      let ranges = selectedGlyphs.enumerated().map { ($0.offset, face.fontDictionarySelection[Int($0.element)]) }
      let reduced = ranges.enumerated().filter { index, value in index == 0 || value.1 != ranges[index - 1].1 }
      guard reduced.count <= 255 else { throw FontError.limitExceeded }
      result.append(UInt8(reduced.count))
      for range in reduced {
        result.append(UInt8(truncatingIfNeeded: range.element.0 >> 8))
        result.append(UInt8(truncatingIfNeeded: range.element.0))
        result.append(UInt8(truncatingIfNeeded: range.element.1))
      }
      result.append(UInt8(truncatingIfNeeded: selectedGlyphs.count >> 8))
      result.append(UInt8(truncatingIfNeeded: selectedGlyphs.count))
      return result
    }
    var result = Data([0])
    for glyph in selectedGlyphs {
      let selection = face.fontDictionarySelection[Int(glyph)]
      guard selection <= UInt8.max else { throw FontError.limitExceeded }
      result.append(UInt8(selection))
    }
    return result
  }

  private func charStringsData() throws -> Data {
    try index(selectedGlyphs.map { face.charStrings[Int($0)] })
  }

  private func privateBlock(_ dictionary: CompactFontDictionary) throws -> (data: Data, dictionaryLength: Int) {
    var privateDictionary = dict([
      ([dictionary.defaultWidth], 20),
      ([dictionary.nominalWidth], 21),
    ])
    guard !dictionary.localSubroutines.isEmpty else { return (privateDictionary, privateDictionary.count) }
    for _ in 0..<4 {
      let next = dict([
        ([Double(privateDictionary.count)], 19),
        ([dictionary.defaultWidth], 20),
        ([dictionary.nominalWidth], 21),
      ])
      if next == privateDictionary { break }
      privateDictionary = next
    }
    let dictionaryLength = privateDictionary.count
    privateDictionary.append(try index(dictionary.localSubroutines))
    return (privateDictionary, dictionaryLength)
  }

  private func index(_ objects: [Data]) throws -> Data {
    guard objects.count <= UInt16.max, objects.count <= limits.maximumObjects else {
      throw FontError.limitExceeded
    }
    var result = Data([UInt8(truncatingIfNeeded: objects.count >> 8), UInt8(truncatingIfNeeded: objects.count)])
    guard !objects.isEmpty else { return result }
    let payloadCount = objects.reduce(0) { $0 + $1.count }
    guard payloadCount <= limits.maximumIndexBytes else { throw FontError.limitExceeded }
    let maximumOffset = payloadCount + 1
    let offsetSize = maximumOffset <= 0xFF ? 1 : maximumOffset <= 0xFFFF ? 2 : maximumOffset <= 0xFF_FFFF ? 3 : 4
    result.append(UInt8(offsetSize))
    var offset = 1
    for object in objects {
      appendUnsigned(offset, bytes: offsetSize, to: &result)
      offset += object.count
    }
    appendUnsigned(offset, bytes: offsetSize, to: &result)
    for object in objects { result.append(object) }
    return result
  }

  private func dict(_ entries: [([Double], UInt16)]) -> Data {
    var result = Data()
    for (operands, operation) in entries {
      for operand in operands { appendDictionaryNumber(operand, to: &result) }
      if operation & 0xFF00 == 0x0C00 {
        result.append(12)
        result.append(UInt8(truncatingIfNeeded: operation))
      } else {
        result.append(UInt8(truncatingIfNeeded: operation))
      }
    }
    return result
  }

  private func appendDictionaryNumber(_ value: Double, to data: inout Data) {
    let integer = Int32(value.rounded())
    data.append(29)
    data.append(UInt8(truncatingIfNeeded: integer >> 24))
    data.append(UInt8(truncatingIfNeeded: integer >> 16))
    data.append(UInt8(truncatingIfNeeded: integer >> 8))
    data.append(UInt8(truncatingIfNeeded: integer))
  }

  private func appendUnsigned(_ value: Int, bytes: Int, to data: inout Data) {
    for shift in stride(from: (bytes - 1) * 8, through: 0, by: -8) {
      data.append(UInt8(truncatingIfNeeded: value >> shift))
    }
  }
}
