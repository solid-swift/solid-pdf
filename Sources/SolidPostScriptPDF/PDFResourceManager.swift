import Foundation
import SolidFont
import SolidPDF
import SolidPostScript
import SolidRaster

struct PDFFontSelection {
  let name: PDFName
  let code: Data
  let size: Double
}

private extension GraphicsBlendMode {
  var pdfName: String {
    switch self {
    case .normal: "Normal"
    case .multiply: "Multiply"
    case .screen: "Screen"
    case .overlay: "Overlay"
    case .darken: "Darken"
    case .lighten: "Lighten"
    case .colorDodge: "ColorDodge"
    case .colorBurn: "ColorBurn"
    case .hardLight: "HardLight"
    case .softLight: "SoftLight"
    case .difference: "Difference"
    case .exclusion: "Exclusion"
    case .hue: "Hue"
    case .saturation: "Saturation"
    case .color: "Color"
    case .luminosity: "Luminosity"
    }
  }
}

final class PDFResourceManager<Sink: PDFOutputSink> {
  private struct NamedReference {
    let name: PDFName
    let reference: PDFObjectReference
  }

  private struct TransparencyKey: Hashable {
    let state: GraphicsTransparencyState
    let strokingAlpha: Double
    let nonstrokingAlpha: Double
  }

  private var images: [GraphicsImage: NamedReference] = [:]
  private var rasterImages: [RasterImage: NamedReference] = [:]
  private var forms: [GraphicsForm: NamedReference] = [:]
  private var transparencyGroups: [GraphicsTransparencyGroup: NamedReference] = [:]
  private var patterns: [GraphicsPatternPaint: NamedReference] = [:]
  private var shadings: [GraphicsShading: NamedReference] = [:]
  private var colorSpaces: [GraphicsColorSpaceDescription: NamedReference] = [:]
  private var overprintStates: [Bool: NamedReference] = [:]
  private var transparencyStates: [TransparencyKey: NamedReference] = [:]
  private var plannedGlyphs: [PDFFontGroupKey: [PDFFontGlyphKey: PDFFontSelection]] = [:]
  private var xObjects: [PDFName: PDFObjectReference] = [:]
  private var shadingObjects: [PDFName: PDFObjectReference] = [:]
  private var patternObjects: [PDFName: PDFObjectReference] = [:]
  private var colorSpaceObjects: [PDFName: PDFObjectReference] = [:]
  private var graphicsStates: [PDFName: PDFObjectReference] = [:]
  private var fontObjects: [PDFName: PDFObjectReference] = [:]
  private let resourcesReference: PDFObjectReference

  init(resourcesReference: PDFObjectReference) {
    self.resourcesReference = resourcesReference
  }

