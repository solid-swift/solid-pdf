import Foundation
import SolidFont
import SolidPDF
import SolidPostScript

final class PDFResolvedFont {
  enum Mapping {
    case simple(PDFSimpleEncoding)
    case composite(PDFCMap, Descendant)
    case type3(PDFSimpleEncoding, [PDFName: PDFObject], [PDFName: PDFObject]?)
  }

  struct Descendant {
    let systemInfo: FontCIDSystemInfo
    let cidToGlyph: CIDToGlyph
    let defaultWidth: Double
    let widths: [UInt32: Double]
    let defaultVertical: VerticalMetric
    let verticalMetrics: [UInt32: VerticalMetric]
  }

  struct VerticalMetric: Sendable, Hashable {
    let advance: Double
    let originX: Double
    let originY: Double

    static let standard = Self(advance: -1_000, originX: 500, originY: 880)
  }

  enum CIDToGlyph: Sendable, Hashable {
    case identity
    case table(Data)

    func glyphIndex(for cid: UInt32) -> UInt32? {
      switch self {
      case .identity: return cid
      case .table(let data):
        guard cid <= UInt32(Int.max / 2) else { return nil }
        let offset = Int(cid) * 2
        guard offset <= data.count - 2 else { return nil }
        return UInt32(data[offset]) << 8 | UInt32(data[offset + 1])
      }
    }
  }

  enum GlyphSource {
    case type1(Type1FontProgram)
    case compact(CompactFontCollection, faceIndex: Int)
    case sfnt(SFNTCollection, data: Data, faceIndex: Int)
    case provider(any FontResourceProvider, FontProviderFace)
    case type3
    case unavailable
  }

  let resourceName: String
  let reference: PDFObjectReference?
  let description: GraphicsFontDescription
  let mapping: Mapping
  let source: GlyphSource
  let toUnicode: PDFCMap?
  let collectionUnicode: PDFCMap?
  let defaultWidth: Double
  let widths: [UInt32: Double]
  let firstCharacter: Int
  let fontMatrix: GraphicsMatrix
  let fontBounds: GraphicsRect?

  init(
    resourceName: String,
    reference: PDFObjectReference?,
    description: GraphicsFontDescription,
    mapping: Mapping,
    source: GlyphSource,
    toUnicode: PDFCMap?,
    collectionUnicode: PDFCMap? = nil,
    defaultWidth: Double,
    widths: [UInt32: Double],
    firstCharacter: Int,
    fontMatrix: GraphicsMatrix,
    fontBounds: GraphicsRect? = nil
  ) {
    self.resourceName = resourceName
    self.reference = reference
    self.description = description
    self.mapping = mapping
    self.source = source
    self.toUnicode = toUnicode
    self.collectionUnicode = collectionUnicode
    self.defaultWidth = defaultWidth
    self.widths = widths
    self.firstCharacter = firstCharacter
    self.fontMatrix = fontMatrix
    self.fontBounds = fontBounds
  }

  func horizontalWidth(code: UInt32, cid: UInt32?) -> Double {
    if case .composite(_, let descendant) = mapping {
      return descendant.widths[cid ?? code] ?? descendant.defaultWidth
    }
    return widths[code] ?? defaultWidth
  }

  func verticalMetric(cid: UInt32) -> VerticalMetric? {
    guard case .composite(let cmap, let descendant) = mapping, cmap.writingMode == 1 else { return nil }
    return descendant.verticalMetrics[cid] ?? descendant.defaultVertical
  }
}

