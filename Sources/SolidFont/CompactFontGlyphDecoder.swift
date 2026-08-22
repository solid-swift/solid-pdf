import Foundation

package extension CompactFontCollection {
  func glyph(
    faceIndex: Int,
    glyphIndex: UInt32,
    selector: FontGlyphSelector,
    limits: FontParsingLimits = .default
  ) throws -> FontGlyph {
    guard faces.indices.contains(faceIndex), Int(exactly: glyphIndex) != nil else { throw FontError.range }
    let face = faces[faceIndex]
    let index = Int(glyphIndex)
    guard face.charStrings.indices.contains(index) else { throw FontError.range }
    let dictionary: CompactFontDictionary
    if face.isCIDKeyed {
      guard face.fontDictionarySelection.indices.contains(index) else { throw FontError.invalidData }
      let dictionaryIndex = Int(face.fontDictionarySelection[index])
      guard face.fontDictionaries.indices.contains(dictionaryIndex) else { throw FontError.invalidData }
      dictionary = face.fontDictionaries[dictionaryIndex]
    } else {
      dictionary = face.privateDictionary
    }
    let decoded = try FontCharStringDecoder.decode(
      face.charStrings[index],
      dialect: .type2,
      localSubroutines: dictionary.localSubroutines,
      globalSubroutines: globalSubroutines,
      defaultWidth: dictionary.defaultWidth,
      nominalWidth: dictionary.nominalWidth,
      limits: limits
    )
    return FontGlyph(
      selector: selector,
      metrics: FontGlyphMetrics(
        horizontalAdvance: decoded.advance,
        bounds: decoded.outline.bounds
      ),
      program: .outline(decoded.outline),
      resolvedGlyphIndex: glyphIndex
    )
  }

  func glyphIndex(faceIndex: Int, cid: UInt32) -> UInt32? {
    guard faces.indices.contains(faceIndex), cid <= UInt32(UInt16.max) else { return nil }
    let face = faces[faceIndex]
    guard face.isCIDKeyed else { return nil }
    if cid == 0 { return 0 }
    return face.charset.enumerated().first { _, identifier in
      identifier == .cid(UInt16(cid))
    }.map { UInt32($0.offset + 1) }
  }

  func glyphIndex(faceIndex: Int, encodedCode: UInt8) -> UInt32? {
    guard faces.indices.contains(faceIndex) else { return nil }
    return faces[faceIndex].encoding[encodedCode]
  }

  func glyphIndex(faceIndex: Int, glyphName: String) -> UInt32? {
    guard faces.indices.contains(faceIndex) else { return nil }
    if glyphName == ".notdef" { return 0 }
    return faces[faceIndex].charset.enumerated().first { _, identifier in
      guard case .stringIdentifier(let identifier) = identifier else { return false }
      let name: String?
      if Int(identifier) < CompactFontStandardStrings.values.count {
        name = CompactFontStandardStrings.values[Int(identifier)]
      } else {
        let index = Int(identifier) - CompactFontStandardStrings.values.count
        name = strings.indices.contains(index) ? strings[index] : nil
      }
      return name == glyphName
    }.map { UInt32($0.offset + 1) }
  }
}

private extension FontOutline {
  var bounds: FontBounds? {
    var points: [FontPoint] = []
    for element in elements {
      switch element {
      case .move(let point), .line(let point): points.append(point)
      case .quadratic(let control, let end): points.append(contentsOf: [control, end])
      case .cubic(let control1, let control2, let end): points.append(contentsOf: [control1, control2, end])
      case .close: break
      }
    }
    guard let first = points.first else { return nil }
    return FontBounds(
      minimumX: points.dropFirst().reduce(first.x) { min($0, $1.x) },
      minimumY: points.dropFirst().reduce(first.y) { min($0, $1.y) },
      maximumX: points.dropFirst().reduce(first.x) { max($0, $1.x) },
      maximumY: points.dropFirst().reduce(first.y) { max($0, $1.y) }
    )
  }
}