  func prepareFonts(
    _ catalog: PDFFontUsageCatalog,
    version: PDFVersion,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> [PDFDiagnostic] {
    var diagnostics: [PDFDiagnostic] = []
    for groupKey in catalog.order {
      guard let group = catalog.groups[groupKey] else { continue }
      if let asset = group.font.asset,
        asset.format != .type1 || version == .v1_7,
        group.glyphs.allSatisfy({ $0.resolvedIndex != nil }),
        try prepareEmbeddedFont(group, asset: asset, writer: &writer)
      {
        continue
      }
      try prepareType3Fonts(group, writer: &writer)
      diagnostics.append(PDFDiagnostic(
        kind: .rendering,
        message: "Represented font \(group.font.postScriptName ?? group.font.identifier.value) "
          + "as an aggregated PDF Type 3 font because its binary program was unavailable, "
          + "restricted, unsupported, or unsafe for this PDF version."
      ))
    }
    return diagnostics
  }

  func fontSelection(
    font: GraphicsFontDescription,
    glyph: GraphicsGlyphDescription
  ) -> PDFFontSelection? {
    plannedGlyphs[PDFFontGroupKey(font: font)]?[PDFFontGlyphKey(glyph)]
  }

  private func prepareEmbeddedFont(
    _ group: PDFFontUsageGroup,
    asset: FontAsset,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> Bool {
    let indexes = group.glyphs.compactMap(\.resolvedIndex)
    let subset: FontSubset
    do {
      subset = try FontSubsetter.subset(asset, request: FontSubsetRequest(glyphIndexes: indexes))
    } catch {
      return false
    }
    switch subset.format {
    case .nameKeyedCFF:
      return try prepareNameKeyedCFF(group, asset: asset, subset: subset, writer: &writer)
    case .cidKeyedCFF:
      return try prepareCIDKeyedCFF(group, subset: subset, writer: &writer)
    case .type1:
      return try prepareType1(group, subset: subset, writer: &writer)
    case .trueType:
      break
    }
    let name = PDFName("F\(fontObjects.count + 1)")
    let fontReference = try writer.reserveObject()
    let descendantReference = try writer.reserveObject()
    let descriptorReference = try writer.reserveObject()
    let programReference = try writer.reserveObject()
    let mapReference = try writer.reserveObject()
    let unicodeEntries = group.glyphs.enumerated().compactMap { index, key -> (Int, [UInt32])? in
      group.uses[key]?.unicode.map { (index + 1, $0) }
    }
    let toUnicodeReference = unicodeEntries.isEmpty ? nil : try writer.reserveObject()
    fontObjects[name] = fontReference

    var selections: [PDFFontGlyphKey: PDFFontSelection] = [:]
    var cidToGID = Data(repeating: 0, count: (group.glyphs.count + 1) * 2)
    var widths: [PDFObject] = []
    for (offset, key) in group.glyphs.enumerated() {
      guard let original = key.resolvedIndex, let subsetIndex = subset.glyphMapping[original],
        let use = group.uses[key]
      else { return false }
      let code = offset + 1
      cidToGID[code * 2] = UInt8(truncatingIfNeeded: subsetIndex >> 8)
      cidToGID[code * 2 + 1] = UInt8(truncatingIfNeeded: subsetIndex)
      let width = use.glyph.metrics.horizontalAdvance.x * 1_000 / Double(subset.unitsPerEm)
      widths.append(.real(width))
      selections[key] = PDFFontSelection(
        name: name,
        code: Data([UInt8(truncatingIfNeeded: code >> 8), UInt8(truncatingIfNeeded: code)]),
        size: Double(subset.unitsPerEm)
      )
    }
    plannedGlyphs[PDFFontGroupKey(font: group.font)] = selections

    try writer.writeStream(chunks: [subset.data], to: programReference)
    try writer.writeStream(chunks: [cidToGID], compressed: false, to: mapReference)
    if let toUnicodeReference {
      try writer.writeStream(
        chunks: [makeToUnicode(entries: unicodeEntries, twoByteCodes: true)],
        compressed: false,
        to: toUnicodeReference
      )
    }
    let bounds = subset.metrics.bounds ?? FontBounds(
      minimumX: 0, minimumY: subset.metrics.descent,
      maximumX: Double(subset.unitsPerEm), maximumY: subset.metrics.ascent
    )
    var descriptor: [PDFName: PDFObject] = [
      "Type": .name("FontDescriptor"),
      "FontName": .name(PDFName(subset.postScriptName)),
      "Flags": .integer(4),
      "FontBBox": .array([
        .real(bounds.minimumX), .real(bounds.minimumY), .real(bounds.maximumX), .real(bounds.maximumY),
      ]),
      "ItalicAngle": .real(subset.metrics.italicAngle),
      "Ascent": .real(subset.metrics.ascent),
      "Descent": .real(subset.metrics.descent),
      "CapHeight": .real(subset.metrics.capHeight ?? subset.metrics.ascent),
      "StemV": .real(subset.metrics.stemV ?? 80),
      "FontFile2": .reference(programReference),
    ]
    if subset.metrics.ascent == 0 { descriptor["Ascent"] = .real(Double(subset.unitsPerEm) * 0.8) }
    if subset.metrics.descent == 0 { descriptor["Descent"] = .real(-Double(subset.unitsPerEm) * 0.2) }
    try writer.write(.dictionary(descriptor), to: descriptorReference)
    var descendant: [PDFName: PDFObject] = [
      "Type": .name("Font"),
      "Subtype": .name("CIDFontType2"),
      "BaseFont": .name(PDFName(subset.postScriptName)),
      "CIDSystemInfo": .dictionary([
        "Registry": .string(PDFString("Adobe")),
        "Ordering": .string(PDFString("Identity")),
        "Supplement": .integer(0),
      ]),
      "FontDescriptor": .reference(descriptorReference),
      "DW": .integer(1_000),
      "W": .array([.integer(1), .array(widths)]),
      "CIDToGIDMap": .reference(mapReference),
    ]
    if group.font.writingMode == 1 {
      descendant["DW2"] = .array([.integer(880), .integer(-1_000)])
    }
    try writer.write(.dictionary(descendant), to: descendantReference)
    var font: [PDFName: PDFObject] = [
      "Type": .name("Font"),
      "Subtype": .name("Type0"),
      "BaseFont": .name(PDFName(subset.postScriptName)),
      "Encoding": .name(group.font.writingMode == 1 ? "Identity-V" : "Identity-H"),
      "DescendantFonts": .array([.reference(descendantReference)]),
    ]
    if let toUnicodeReference { font["ToUnicode"] = .reference(toUnicodeReference) }
    try writer.write(.dictionary(font), to: fontReference)
    return true
  }

  private func prepareNameKeyedCFF(
    _ group: PDFFontUsageGroup,
    asset: FontAsset,
    subset: FontSubset,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> Bool {
    guard let data = asset.data,
      let collection = try? CompactFontCollection(data: data),
      collection.faces.indices.contains(asset.faceIndex)
    else { return false }
    let face = collection.faces[asset.faceIndex]
    guard
      !face.isCIDKeyed,
      group.glyphs.count <= 255
    else { return false }
    var codeByGlyph: [UInt32: UInt8] = [:]
    for (code, glyph) in face.encoding where codeByGlyph[glyph] == nil {
      codeByGlyph[glyph] = code
    }
    var codes: [(code: Int, key: PDFFontGlyphKey, use: PDFFontGlyphUse)] = []
    for key in group.glyphs {
      guard let index = key.resolvedIndex,
        let code = codeByGlyph[index],
        let use = group.uses[key]
      else { return false }
      codes.append((Int(code), key, use))
    }
    guard Set(codes.map(\.code)).count == codes.count else { return false }

    let name = PDFName("F\(fontObjects.count + 1)")
    let fontReference = try writer.reserveObject()
    let descriptorReference = try writer.reserveObject()
    let programReference = try writer.reserveObject()
    let unicodeEntries = codes.compactMap { entry in
      entry.use.unicode.map { (entry.code, $0) }
    }
    let toUnicodeReference = unicodeEntries.isEmpty ? nil : try writer.reserveObject()
    fontObjects[name] = fontReference

    let first = codes.map(\.code).min() ?? 0
    let last = codes.map(\.code).max() ?? 0
    var widthByCode: [Int: Double] = [:]
    var selections: [PDFFontGlyphKey: PDFFontSelection] = [:]
    for entry in codes {
      widthByCode[entry.code] = entry.use.glyph.metrics.horizontalAdvance.x
        * 1_000 / Double(subset.unitsPerEm)
      selections[entry.key] = PDFFontSelection(
        name: name, code: Data([UInt8(entry.code)]), size: Double(subset.unitsPerEm)
      )
    }
    plannedGlyphs[PDFFontGroupKey(font: group.font)] = selections

    try writer.writeStream(
      dictionary: ["Subtype": .name("Type1C")], chunks: [subset.data], to: programReference
    )
    try writeFontDescriptor(subset, programKey: "FontFile3", programReference, to: descriptorReference, writer: &writer)
    if let toUnicodeReference {
      try writer.writeStream(
        chunks: [makeToUnicode(entries: unicodeEntries, twoByteCodes: false)],
        compressed: false,
        to: toUnicodeReference
      )
    }
    var font: [PDFName: PDFObject] = [
      "Type": .name("Font"), "Subtype": .name("Type1"),
      "BaseFont": .name(PDFName(subset.postScriptName)),
      "FirstChar": .integer(first), "LastChar": .integer(last),
      "Widths": .array((first...last).map { .real(widthByCode[$0] ?? 0) }),
      "FontDescriptor": .reference(descriptorReference),
    ]
    if let toUnicodeReference { font["ToUnicode"] = .reference(toUnicodeReference) }
    try writer.write(.dictionary(font), to: fontReference)
    return true
  }

  private func prepareCIDKeyedCFF(
    _ group: PDFFontUsageGroup,
    subset: FontSubset,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> Bool {
    let glyphByOriginal = Dictionary(uniqueKeysWithValues: subset.glyphs.map { ($0.originalIndex, $0) })
    var entries: [(cid: Int, key: PDFFontGlyphKey, use: PDFFontGlyphUse)] = []
    for key in group.glyphs {
      guard let index = key.resolvedIndex,
        let cid = glyphByOriginal[index]?.cid,
        cid <= UInt16.max,
        let use = group.uses[key]
      else { return false }
      entries.append((Int(cid), key, use))
    }
    guard Set(entries.map(\.cid)).count == entries.count else { return false }

    let name = PDFName("F\(fontObjects.count + 1)")
    let fontReference = try writer.reserveObject()
    let descendantReference = try writer.reserveObject()
    let descriptorReference = try writer.reserveObject()
    let programReference = try writer.reserveObject()
    let unicodeEntries = entries.compactMap { entry in
      entry.use.unicode.map { (entry.cid, $0) }
    }
    let toUnicodeReference = unicodeEntries.isEmpty ? nil : try writer.reserveObject()
    fontObjects[name] = fontReference

    var selections: [PDFFontGlyphKey: PDFFontSelection] = [:]
    var widths: [PDFObject] = []
    for entry in entries {
      widths.append(.integer(entry.cid))
      widths.append(.array([.real(
        entry.use.glyph.metrics.horizontalAdvance.x * 1_000 / Double(subset.unitsPerEm)
      )]))
      selections[entry.key] = PDFFontSelection(
        name: name,
        code: Data([UInt8(truncatingIfNeeded: entry.cid >> 8), UInt8(truncatingIfNeeded: entry.cid)]),
        size: Double(subset.unitsPerEm)
      )
    }
    plannedGlyphs[PDFFontGroupKey(font: group.font)] = selections

    try writer.writeStream(
      dictionary: ["Subtype": .name("CIDFontType0C")], chunks: [subset.data], to: programReference
    )
    try writeFontDescriptor(subset, programKey: "FontFile3", programReference, to: descriptorReference, writer: &writer)
    if let toUnicodeReference {
      try writer.writeStream(
        chunks: [makeToUnicode(entries: unicodeEntries, twoByteCodes: true)],
        compressed: false,
        to: toUnicodeReference
      )
    }
    var descendant: [PDFName: PDFObject] = [
      "Type": .name("Font"), "Subtype": .name("CIDFontType0"),
      "BaseFont": .name(PDFName(subset.postScriptName)),
      "CIDSystemInfo": .dictionary([
        "Registry": .string(PDFString("Adobe")), "Ordering": .string(PDFString("Identity")),
        "Supplement": .integer(0),
      ]),
      "FontDescriptor": .reference(descriptorReference), "DW": .integer(1_000),
      "W": .array(widths),
    ]
    if group.font.writingMode == 1 { descendant["DW2"] = .array([.integer(880), .integer(-1_000)]) }
    try writer.write(.dictionary(descendant), to: descendantReference)
    var font: [PDFName: PDFObject] = [
      "Type": .name("Font"), "Subtype": .name("Type0"),
      "BaseFont": .name(PDFName(subset.postScriptName)),
      "Encoding": .name(group.font.writingMode == 1 ? "Identity-V" : "Identity-H"),
      "DescendantFonts": .array([.reference(descendantReference)]),
    ]
    if let toUnicodeReference { font["ToUnicode"] = .reference(toUnicodeReference) }
    try writer.write(.dictionary(font), to: fontReference)
    return true
  }

  private func prepareType1(
    _ group: PDFFontUsageGroup,
    subset: FontSubset,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> Bool {
    guard group.glyphs.count <= 255 else { return false }
    var glyphs: [(key: PDFFontGlyphKey, use: PDFFontGlyphUse, name: String)] = []
    for key in group.glyphs {
      guard let use = group.uses[key], case .name(let glyphName) = use.glyph.selector else { return false }
      glyphs.append((key, use, glyphName))
    }
    let name = PDFName("F\(fontObjects.count + 1)")
    let fontReference = try writer.reserveObject()
    let descriptorReference = try writer.reserveObject()
    let programReference = try writer.reserveObject()
    let unicodeEntries = glyphs.enumerated().compactMap { code, entry in
      entry.use.unicode.map { (code, $0) }
    }
    let toUnicodeReference = unicodeEntries.isEmpty ? nil : try writer.reserveObject()
    fontObjects[name] = fontReference

    var selections: [PDFFontGlyphKey: PDFFontSelection] = [:]
    for (code, entry) in glyphs.enumerated() {
      selections[entry.key] = PDFFontSelection(
        name: name, code: Data([UInt8(code)]), size: Double(subset.unitsPerEm)
      )
    }
    plannedGlyphs[PDFFontGroupKey(font: group.font)] = selections
    let lengths = subset.type1SegmentLengths ?? [subset.data.count, 0, 0]
    guard lengths.count == 3 else { return false }
    let program = try type1PDFProgram(subset.data)
    try writer.writeStream(
      dictionary: [
        "Length1": .integer(lengths[0]), "Length2": .integer(lengths[1]),
        "Length3": .integer(lengths[2]),
      ],
      chunks: [program], to: programReference
    )
    try writeFontDescriptor(subset, programKey: "FontFile", programReference, to: descriptorReference, writer: &writer)
    if let toUnicodeReference {
      try writer.writeStream(
        chunks: [makeToUnicode(entries: unicodeEntries, twoByteCodes: false)], compressed: false,
        to: toUnicodeReference
      )
    }
    var differences: [PDFObject] = [.integer(0)]
    differences.append(contentsOf: glyphs.map { .name(PDFName($0.name)) })
    var font: [PDFName: PDFObject] = [
      "Type": .name("Font"), "Subtype": .name("Type1"),
      "BaseFont": .name(PDFName(subset.postScriptName)),
      "Encoding": .dictionary(["Type": .name("Encoding"), "Differences": .array(differences)]),
      "FirstChar": .integer(0), "LastChar": .integer(max(0, glyphs.count - 1)),
      "Widths": .array(glyphs.map { .real(
        $0.use.glyph.metrics.horizontalAdvance.x * 1_000 / Double(subset.unitsPerEm)
      ) }),
      "FontDescriptor": .reference(descriptorReference),
    ]
    if let toUnicodeReference { font["ToUnicode"] = .reference(toUnicodeReference) }
    try writer.write(.dictionary(font), to: fontReference)
    return true
  }

  private func writeFontDescriptor(
    _ subset: FontSubset,
    programKey: PDFName,
    _ programReference: PDFObjectReference,
    to reference: PDFObjectReference,
    writer: inout PDFDocumentWriter<Sink>
  ) throws {
    let bounds =
      subset.metrics.bounds
      ?? FontBounds(
        minimumX: 0,
        minimumY: subset.metrics.descent,
        maximumX: Double(subset.unitsPerEm),
        maximumY: subset.metrics.ascent
      )
    try writer.write(
      .dictionary([
        "Type": .name("FontDescriptor"), "FontName": .name(PDFName(subset.postScriptName)),
        "Flags": .integer(4),
        "FontBBox": .array([
          .real(bounds.minimumX), .real(bounds.minimumY), .real(bounds.maximumX), .real(bounds.maximumY),
        ]),
        "ItalicAngle": .real(subset.metrics.italicAngle),
        "Ascent": .real(subset.metrics.ascent == 0 ? Double(subset.unitsPerEm) * 0.8 : subset.metrics.ascent),
        "Descent": .real(subset.metrics.descent == 0 ? -Double(subset.unitsPerEm) * 0.2 : subset.metrics.descent),
        "CapHeight": .real(subset.metrics.capHeight ?? subset.metrics.ascent),
        "StemV": .real(subset.metrics.stemV ?? 80), programKey: .reference(programReference),
      ]),
      to: reference
    )
  }

  private func type1PDFProgram(_ data: Data) throws -> Data {
    guard data.first == 0x80 else { return data }
    var offset = 0
    var result = Data()
    while offset < data.count {
      guard offset <= data.count - 2, data[offset] == 0x80 else { throw PDFError.invalidObject }
      let kind = data[offset + 1]
      offset += 2
      if kind == 3 { return result }
      guard (kind == 1 || kind == 2), offset <= data.count - 4 else { throw PDFError.invalidObject }
      let count = Int(data[offset]) | Int(data[offset + 1]) << 8
        | Int(data[offset + 2]) << 16 | Int(data[offset + 3]) << 24
      offset += 4
      guard count >= 0, offset <= data.count - count else { throw PDFError.invalidObject }
      result.append(data[offset..<offset + count])
      offset += count
    }
    throw PDFError.invalidObject
  }

  private func prepareType3Fonts(
    _ group: PDFFontUsageGroup,
    writer: inout PDFDocumentWriter<Sink>
  ) throws {
    for start in stride(from: 0, to: group.glyphs.count, by: 255) {
      let keys = Array(group.glyphs[start..<min(start + 255, group.glyphs.count)])
      let name = PDFName("F\(fontObjects.count + 1)")
      let fontReference = try writer.reserveObject()
      fontObjects[name] = fontReference
      var charProcs: [PDFName: PDFObject] = [:]
      var differences: [PDFObject] = [.integer(0)]
      var widths: [PDFObject] = []
      var bounds: [GraphicsRect] = []
      var unicodeEntries: [(Int, [UInt32])] = []
      var selections = plannedGlyphs[PDFFontGroupKey(font: group.font)] ?? [:]
      for (code, key) in keys.enumerated() {
        guard let use = group.uses[key] else { continue }
        let characterName = PDFName("g\(code)")
        let characterReference = try writer.reserveObject()
        let glyphBounds = use.glyph.metrics.bounds ?? pathBounds(use.glyph.program)
        bounds.append(glyphBounds)
        var character = PDFContentBuilder()
        character.command(
          "\(character.number(use.glyph.metrics.horizontalAdvance.x)) "
            + "\(character.number(use.glyph.metrics.horizontalAdvance.y)) "
            + "\(character.number(glyphBounds.x)) \(character.number(glyphBounds.y)) "
            + "\(character.number(glyphBounds.maxX)) \(character.number(glyphBounds.maxY)) d1"
        )
        if case .outline(let path) = use.glyph.program {
          character.path(path)
          character.command("f")
        }
        try writer.writeStream(chunks: [character.data], to: characterReference)
        charProcs[characterName] = .reference(characterReference)
        differences.append(.name(characterName))
        widths.append(.real(use.glyph.metrics.horizontalAdvance.x))
        if let unicode = use.unicode { unicodeEntries.append((code, unicode)) }
        selections[key] = PDFFontSelection(name: name, code: Data([UInt8(code)]), size: 1)
      }
      plannedGlyphs[PDFFontGroupKey(font: group.font)] = selections
      let combined = bounds.reduce(GraphicsRect(x: 0, y: 0, width: 0, height: 0)) { value, next in
        guard value.width != 0 || value.height != 0 else { return next }
        let minimumX = min(value.x, next.x)
        let minimumY = min(value.y, next.y)
        return GraphicsRect(
          x: minimumX, y: minimumY,
          width: max(value.maxX, next.maxX) - minimumX,
          height: max(value.maxY, next.maxY) - minimumY
        )
      }
      let toUnicodeReference = unicodeEntries.isEmpty ? nil : try writer.reserveObject()
      if let toUnicodeReference {
        try writer.writeStream(
          chunks: [makeToUnicode(entries: unicodeEntries, twoByteCodes: false)],
          compressed: false,
          to: toUnicodeReference
        )
      }
      var dictionary: [PDFName: PDFObject] = [
        "Type": .name("Font"), "Subtype": .name("Type3"),
        "Name": .name(PDFName(group.font.postScriptName ?? "SolidGlyphs")),
        "FontBBox": .array([.real(combined.x), .real(combined.y), .real(combined.maxX), .real(combined.maxY)]),
        "FontMatrix": .array([.integer(1), .integer(0), .integer(0), .integer(1), .integer(0), .integer(0)]),
        "CharProcs": .dictionary(charProcs),
        "Encoding": .dictionary(["Type": .name("Encoding"), "Differences": .array(differences)]),
        "FirstChar": .integer(0), "LastChar": .integer(max(0, keys.count - 1)),
        "Widths": .array(widths), "Resources": .reference(resourcesReference),
      ]
      if let toUnicodeReference { dictionary["ToUnicode"] = .reference(toUnicodeReference) }
      try writer.write(.dictionary(dictionary), to: fontReference)
    }
  }

  private func makeToUnicode(entries: [(Int, [UInt32])], twoByteCodes: Bool) -> Data {
    var lines = [
      "/CIDInit /ProcSet findresource begin", "12 dict begin", "begincmap",
      "/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def",
      "/CMapName /SolidToUnicode def", "/CMapType 2 def", "1 begincodespacerange",
      twoByteCodes ? "<0000> <FFFF>" : "<00> <FF>", "endcodespacerange",
    ]
    for start in stride(from: 0, to: entries.count, by: 100) {
      let chunk = entries[start..<min(start + 100, entries.count)]
      lines.append("\(chunk.count) beginbfchar")
      for entry in chunk {
        let source = String(format: twoByteCodes ? "%04X" : "%02X", entry.0)
        let destination = entry.1.flatMap(utf16).map { String(format: "%04X", $0) }.joined()
        lines.append("<\(source)> <\(destination)>")
      }
      lines.append("endbfchar")
    }
    lines.append(contentsOf: ["endcmap", "CMapName currentdict /CMap defineresource pop", "end", "end"])
    return Data((lines.joined(separator: "\n") + "\n").utf8)
  }

  private func utf16(_ scalar: UInt32) -> [UInt16] {
    if scalar <= 0xFFFF { return [UInt16(scalar)] }
    let value = scalar - 0x1_0000
    return [UInt16(0xD800 + (value >> 10)), UInt16(0xDC00 + (value & 0x3FF))]
  }

  func finish(writer: inout PDFDocumentWriter<Sink>) throws {
    var resources: [PDFName: PDFObject] = [:]
    if !xObjects.isEmpty {
      resources["XObject"] = .dictionary(xObjects.mapValues(PDFObject.reference))
    }
    if !shadingObjects.isEmpty {
      resources["Shading"] = .dictionary(shadingObjects.mapValues(PDFObject.reference))
    }
    if !patternObjects.isEmpty {
      resources["Pattern"] = .dictionary(patternObjects.mapValues(PDFObject.reference))
    }
    if !colorSpaceObjects.isEmpty {
      resources["ColorSpace"] = .dictionary(colorSpaceObjects.mapValues(PDFObject.reference))
    }
    if !graphicsStates.isEmpty {
      resources["ExtGState"] = .dictionary(graphicsStates.mapValues(PDFObject.reference))
    }
    if !fontObjects.isEmpty {
      resources["Font"] = .dictionary(fontObjects.mapValues(PDFObject.reference))
    }
    try writer.write(.dictionary(resources), to: resourcesReference)
  }

  func ensureImage(
    _ image: GraphicsImage,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> PDFName {
    if let existing = images[image] { return existing.name }
    let name = PDFName("Im\(images.count + rasterImages.count + 1)")
    let reference = try writer.reserveObject()
    images[image] = NamedReference(name: name, reference: reference)
    xObjects[name] = reference
    let mask = try makeMask(for: image, writer: &writer)
    let bits = image.descriptor.sourceBitsPerComponent > 8 ? 16 : 8
    let components = image.descriptor.kind.componentCount
    var bytes = Data()
    bytes.reserveCapacity(image.descriptor.width * image.descriptor.height * components * (bits / 8))
    let expected = image.descriptor.width * image.descriptor.height * components
    for index in 0..<expected {
      let value = index < image.components.count ? min(1, max(0, image.components[index])) : 0
      if bits == 16 {
        let sample = UInt16((value * Float(UInt16.max)).rounded())
        bytes.append(UInt8(truncatingIfNeeded: sample >> 8))
        bytes.append(UInt8(truncatingIfNeeded: sample))
      } else {
        bytes.append(UInt8((value * 255).rounded()))
      }
    }
    var dictionary: [PDFName: PDFObject] = [
      "Type": .name("XObject"),
      "Subtype": .name("Image"),
      "Width": .integer(image.descriptor.width),
      "Height": .integer(image.descriptor.height),
      "BitsPerComponent": .integer(bits),
    ]
    switch image.descriptor.kind {
    case .color(.deviceGray): dictionary["ColorSpace"] = .name("DeviceGray")
    case .color(.deviceRGB): dictionary["ColorSpace"] = .name("DeviceRGB")
    case .color(.deviceCMYK): dictionary["ColorSpace"] = .name("DeviceCMYK")
    case .mask:
      dictionary["ImageMask"] = .boolean(true)
      dictionary["Decode"] = .array([.integer(0), .integer(1)])
    }
    if let mask { dictionary["SMask"] = .reference(mask) }
    try writer.writeStream(dictionary: dictionary, chunks: [bytes], to: reference)
    return name
  }

  func ensureRasterImage(
    _ image: RasterImage,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> PDFName {
    if let existing = rasterImages[image] { return existing.name }
    let name = PDFName("Im\(images.count + rasterImages.count + 1)")
    let reference = try writer.reserveObject()
    let maskReference = try writer.reserveObject()
    rasterImages[image] = NamedReference(name: name, reference: reference)
    xObjects[name] = reference
    var rgb = Data()
    var alpha = Data()
    rgb.reserveCapacity(image.width * image.height * 3)
    alpha.reserveCapacity(image.width * image.height)
    for row in 0..<image.height {
      for column in 0..<image.width {
        let offset = row * image.bytesPerRow + column * 4
        let opacity = image.data[offset + 3]
        let components = [image.data[offset], image.data[offset + 1], image.data[offset + 2]]
        for component in components {
          if image.pixelFormat == .rgba8UnormPremultiplied, opacity != 0 {
            rgb.append(UInt8(clamping: (Int(component) * 255 + Int(opacity) / 2) / Int(opacity)))
          } else {
            rgb.append(component)
          }
        }
        alpha.append(opacity)
      }
    }
    try writer.writeStream(
      dictionary: [
        "Type": .name("XObject"), "Subtype": .name("Image"),
        "Width": .integer(image.width), "Height": .integer(image.height),
        "ColorSpace": .name("DeviceGray"), "BitsPerComponent": .integer(8),
      ],
      chunks: [alpha],
      to: maskReference
    )
    try writer.writeStream(
      dictionary: [
        "Type": .name("XObject"), "Subtype": .name("Image"),
        "Width": .integer(image.width), "Height": .integer(image.height),
        "ColorSpace": .name("DeviceRGB"), "BitsPerComponent": .integer(8),
        "SMask": .reference(maskReference),
      ],
      chunks: [rgb],
      to: reference
    )
    return name
  }

  func ensureForm(
    _ form: GraphicsForm,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> PDFName {
    if let existing = forms[form] { return existing.name }
    let name = PDFName("Fm\(forms.count + 1)")
    let reference = try writer.reserveObject()
    forms[form] = NamedReference(name: name, reference: reference)
    xObjects[name] = reference
    let content = try PDFGraphicsContentEncoder.encode(
      form.displayList.effects,
      resources: self,
      writer: &writer
    )
    let bounds = form.bounds
    try writer.writeStream(
      dictionary: [
        "Type": .name("XObject"),
        "Subtype": .name("Form"),
        "FormType": .integer(1),
        "BBox": .array([
          .real(bounds.x), .real(bounds.y), .real(bounds.maxX), .real(bounds.maxY),
        ]),
        "Resources": .reference(resourcesReference),
      ],
      chunks: [content],
      to: reference
    )
    return name
  }

  func ensureTransparencyGroup(
    _ group: GraphicsTransparencyGroup,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> PDFName {
    if let existing = transparencyGroups[group] { return existing.name }
    let name = PDFName("Tr\(transparencyGroups.count + 1)")
    let reference = try writer.reserveObject()
    transparencyGroups[group] = NamedReference(name: name, reference: reference)
    xObjects[name] = reference
    let content = try PDFGraphicsContentEncoder.encode(
      group.displayList.effects,
      resources: self,
      writer: &writer
    )
    let bounds = group.bounds
    var groupDictionary: [PDFName: PDFObject] = [
      "S": .name("Transparency"),
      "I": .boolean(group.isolated),
      "K": .boolean(group.knockout),
    ]
    if let colorSpace = group.colorSpace {
      groupDictionary["CS"] = try pdfColorSpace(colorSpace, writer: &writer)
    }
    try writer.writeStream(
      dictionary: [
        "Type": .name("XObject"),
        "Subtype": .name("Form"),
        "FormType": .integer(1),
        "BBox": .array([
          .real(bounds.x), .real(bounds.y), .real(bounds.maxX), .real(bounds.maxY),
        ]),
        "Group": .dictionary(groupDictionary),
        "Resources": .reference(resourcesReference),
      ],
      chunks: [content],
      to: reference
    )
    return name
  }

  func ensureTransparency(
    _ transparency: GraphicsTransparencyState,
    strokingAlpha: Double? = nil,
    nonstrokingAlpha: Double? = nil,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> PDFName {
    let key = TransparencyKey(
      state: transparency,
      strokingAlpha: strokingAlpha ?? transparency.constantAlpha,
      nonstrokingAlpha: nonstrokingAlpha ?? transparency.constantAlpha
    )
    if let existing = transparencyStates[key] { return existing.name }
    let name = PDFName("GStr\(transparencyStates.count + 1)")
    let reference = try writer.reserveObject()
    transparencyStates[key] = NamedReference(name: name, reference: reference)
    graphicsStates[name] = reference
    var dictionary: [PDFName: PDFObject] = [
      "Type": .name("ExtGState"),
      "BM": .name(PDFName(transparency.blendMode.pdfName)),
      "ca": .real(key.nonstrokingAlpha),
      "CA": .real(key.strokingAlpha),
      "AIS": .boolean(transparency.alphaIsShape),
      "TK": .boolean(transparency.textKnockout),
    ]
    if let mask = transparency.softMask {
      let groupName = try ensureTransparencyGroup(mask.group, writer: &writer)
      guard let groupReference = xObjects[groupName] else { throw PDFError.invalidReference }
      var maskDictionary: [PDFName: PDFObject] = [
        "S": .name(mask.subtype == .alpha ? "Alpha" : "Luminosity"),
        "G": .reference(groupReference),
      ]
      if !mask.backdrop.isEmpty { maskDictionary["BC"] = .array(mask.backdrop.map(PDFObject.real)) }
      if let transfer = mask.transferFunction {
        maskDictionary["TR"] = .reference(try sampledFunction(transfer, writer: &writer))
      }
      dictionary["SMask"] = .dictionary(maskDictionary)
    } else {
      dictionary["SMask"] = .name("None")
    }
    try writer.write(.dictionary(dictionary), to: reference)
    return name
  }

  private func sampledFunction(
    _ function: GraphicsComponentFunction,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> PDFObjectReference {
    let reference = try writer.reserveObject()
    let data = Data(function.samples.map { UInt8((min(1, max(0, $0)) * 255).rounded()) })
    try writer.writeStream(
      dictionary: [
        "FunctionType": .integer(0),
        "Domain": .array([.integer(0), .integer(1)]),
        "Range": .array([.integer(0), .integer(1)]),
        "Size": .array([.integer(function.samples.count)]),
        "BitsPerSample": .integer(8),
      ],
      chunks: [data],
      to: reference
    )
    return reference
  }

  private func pdfColorSpace(
    _ space: GraphicsColorSpaceDescription,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> PDFObject {
    switch space {
    case .deviceGray: .name("DeviceGray")
    case .deviceRGB: .name("DeviceRGB")
    case .deviceCMYK: .name("DeviceCMYK")
    default: .name(try ensureColorSpace(space, writer: &writer))
    }
  }

  func ensureShading(
    _ shading: GraphicsShading,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> PDFName {
    if let existing = shadings[shading] { return existing.name }
    let name = PDFName("Sh\(shadings.count + 1)")
    let reference = try writer.reserveObject()
    shadings[shading] = NamedReference(name: name, reference: reference)
    shadingObjects[name] = reference
    let triangles = shading.mesh.triangles
    let points = triangles.flatMap { [$0.first.position, $0.second.position, $0.third.position] }
    let minimumX = points.map(\.x).min() ?? 0
    let maximumX = points.map(\.x).max() ?? minimumX + 1
    let minimumY = points.map(\.y).min() ?? 0
    let maximumY = points.map(\.y).max() ?? minimumY + 1
    let width = max(Double.leastNonzeroMagnitude, maximumX - minimumX)
    let height = max(Double.leastNonzeroMagnitude, maximumY - minimumY)
    var data = Data()
    for triangle in triangles {
      for vertex in [triangle.first, triangle.second, triangle.third] {
        data.append(0)
        data.appendBigEndian(UInt32(((vertex.position.x - minimumX) / width * Double(UInt32.max)).rounded()))
        data.appendBigEndian(UInt32(((vertex.position.y - minimumY) / height * Double(UInt32.max)).rounded()))
        let rgb = vertex.paint.rgbComponents
        data.append(UInt8((min(1, max(0, rgb.red)) * 255).rounded()))
        data.append(UInt8((min(1, max(0, rgb.green)) * 255).rounded()))
        data.append(UInt8((min(1, max(0, rgb.blue)) * 255).rounded()))
      }
    }
    try writer.writeStream(
      dictionary: [
        "ShadingType": .integer(4),
        "ColorSpace": .name("DeviceRGB"),
        "BitsPerCoordinate": .integer(32),
        "BitsPerComponent": .integer(8),
        "BitsPerFlag": .integer(8),
        "Decode": .array([
          .real(minimumX), .real(maximumX), .real(minimumY), .real(maximumY),
          .integer(0), .integer(1), .integer(0), .integer(1), .integer(0), .integer(1),
        ]),
      ],
      chunks: [data],
      to: reference
    )
    return name
  }

  func ensurePattern(
    _ paint: GraphicsPatternPaint,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> PDFName {
    if let existing = patterns[paint] { return existing.name }
    let name = PDFName("P\(patterns.count + 1)")
    let reference = try writer.reserveObject()
    patterns[paint] = NamedReference(name: name, reference: reference)
    patternObjects[name] = reference
    switch paint {
    case .empty:
      try writer.write(.dictionary(["PatternType": .integer(1)]), to: reference)
    case .shading(let shading):
      let shadingName = try ensureShading(shading, writer: &writer)
      guard let shadingReference = shadingObjects[shadingName] else { throw PDFError.invalidReference }
      try writer.write(
        .dictionary([
          "Type": .name("Pattern"),
          "PatternType": .integer(2),
          "Shading": .reference(shadingReference),
        ]),
        to: reference
      )
    case .tiling(let pattern, let underlying):
      guard let inverse = pattern.matrix.inverted else { throw PDFError.invalidObject }
      var content = PDFContentBuilder()
      content.command("q")
      content.command("\(content.matrix(inverse)) cm")
      content.append(try PDFGraphicsContentEncoder.encode(
        pattern.displayList.effects,
        resources: self,
        writer: &writer,
        paintOverride: underlying
      ))
      content.command("Q")
      try writer.writeStream(
        dictionary: [
          "Type": .name("Pattern"),
          "PatternType": .integer(1),
          "PaintType": .integer(1),
          "TilingType": .integer(pattern.tilingType),
          "BBox": .array([
            .real(pattern.bounds.x), .real(pattern.bounds.y),
            .real(pattern.bounds.maxX), .real(pattern.bounds.maxY),
          ]),
          "XStep": .real(pattern.xStep),
          "YStep": .real(pattern.yStep),
          "Matrix": .array([
            .real(pattern.matrix.a), .real(pattern.matrix.b),
            .real(pattern.matrix.c), .real(pattern.matrix.d),
            .real(pattern.matrix.tx), .real(pattern.matrix.ty),
          ]),
          "Resources": .reference(resourcesReference),
        ],
        chunks: [content.data],
        to: reference
      )
    }
    return name
  }

  func ensureColorSpace(
    _ space: GraphicsColorSpaceDescription,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> PDFName {
    if let existing = colorSpaces[space] { return existing.name }
    let name = PDFName("Cs\(colorSpaces.count + 1)")
    let reference = try writer.reserveObject()
    colorSpaces[space] = NamedReference(name: name, reference: reference)
    colorSpaceObjects[name] = reference
    switch space {
    case .separation(let colorant, _):
      let function = try makeTintFunction(componentCount: 1, writer: &writer)
      try writer.write(
        .array([
          .name("Separation"), .name(PDFName(colorant)), .name("DeviceCMYK"), .reference(function),
        ]),
        to: reference
      )
    case .deviceN(let colorants, _):
      let function = try makeTintFunction(componentCount: colorants.count, writer: &writer)
      try writer.write(
        .array([
          .name("DeviceN"), .array(colorants.map { .name(PDFName($0)) }),
          .name("DeviceCMYK"), .reference(function),
        ]),
        to: reference
      )
    default:
      throw PDFError.invalidObject
    }
    return name
  }

  func ensureOverprint(
    _ enabled: Bool,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> PDFName {
    if let existing = overprintStates[enabled] { return existing.name }
    let name = PDFName(enabled ? "GSop" : "GSko")
    let reference = try writer.reserveObject()
    overprintStates[enabled] = NamedReference(name: name, reference: reference)
    graphicsStates[name] = reference
    try writer.write(
      .dictionary([
        "Type": .name("ExtGState"),
        "OP": .boolean(enabled),
        "op": .boolean(enabled),
        "OPM": .integer(1),
      ]),
      to: reference
    )
    return name
  }

  private func makeMask(
    for image: GraphicsImage,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> PDFObjectReference? {
    let width: Int
    let height: Int
    var opacities: [Float]
    if let mask = image.mask {
      switch mask.descriptor {
      case .explicit(let maskWidth, let maskHeight, _, _):
        width = maskWidth; height = maskHeight
      case .colorKey:
        width = image.descriptor.width; height = image.descriptor.height
      }
      opacities = mask.opacities
    } else if image.completedRowCount < image.descriptor.height {
      width = image.descriptor.width; height = image.descriptor.height
      opacities = [Float](
        repeating: 1,
        count: image.completedRowCount * image.descriptor.width
      )
    } else {
      return nil
    }
    let total = width * height
    if opacities.count < total { opacities.append(contentsOf: repeatElement(0, count: total - opacities.count)) }
    let data = Data(opacities.prefix(total).map { UInt8((min(1, max(0, $0)) * 255).rounded()) })
    let reference = try writer.reserveObject()
    try writer.writeStream(
      dictionary: [
        "Type": .name("XObject"), "Subtype": .name("Image"),
        "Width": .integer(width), "Height": .integer(height),
        "ColorSpace": .name("DeviceGray"), "BitsPerComponent": .integer(8),
      ],
      chunks: [data],
      to: reference
    )
    return reference
  }

  private func makeTintFunction(
    componentCount: Int,
    writer: inout PDFDocumentWriter<Sink>
  ) throws -> PDFObjectReference {
    guard (1...8).contains(componentCount) else { throw PDFError.limitExceeded }
    let reference = try writer.reserveObject()
    let sampleCount = 1 << componentCount
    var samples = Data()
    for sample in 0..<sampleCount {
      var maximum = 0
      for bit in 0..<componentCount where sample & (1 << bit) != 0 { maximum = 255 }
      samples.append(contentsOf: [0, 0, 0, UInt8(maximum)])
    }
    try writer.writeStream(
      dictionary: [
        "FunctionType": .integer(0),
        "Domain": .array((0..<componentCount).flatMap { _ in [.integer(0), .integer(1)] }),
        "Range": .array((0..<4).flatMap { _ in [.integer(0), .integer(1)] }),
        "Size": .array((0..<componentCount).map { _ in .integer(2) }),
        "BitsPerSample": .integer(8),
      ],
      chunks: [samples],
      to: reference
    )
    return reference
  }

  private func pathBounds(_ program: GraphicsGlyphProgram) -> GraphicsRect {
    guard case .outline(let path) = program else { return .init(x: 0, y: 0, width: 0, height: 0) }
    let points = path.elements.flatMap { element -> [GraphicsPoint] in
      switch element {
      case .move(let point), .line(let point): [point]
      case .curve(let first, let second, let end): [first, second, end]
      case .close: []
      }
    }
    guard let minimumX = points.map(\.x).min(), let maximumX = points.map(\.x).max(),
      let minimumY = points.map(\.y).min(), let maximumY = points.map(\.y).max()
    else { return .init(x: 0, y: 0, width: 0, height: 0) }
    return GraphicsRect(x: minimumX, y: minimumY, width: maximumX - minimumX, height: maximumY - minimumY)
  }
}

private extension Data {
  mutating func appendBigEndian(_ value: UInt32) {
    append(contentsOf: [
      UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16),
      UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value),
    ])
  }
}