extension PDFGraphicsResourceResolver {
  func font(named name: PDFName, location: PDFContentLocation) async throws -> PDFResolvedFont {
    guard let object = try await resourceObject(category: "Font", name: name) else {
      throw PDFGraphicsError.fontProgramUnavailable(name: name.pdfGraphicsString, location: location)
    }
    let key = FontCacheKey(revision: revision, object: object)
    if let cached = fontCache[key] { return cached }
    guard fontCache.count < limits.maximumFonts else {
      throw PDFGraphicsError.limitExceeded("PDF font-resource limit exceeded.", location: location)
    }
    do {
      let resolved = try await resolveFont(
        resourceName: name.pdfGraphicsString,
        object: object,
        location: location
      )
      fontCache[key] = resolved
      return resolved
    } catch let error as PDFGraphicsError {
      throw error
    } catch let error as PDFCMapError {
      throw PDFGraphicsError.malformedCMap(message: String(describing: error), location: location)
    } catch {
      throw PDFGraphicsError.malformedContent(
        message: "Malformed PDF font resource.", operatorName: "Tf", location: location
      )
    }
  }

  private func resolveFont(
    resourceName: String,
    object: PDFObject,
    location: PDFContentLocation
  ) async throws -> PDFResolvedFont {
    let reference: PDFObjectReference?
    let dictionary: [PDFName: PDFObject]
    if case .reference(let value) = object {
      reference = value
      let resolved = try await document.resolve(value, in: revision)
      guard case .value(.dictionary(let value)) = resolved.value else { throw PDFObjectAccess.TypeMismatch.dictionary }
      dictionary = value
    } else {
      reference = nil
      dictionary = try PDFObjectAccess.dictionary(object)
    }
    let subtype = try PDFObjectAccess.name(dictionary["Subtype"] ?? .null).pdfGraphicsString
    let baseName = try dictionary["BaseFont"].map(PDFObjectAccess.name)?.pdfGraphicsString ?? resourceName
    let toUnicode = try await resolveToUnicode(dictionary["ToUnicode"], location: location)
    if subtype == "Type0" {
      return try await resolveComposite(
        resourceName: resourceName,
        reference: reference,
        baseName: baseName,
        dictionary: dictionary,
        toUnicode: toUnicode,
        location: location
      )
    }
    guard ["Type1", "MMType1", "TrueType", "Type3"].contains(subtype) else {
      throw PDFGraphicsError.unsupportedFont(subtype: subtype, location: location)
    }
    let encoding = try await simpleEncoding(
      dictionary["Encoding"],
      defaultName: symbolicEncodingName(baseName: baseName),
      location: location
    )
    let first = try dictionary["FirstChar"].map(PDFObjectAccess.integer) ?? 0
    let widths = try simpleWidths(dictionary, first: first)
    let descriptorDictionary = try await dictionaryValue(dictionary["FontDescriptor"])
    let missingWidth = try descriptorDictionary?["MissingWidth"].map(PDFObjectAccess.number) ?? 0
    let matrix = subtype == "Type3"
      ? try graphicsMatrix(dictionary["FontMatrix"] ?? .null)
      : GraphicsMatrix(a: 0.001, b: 0, c: 0, d: 0.001, tx: 0, ty: 0)
    let fontBounds = try dictionary["FontBBox"].map(PDFObjectAccess.numbers).map(Self.graphicsRect)
    let technology: GraphicsFontTechnology = switch subtype {
    case "TrueType": .trueType
    case "Type3": .type3
    default: .type1
    }
    let asset = try await embeddedAsset(
      descriptorDictionary,
      postScriptName: baseName,
      expectedTechnology: technology,
      location: location
    )
    let selected = try await selectGlyphSource(
      asset: asset,
      name: baseName,
      cidSystemInfo: nil,
      technology: technology,
      location: location
    )
    let substitution = selected.substitution
    let description = GraphicsFontDescription(
      identifier: .init(fontIdentifier(reference: reference, resourceName: resourceName)),
      resourceName: resourceName,
      postScriptName: baseName,
      matrix: matrix,
      writingMode: 0,
      asset: selected.asset,
      outlineAccess: selected.asset?.descriptor.outlineAccess ?? .extractable,
      technology: technology,
      fontType: subtype == "Type3" ? 3 : subtype == "TrueType" ? 42 : 1,
      resourceIdentifier: resourceIdentifier(reference: reference, resourceName: resourceName),
      substitution: substitution
    )
    let mapping: PDFResolvedFont.Mapping
    if subtype == "Type3" {
      let procedures = try PDFObjectAccess.dictionary(dictionary["CharProcs"] ?? .null)
      let resources = try await dictionaryValue(dictionary["Resources"])
      mapping = .type3(encoding, procedures, resources)
    } else {
      mapping = .simple(encoding)
    }
    return PDFResolvedFont(
      resourceName: resourceName,
      reference: reference,
      description: description,
      mapping: mapping,
      source: subtype == "Type3" ? .type3 : selected.source,
      toUnicode: toUnicode,
      defaultWidth: missingWidth,
      widths: widths,
      firstCharacter: first,
      fontMatrix: matrix,
      fontBounds: fontBounds
    )
  }

  private func resolveComposite(
    resourceName: String,
    reference: PDFObjectReference?,
    baseName: String,
    dictionary: [PDFName: PDFObject],
    toUnicode: PDFCMap?,
    location: PDFContentLocation
  ) async throws -> PDFResolvedFont {
    let descendants = try PDFObjectAccess.array(dictionary["DescendantFonts"] ?? .null)
    guard descendants.count == 1 else { throw PDFObjectAccess.TypeMismatch.array }
    let descendantObject = descendants[0]
    let descendant = try await dictionaryValue(descendantObject)
    guard let descendant else { throw PDFObjectAccess.TypeMismatch.dictionary }
    let subtype = try PDFObjectAccess.name(descendant["Subtype"] ?? .null).pdfGraphicsString
    guard subtype == "CIDFontType0" || subtype == "CIDFontType2" else {
      throw PDFGraphicsError.unsupportedFont(subtype: subtype, location: location)
    }
    let systemInfo = try cidSystemInfo(descendant["CIDSystemInfo"] ?? .null)
    let cmap = try await resolveEncodingCMap(dictionary["Encoding"] ?? .null, location: location)
    let defaultWidth = try descendant["DW"].map(PDFObjectAccess.number) ?? 1_000
    let widths = try cidWidths(descendant["W"])
    let defaultVertical = try defaultVerticalMetric(descendant["DW2"])
    let vertical = try cidVerticalMetrics(descendant["W2"])
    let cidToGlyph = try await cidToGlyphMap(descendant["CIDToGIDMap"])
    let descriptorDictionary = try await dictionaryValue(descendant["FontDescriptor"])
    let technology: GraphicsFontTechnology = subtype == "CIDFontType2" ? .cidType2 : .cidType0
    let asset = try await embeddedAsset(
      descriptorDictionary,
      postScriptName: baseName,
      expectedTechnology: technology,
      location: location
    )
    let selected = try await selectGlyphSource(
      asset: asset,
      name: baseName,
      cidSystemInfo: systemInfo,
      technology: technology,
      location: location
    )
    let description = GraphicsFontDescription(
      identifier: .init(fontIdentifier(reference: reference, resourceName: resourceName)),
      resourceName: resourceName,
      postScriptName: baseName,
      matrix: GraphicsMatrix(a: 0.001, b: 0, c: 0, d: 0.001, tx: 0, ty: 0),
      writingMode: cmap.writingMode,
      asset: selected.asset,
      outlineAccess: selected.asset?.descriptor.outlineAccess ?? .extractable,
      technology: .composite,
      fontType: 0,
      resourceIdentifier: resourceIdentifier(reference: reference, resourceName: resourceName),
      substitution: selected.substitution
    )
    return PDFResolvedFont(
      resourceName: resourceName,
      reference: reference,
      description: description,
      mapping: .composite(
        cmap,
        .init(
          systemInfo: systemInfo,
          cidToGlyph: cidToGlyph,
          defaultWidth: defaultWidth,
          widths: widths,
          defaultVertical: defaultVertical,
          verticalMetrics: vertical
        )
      ),
      source: selected.source,
      toUnicode: toUnicode,
      collectionUnicode: try PDFPredefinedCMaps.unicodeMap(for: systemInfo, limits: limits),
      defaultWidth: defaultWidth,
      widths: widths,
      firstCharacter: 0,
      fontMatrix: GraphicsMatrix(a: 0.001, b: 0, c: 0, d: 0.001, tx: 0, ty: 0)
    )
  }

  private static func graphicsRect(_ values: [Double]) throws -> GraphicsRect {
    guard values.count == 4, values.allSatisfy(\.isFinite) else { throw PDFObjectAccess.TypeMismatch.array }
    return GraphicsRect(
      x: min(values[0], values[2]),
      y: min(values[1], values[3]),
      width: abs(values[2] - values[0]),
      height: abs(values[3] - values[1])
    )
  }

  private func selectGlyphSource(
    asset: FontAsset?,
    name: String,
    cidSystemInfo: FontCIDSystemInfo?,
    technology: GraphicsFontTechnology,
    location: PDFContentLocation
  ) async throws -> (source: PDFResolvedFont.GlyphSource, asset: FontAsset?, substitution: GraphicsFontSubstitution?) {
    if let asset {
      if asset.format == .type1, let data = asset.data {
        do {
          return (.type1(try Type1FontProgram(data: data)), asset, nil)
        } catch {
          throw PDFGraphicsError.malformedContent(
            message: "Malformed embedded Type 1 font program.", operatorName: "Tf", location: location
          )
        }
      }
      if asset.format == .compactFontFormat {
        do {
          let collection = try CompactFontCollection(data: asset.data!, limits: .default)
          guard collection.faces.indices.contains(asset.faceIndex) else { throw FontError.range }
          return (.compact(collection, faceIndex: asset.faceIndex), asset, nil)
        } catch {
          throw PDFGraphicsError.malformedContent(
            message: "Malformed embedded CFF font program.", operatorName: "Tf", location: location
          )
        }
      }
      if asset.format == .sfnt, let data = asset.data {
        do {
          let collection = try SFNTCollection(data: data)
          guard collection.faces.indices.contains(asset.faceIndex) else { throw FontError.range }
          if collection.faces[asset.faceIndex].scalerType != 0x4F54_544F {
            return (.sfnt(collection, data: data, faceIndex: asset.faceIndex), asset, nil)
          }
          if let cff = try collection.faces[asset.faceIndex].data(for: 0x4346_4620, in: data) {
            let compact = try CompactFontCollection(data: cff)
            return (.compact(compact, faceIndex: 0), asset, nil)
          }
        } catch {
          throw PDFGraphicsError.malformedContent(
            message: "Malformed embedded sfnt font program.", operatorName: "Tf", location: location
          )
        }
      }
      for provider in fontEnvironment.providers where provider.supportedAssetFormats.contains(asset.format) {
        do {
          if let face = try await provider.open(asset) { return (.provider(provider, face), asset, nil) }
        } catch {
          throw PDFGraphicsError.fontProviderFailure(
            provider: provider.identifier, message: String(describing: error), location: location
          )
        }
      }
    }
    for permitsSubstitution in [false, true] {
      for provider in fontEnvironment.providers {
        do {
          guard let face = try await provider.resolve(.init(name: name, permitsSubstitution: permitsSubstitution)) else {
            continue
          }
          if let cidSystemInfo, face.isSubstitute,
            try await provider.isCompatible(with: cidSystemInfo, face: face) == false
          {
            continue
          }
          let substitution = face.isSubstitute
            ? GraphicsFontSubstitution(
              requestedName: name,
              resolvedName: face.asset.descriptor.postScriptName,
              providerIdentifier: provider.identifier,
              isCIDCompatible: cidSystemInfo != nil
            )
            : nil
          if face.isSubstitute {
            diagnostics.append(PDFGraphicsDiagnostic(
              identifier: "pdf.graphics.font-substitution",
              message: "Substituted \(face.asset.descriptor.postScriptName) for PDF font \(name).",
              severity: .warning,
              location: location
            ))
          }
          return (.provider(provider, face), face.asset, substitution)
        } catch let error as PDFGraphicsError {
          throw error
        } catch {
          throw PDFGraphicsError.fontProviderFailure(
            provider: provider.identifier, message: String(describing: error), location: location
          )
        }
      }
    }
    if technology == .type3 { return (.type3, asset, nil) }
    return (.unavailable, asset, nil)
  }

  private func resolveEncodingCMap(
    _ object: PDFObject,
    location: PDFContentLocation
  ) async throws -> PDFCMap {
    switch object {
    case .name(let name):
      return try PDFPredefinedCMaps.characterMap(named: name.pdfGraphicsString, limits: limits)
    case .reference(let reference):
      let object = try await document.resolve(reference, in: revision)
      guard case .stream(let stream) = object.value else { throw PDFCMapError.malformed }
      return try await parseCMapStream(stream, location: location)
    default: throw PDFCMapError.malformed
    }
  }

  private func resolveToUnicode(
    _ object: PDFObject?,
    location: PDFContentLocation
  ) async throws -> PDFCMap? {
    guard let object else { return nil }
    do {
      guard case .reference(let reference) = object else { throw PDFCMapError.malformed }
      let resolved = try await document.resolve(reference, in: revision)
      guard case .stream(let stream) = resolved.value else { throw PDFCMapError.malformed }
      return try await parseCMapStream(stream, location: location)
    } catch {
      guard !strict else { throw error }
      diagnostics.append(PDFGraphicsDiagnostic(
        identifier: "pdf.graphics.invalid-to-unicode",
        message: "Ignored a malformed /ToUnicode CMap and continued with lower-priority mappings.",
        severity: .warning,
        location: location
      ))
      return nil
    }
  }

  private func parseCMapStream(
    _ stream: PDFStreamObject,
    location: PDFContentLocation
  ) async throws -> PDFCMap {
    let bytes = try await document.decodedBytes(of: stream)
    var map = try PDFCMapParser(
      maximumBytes: limits.maximumCMapBytes,
      maximumEntries: limits.maximumCMapEntries
    ).parse(bytes)
    for name in map.useCMapNames {
      let base = try PDFPredefinedCMaps.characterMap(named: name, limits: limits)
      try map.inherit(base, maximumEntries: limits.maximumCMapEntries)
    }
    return map
  }

  private func simpleEncoding(
    _ object: PDFObject?,
    defaultName: String,
    location: PDFContentLocation
  ) async throws -> PDFSimpleEncoding {
    guard let object else { return try PDFSimpleEncoding(baseName: defaultName) }
    let value = try await resolvedObject(object)
    switch value {
    case .name(let name): return try PDFSimpleEncoding(baseName: name.pdfGraphicsString)
    case .dictionary(let dictionary):
      let base = try dictionary["BaseEncoding"].map(PDFObjectAccess.name)?.pdfGraphicsString ?? defaultName
      var encoding = try PDFSimpleEncoding(baseName: base)
      if let differences = dictionary["Differences"] {
        try encoding.applyDifferences(PDFObjectAccess.array(differences))
      }
      return encoding
    default:
      throw PDFGraphicsError.malformedCMap(message: "Invalid PDF simple-font Encoding.", location: location)
    }
  }

  private func embeddedAsset(
    _ descriptor: [PDFName: PDFObject]?,
    postScriptName: String,
    expectedTechnology: GraphicsFontTechnology,
    location: PDFContentLocation
  ) async throws -> FontAsset? {
    guard let descriptor else { return nil }
    let keys: [(PDFName, FontAsset.Format)] = [
      ("FontFile", .type1), ("FontFile2", .sfnt), ("FontFile3", .compactFontFormat),
    ]
    for (key, defaultFormat) in keys {
      guard let object = descriptor[key] else { continue }
      guard case .reference(let reference) = object else { throw PDFObjectAccess.TypeMismatch.dictionary }
      let resolved = try await document.resolve(reference, in: revision)
      guard case .stream(let stream) = resolved.value else { throw PDFObjectAccess.TypeMismatch.dictionary }
      let bytes = try await document.decodedBytes(of: stream)
      guard bytes.count <= limits.maximumDecodedFontBytes else {
        throw PDFGraphicsError.limitExceeded("Decoded PDF font-program limit exceeded.", location: location)
      }
      let format: FontAsset.Format
      if key == "FontFile3", let subtype = stream.dictionary["Subtype"] {
        switch try PDFObjectAccess.name(subtype).pdfGraphicsString {
        case "Type1C", "CIDFontType0C": format = .compactFontFormat
        case "OpenType": format = .sfnt
        default: throw PDFGraphicsError.unsupportedFont(subtype: "FontFile3", location: location)
        }
      } else { format = defaultFormat }
      let units: UInt32 = format == .sfnt ? (try? sfntUnitsPerEm(bytes)) ?? 1_000 : 1_000
      return try FontAsset(
        descriptor: FontDescriptor(postScriptName: postScriptName, unitsPerEm: units),
        format: format,
        data: bytes
      )
    }
    return nil
  }

  private func dictionaryValue(_ object: PDFObject?) async throws -> [PDFName: PDFObject]? {
    guard let object else { return nil }
    let resolved = try await resolvedObject(object)
    return try PDFObjectAccess.dictionary(resolved)
  }

  private func simpleWidths(_ dictionary: [PDFName: PDFObject], first: Int) throws -> [UInt32: Double] {
    guard let object = dictionary["Widths"] else { return [:] }
    let values = try PDFObjectAccess.numbers(object)
    guard first >= 0, first <= 255, values.count <= 256 - first else { throw PDFObjectAccess.TypeMismatch.array }
    return Dictionary(uniqueKeysWithValues: values.enumerated().map { (UInt32(first + $0.offset), $0.element) })
  }

  private func cidWidths(_ object: PDFObject?) throws -> [UInt32: Double] {
    guard let object else { return [:] }
    let values = try PDFObjectAccess.array(object)
    var result: [UInt32: Double] = [:]
    var index = 0
    while index < values.count {
      let first = try PDFObjectAccess.integer(values[index]); index += 1
      guard first >= 0, index < values.count else { throw PDFObjectAccess.TypeMismatch.array }
      if case .array(let widths) = values[index] {
        index += 1
        for (offset, value) in widths.enumerated() {
          result[UInt32(first + offset)] = try PDFObjectAccess.number(value)
        }
      } else {
        let last = try PDFObjectAccess.integer(values[index]); index += 1
        guard first <= last, index < values.count else { throw PDFObjectAccess.TypeMismatch.array }
        let width = try PDFObjectAccess.number(values[index]); index += 1
        guard last - first <= limits.maximumCMapEntries - result.count else {
          throw PDFGraphicsError.limitExceeded("PDF CID width limit exceeded.", location: nil)
        }
        for cid in first...last { result[UInt32(cid)] = width }
      }
    }
    return result
  }

  private func defaultVerticalMetric(_ object: PDFObject?) throws -> PDFResolvedFont.VerticalMetric {
    guard let object else { return .standard }
    let values = try PDFObjectAccess.numbers(object)
    guard values.count == 2 else { throw PDFObjectAccess.TypeMismatch.array }
    return .init(advance: values[0], originX: 500, originY: values[1])
  }

  private func cidVerticalMetrics(_ object: PDFObject?) throws -> [UInt32: PDFResolvedFont.VerticalMetric] {
    guard let object else { return [:] }
    let values = try PDFObjectAccess.array(object)
    var result: [UInt32: PDFResolvedFont.VerticalMetric] = [:]
    var index = 0
    while index < values.count {
      let first = try PDFObjectAccess.integer(values[index]); index += 1
      guard first >= 0, index < values.count else { throw PDFObjectAccess.TypeMismatch.array }
      if case .array(let metrics) = values[index] {
        index += 1
        guard metrics.count.isMultiple(of: 3) else { throw PDFObjectAccess.TypeMismatch.array }
        for offset in stride(from: 0, to: metrics.count, by: 3) {
          result[UInt32(first + offset / 3)] = .init(
            advance: try PDFObjectAccess.number(metrics[offset]),
            originX: try PDFObjectAccess.number(metrics[offset + 1]),
            originY: try PDFObjectAccess.number(metrics[offset + 2])
          )
        }
      } else {
        let last = try PDFObjectAccess.integer(values[index]); index += 1
        guard first <= last, index <= values.count - 3 else { throw PDFObjectAccess.TypeMismatch.array }
        let metric = PDFResolvedFont.VerticalMetric(
          advance: try PDFObjectAccess.number(values[index]),
          originX: try PDFObjectAccess.number(values[index + 1]),
          originY: try PDFObjectAccess.number(values[index + 2])
        )
        index += 3
        for cid in first...last { result[UInt32(cid)] = metric }
      }
    }
    return result
  }

  private func cidSystemInfo(_ object: PDFObject) throws -> FontCIDSystemInfo {
    let dictionary = try PDFObjectAccess.dictionary(object)
    guard case .string(let registry)? = dictionary["Registry"],
      case .string(let ordering)? = dictionary["Ordering"]
    else { throw PDFObjectAccess.TypeMismatch.dictionary }
    return try FontCIDSystemInfo(
      registry: String(decoding: registry.bytes, as: UTF8.self),
      ordering: String(decoding: ordering.bytes, as: UTF8.self),
      supplement: try PDFObjectAccess.integer(dictionary["Supplement"] ?? .null)
    )
  }

  private func cidToGlyphMap(_ object: PDFObject?) async throws -> PDFResolvedFont.CIDToGlyph {
    guard let object else { return .identity }
    if case .name(let name) = object, name.pdfGraphicsString == "Identity" { return .identity }
    guard case .reference(let reference) = object else { throw PDFObjectAccess.TypeMismatch.dictionary }
    let resolved = try await document.resolve(reference, in: revision)
    guard case .stream(let stream) = resolved.value else { throw PDFObjectAccess.TypeMismatch.dictionary }
    let bytes = try await document.decodedBytes(of: stream)
    guard bytes.count.isMultiple(of: 2) else { throw PDFObjectAccess.TypeMismatch.dictionary }
    return .table(bytes)
  }

  private func graphicsMatrix(_ object: PDFObject) throws -> GraphicsMatrix {
    let values = try PDFObjectAccess.numbers(object)
    guard values.count == 6 else { throw PDFObjectAccess.TypeMismatch.array }
    return .init(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
  }

  private func sfntUnitsPerEm(_ data: Data) throws -> UInt32 {
    let collection = try SFNTCollection(data: data)
    guard let face = collection.faces.first,
      let head = try face.data(for: 0x6865_6164, in: data), head.count >= 20
    else { throw FontError.invalidData }
    return UInt32(head[18]) << 8 | UInt32(head[19])
  }

  private func symbolicEncodingName(baseName: String) -> String {
    if baseName.contains("Symbol") { return "Symbol" }
    if baseName.contains("ZapfDingbats") { return "ZapfDingbats" }
    return "StandardEncoding"
  }

  private func fontIdentifier(reference: PDFObjectReference?, resourceName: String) -> String {
    if let reference { return "pdf:r\(revision.ordinal):font:\(reference.objectNumber):\(reference.generationNumber)" }
    return "pdf:r\(revision.ordinal):font-direct:\(resourceName)"
  }

  private func resourceIdentifier(
    reference: PDFObjectReference?,
    resourceName: String
  ) -> GraphicsResourceIdentifier {
    .init(rawValue: fontIdentifier(reference: reference, resourceName: resourceName))
  }
}

struct FontCacheKey: Hashable {
  let revision: PDFRevisionIdentifier
  let object: PDFObject
}
