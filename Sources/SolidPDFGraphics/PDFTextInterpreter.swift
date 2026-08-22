import Foundation
import SolidFont
import SolidPDF
import SolidPostScript

extension PDFGraphicsInstructionHandler {
  func beginText(_ instruction: PDFContentInstruction) throws {
    try operands(instruction, count: 0)
    textMatrix = .identity
    textLineMatrix = .identity
    textClipElements.removeAll(keepingCapacity: true)
  }

  func endText(_ instruction: PDFContentInstruction) throws {
    try operands(instruction, count: 0)
    if !textClipElements.isEmpty {
      let before = state.snapshot(stroking: false)
      state.clip = try state.clip.appending(.init(
        path: GraphicsPath(elements: textClipElements),
        rule: .winding
      ))
      try emit(GraphicsEvent(
        operation: .clip(.intersect(.winding)),
        before: before,
        after: state.snapshot(stroking: false),
        origin: origin(instruction.location)
      ))
    }
    textMatrix = nil
    textLineMatrix = nil
    textClipElements.removeAll(keepingCapacity: true)
  }

  func setCharacterSpacing(_ instruction: PDFContentInstruction) throws {
    state.text.characterSpacing = try oneNumber(instruction)
  }

  func setWordSpacing(_ instruction: PDFContentInstruction) throws {
    state.text.wordSpacing = try oneNumber(instruction)
  }

  func setHorizontalScaling(_ instruction: PDFContentInstruction) throws {
    state.text.horizontalScale = try oneNumber(instruction) / 100
  }

  func setTextLeading(_ instruction: PDFContentInstruction) throws {
    state.text.leading = try oneNumber(instruction)
  }

  func setTextFont(_ instruction: PDFContentInstruction) async throws {
    try operands(instruction, count: 2)
    let name = try PDFObjectAccess.name(instruction.operands[0])
    let size = try PDFObjectAccess.number(instruction.operands[1])
    let before = state.snapshot(stroking: false)
    state.text.font = try await resources.font(named: name, location: instruction.location)
    state.text.fontSize = size
    try emit(GraphicsEvent(
      operation: .state(.setFont(state.text.font!.description)),
      before: before,
      after: state.snapshot(stroking: false),
      origin: origin(instruction.location, resource: state.text.font!.description.resourceIdentifier)
    ))
  }

  func setTextRenderingMode(_ instruction: PDFContentInstruction) throws {
    let value = try oneInteger(instruction)
    guard let mode = GraphicsTextRenderingMode(rawValue: value) else {
      throw malformed("Invalid PDF text rendering mode.", instruction)
    }
    state.text.renderingMode = mode
  }

  func setTextRise(_ instruction: PDFContentInstruction) throws {
    state.text.rise = try oneNumber(instruction)
  }

  func moveText(_ instruction: PDFContentInstruction, setsLeading: Bool) throws {
    let values = try twoNumbers(instruction)
    if setsLeading { state.text.leading = -values.y }
    try translateTextLine(x: values.x, y: values.y, instruction: instruction)
  }

  func setTextMatrix(_ instruction: PDFContentInstruction) throws {
    try operands(instruction, count: 6)
    let values = try instruction.operands.map(PDFObjectAccess.number)
    let matrix = GraphicsMatrix(
      a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5]
    )
    textMatrix = matrix
    textLineMatrix = matrix
  }

  func nextTextLine(_ instruction: PDFContentInstruction) throws {
    try operands(instruction, count: 0)
    try translateTextLine(x: 0, y: -state.text.leading, instruction: instruction)
  }

  func showText(_ instruction: PDFContentInstruction) async throws {
    try operands(instruction, count: 1)
    guard case .string(let string) = instruction.operands[0] else {
      throw malformed("Tj requires a string.", instruction)
    }
    try await emitText(elements: [.bytes(string.bytes)], instruction: instruction)
  }

  func showTextArray(_ instruction: PDFContentInstruction) async throws {
    try operands(instruction, count: 1)
    let values = try PDFObjectAccess.array(instruction.operands[0])
    var elements: [PDFTextElement] = []
    elements.reserveCapacity(values.count)
    for value in values {
      switch value {
      case .string(let string): elements.append(.bytes(string.bytes))
      case .number: elements.append(.adjustment(try PDFObjectAccess.number(value)))
      default: throw malformed("TJ accepts only strings and numbers.", instruction)
      }
    }
    try await emitText(elements: elements, instruction: instruction)
  }

  func showNextLine(_ instruction: PDFContentInstruction, setsSpacing: Bool) async throws {
    if setsSpacing {
      try operands(instruction, count: 3)
      state.text.wordSpacing = try PDFObjectAccess.number(instruction.operands[0])
      state.text.characterSpacing = try PDFObjectAccess.number(instruction.operands[1])
      guard case .string(let string) = instruction.operands[2] else {
        throw malformed("Double-quote text operator requires a string.", instruction)
      }
      try translateTextLine(x: 0, y: -state.text.leading, instruction: instruction)
      try await emitText(elements: [.bytes(string.bytes)], instruction: instruction)
    } else {
      try operands(instruction, count: 1)
      guard case .string(let string) = instruction.operands[0] else {
        throw malformed("Single-quote text operator requires a string.", instruction)
      }
      try translateTextLine(x: 0, y: -state.text.leading, instruction: instruction)
      try await emitText(elements: [.bytes(string.bytes)], instruction: instruction)
    }
  }

  private func emitText(
    elements: [PDFTextElement],
    instruction: PDFContentInstruction
  ) async throws {
    guard let font = state.text.font, textMatrix != nil else {
      throw malformed("Text showing requires a selected font and text matrix.", instruction)
    }
    let sourceBytes = elements.reduce(into: Data()) { result, element in
      if case .bytes(let bytes) = element { result.append(bytes) }
    }
    var placements: [PDFPositionedGlyph] = []
    var sourceOffset = 0
    for element in elements {
      switch element {
      case .adjustment(let value):
        let scale = -value / 1_000 * state.text.fontSize
        if font.description.writingMode == 0 {
          advanceTextMatrix(x: scale * state.text.horizontalScale, y: 0)
        } else {
          advanceTextMatrix(x: 0, y: scale)
        }
      case .bytes(let bytes):
        var byteOffset = 0
        while byteOffset < bytes.count {
          interpretedGlyphCount += 1
          guard interpretedGlyphCount <= limits.maximumGlyphsPerPage else {
            throw PDFGraphicsError.limitExceeded("PDF page glyph limit exceeded.", location: instruction.location)
          }
          let selection = try decode(bytes, offset: byteOffset, font: font, instruction: instruction)
          let glyph = try await realize(selection, font: font, instruction: instruction)
          let placement = try placement(
            glyph,
            selection: selection,
            font: font,
            sourceOffset: sourceOffset,
            instruction: instruction
          )
          placements.append(placement)
          byteOffset += selection.bytes.count
          sourceOffset += selection.bytes.count
          advanceTextMatrix(x: placement.textAdvance.x, y: placement.textAdvance.y)
        }
      }
    }
    let run = GraphicsGlyphRun(
      rootFont: font.description,
      glyphs: placements.map(\.placement),
      sourceBytes: sourceBytes,
      renderingMode: state.text.renderingMode,
      style: textStyle,
      textReplacement: currentTextReplacement
    )
    let snapshot = state.snapshot(stroking: !state.text.renderingMode.fills)
    try emit(GraphicsEvent(
      operation: .paint(.text(run)),
      before: snapshot,
      after: snapshot,
      origin: origin(instruction.location, resource: font.description.resourceIdentifier)
    ))
  }

  private func decode(
    _ bytes: Data,
    offset: Int,
    font: PDFResolvedFont,
    instruction: PDFContentInstruction
  ) throws -> PDFGlyphSelection {
    switch font.mapping {
    case .simple(let encoding), .type3(let encoding, _, _):
      let code = bytes[offset]
      let entry = encoding[code]
      return PDFGlyphSelection(
        bytes: Data([code]),
        code: UInt32(code),
        cid: nil,
        glyphName: entry.glyphName,
        encodingUnicode: entry.unicodeScalars
      )
    case .composite(let cmap, _):
      do {
        let decoded = try cmap.decode(bytes, from: offset)
        guard let cid = decoded.cid ?? decoded.notdefCID else {
          throw PDFCMapError.invalidCode
        }
        return PDFGlyphSelection(bytes: decoded.bytes, code: nil, cid: cid, glyphName: nil, encodingUnicode: nil)
      } catch {
        throw PDFGraphicsError.malformedCMap(message: String(describing: error), location: instruction.location)
      }
    }
  }

  private func realize(
    _ selection: PDFGlyphSelection,
    font: PDFResolvedFont,
    instruction: PDFContentInstruction
  ) async throws -> GraphicsGlyphDescription {
    let selector: GraphicsGlyphSelector = selection.cid.map(GraphicsGlyphSelector.cid)
      ?? .character(UInt8(selection.code!))
    let resolved: FontGlyph?
    do {
      switch font.source {
      case .type1(let program):
        resolved = try program.glyph(
          named: selection.glyphName ?? ".notdef",
          selector: fontSelector(selection, glyphIndex: 0)
        )
      case .compact(let collection, let faceIndex):
        let glyphIndex: UInt32?
        if let cid = selection.cid {
          glyphIndex = collection.glyphIndex(faceIndex: faceIndex, cid: cid)
        } else if let glyphName = selection.glyphName {
          glyphIndex = collection.glyphIndex(faceIndex: faceIndex, glyphName: glyphName)
        } else {
          glyphIndex = collection.glyphIndex(faceIndex: faceIndex, encodedCode: UInt8(selection.code!))
        }
        guard let glyphIndex else { throw unavailableGlyph(font, instruction: instruction) }
        resolved = try collection.glyph(
          faceIndex: faceIndex,
          glyphIndex: glyphIndex,
          selector: fontSelector(selection, glyphIndex: glyphIndex)
        )
      case .sfnt(let collection, let data, let faceIndex):
        let glyphIndex: UInt32?
        if let cid = selection.cid, case .composite(_, let descendant) = font.mapping {
          glyphIndex = descendant.cidToGlyph.glyphIndex(for: cid)
        } else if let scalar = selection.encodingUnicode?.only {
          glyphIndex = try collection.glyphIndex(data: data, faceIndex: faceIndex, unicodeScalar: scalar)
        } else {
          glyphIndex = selection.code
        }
        guard let glyphIndex else { throw unavailableGlyph(font, instruction: instruction) }
        resolved = try collection.glyph(
          data: data,
          faceIndex: faceIndex,
          glyphIndex: glyphIndex,
          selector: fontSelector(selection, glyphIndex: glyphIndex)
        )
      case .provider(let provider, let face):
        let providerSelector: FontGlyphSelector
        if let cid = selection.cid, case .composite(_, let descendant) = font.mapping {
          if case .identity = descendant.cidToGlyph { providerSelector = .cid(cid) }
          else if let glyph = descendant.cidToGlyph.glyphIndex(for: cid) { providerSelector = .index(glyph) }
          else { throw unavailableGlyph(font, instruction: instruction) }
        } else {
          providerSelector = .name(selection.glyphName ?? ".notdef")
        }
        resolved = try await provider.glyph(providerSelector, in: face)
      case .type3:
        return try await realizeType3(
          selection,
          font: font,
          transform: try type3GlyphTransform(font: font, instruction: instruction),
          instruction: instruction
        )
      case .unavailable:
        throw PDFGraphicsError.fontProgramUnavailable(
          name: font.description.postScriptName ?? font.resourceName,
          location: instruction.location
        )
      }
    } catch let error as PDFGraphicsError {
      throw error
    } catch {
      if case .provider(let provider, _) = font.source {
        throw PDFGraphicsError.fontProviderFailure(
          provider: provider.identifier,
          message: String(describing: error),
          location: instruction.location
        )
      }
      throw PDFGraphicsError.malformedContent(
        message: "Malformed PDF glyph program.", operatorName: instruction.name, location: instruction.location
      )
    }
    guard let resolved else { throw unavailableGlyph(font, instruction: instruction) }
    let decoded = GraphicsGlyphDescription(resolved, selector: selector)
    return GraphicsGlyphDescription(
      selector: selector,
      metrics: GraphicsGlyphMetrics(
        horizontalAdvance: GraphicsPoint(x: font.horizontalWidth(code: selection.code ?? selection.cid!, cid: selection.cid), y: 0),
        verticalAdvance: selection.cid.flatMap(font.verticalMetric).map { GraphicsPoint(x: 0, y: $0.advance) }
          ?? decoded.metrics.verticalAdvance,
        verticalOrigin: selection.cid.flatMap(font.verticalMetric).map {
          GraphicsPoint(x: $0.originX, y: $0.originY)
        } ?? decoded.metrics.verticalOrigin,
        bounds: decoded.metrics.bounds
      ),
      program: decoded.program,
      resolvedGlyphIndex: decoded.resolvedGlyphIndex,
      resourceIdentifier: glyphIdentifier(font: font, selection: selection, glyphIndex: decoded.resolvedGlyphIndex)
    )
  }

  private func placement(
    _ glyph: GraphicsGlyphDescription,
    selection: PDFGlyphSelection,
    font: PDFResolvedFont,
    sourceOffset: Int,
    instruction: PDFContentInstruction
  ) throws -> PDFPositionedGlyph {
    guard let textMatrix else { throw malformed("Missing PDF text matrix.", instruction) }
    let vertical = font.description.writingMode == 1
    let originAdjustment = vertical ? glyph.metrics.verticalOrigin ?? .init(x: 0, y: 0) : .init(x: 0, y: 0)
    let glyphOrigin = GraphicsMatrix(
      a: 1, b: 0, c: 0, d: 1, tx: -originAdjustment.x, ty: -originAdjustment.y
    )
    let textScale = GraphicsMatrix(
      a: state.text.fontSize * state.text.horizontalScale,
      b: 0,
      c: 0,
      d: state.text.fontSize,
      tx: 0,
      ty: state.text.rise
    )
    let transform = glyphOrigin
      .concatenated(with: font.fontMatrix)
      .concatenated(with: textScale)
      .concatenated(with: textMatrix)
      .concatenated(with: state.matrix)
    let textAdvance: GraphicsPoint
    if vertical {
      let width = glyph.metrics.verticalAdvance?.y ?? -1_000
      textAdvance = GraphicsPoint(
        x: 0,
        y: width / 1_000 * state.text.fontSize + state.text.characterSpacing
      )
    } else {
      let wordSpacing = selection.bytes.count == 1 && selection.bytes[0] == 0x20 ? state.text.wordSpacing : 0
      textAdvance = GraphicsPoint(
        x: (glyph.metrics.horizontalAdvance.x / 1_000 * state.text.fontSize
          + state.text.characterSpacing + wordSpacing) * state.text.horizontalScale,
        y: 0
      )
    }
    let userAdvance = textMatrix.transformDistance(textAdvance)
    let unicode = unicodeMapping(selection, glyph: glyph, font: font)
    let placement = GraphicsGlyphPlacement(
      glyph: glyph,
      origin: transform.transform(.init(x: 0, y: 0)),
      transform: transform,
      advance: userAdvance,
      font: font.description,
      sourceBytes: selection.bytes,
      unicodeScalars: unicode.scalars,
      sourceRange: sourceOffset..<(sourceOffset + selection.bytes.count),
      unicodeProvenance: unicode.provenance
    )
    if state.text.renderingMode.clips {
      guard case .outline(let outline) = glyph.program else {
        throw PDFGraphicsError.unsupported(.textClipping, location: instruction.location)
      }
      textClipElements.append(contentsOf: outline.transformed(by: transform).elements)
    }
    return PDFPositionedGlyph(placement: placement, textAdvance: textAdvance)
  }

  private func type3GlyphTransform(
    font: PDFResolvedFont,
    instruction: PDFContentInstruction
  ) throws -> GraphicsMatrix {
    guard let textMatrix else { throw malformed("Missing PDF text matrix.", instruction) }
    let textScale = GraphicsMatrix(
      a: state.text.fontSize * state.text.horizontalScale,
      b: 0,
      c: 0,
      d: state.text.fontSize,
      tx: 0,
      ty: state.text.rise
    )
    return font.fontMatrix
      .concatenated(with: textScale)
      .concatenated(with: textMatrix)
      .concatenated(with: state.matrix)
  }

  private func unicodeMapping(
    _ selection: PDFGlyphSelection,
    glyph: GraphicsGlyphDescription,
    font: PDFResolvedFont
  ) -> (scalars: [Unicode.Scalar]?, provenance: GraphicsUnicodeProvenance?) {
    if let value = font.toUnicode?.unicodeMappings[selection.bytes] { return (value, .pdfToUnicode) }
    if let value = selection.encodingUnicode { return (value, .pdfEncoding) }
    if let cid = selection.cid {
      let key = Data([UInt8(truncatingIfNeeded: cid >> 8), UInt8(truncatingIfNeeded: cid)])
      if let value = font.collectionUnicode?.unicodeMappings[key] { return (value, .pdfCMap) }
    }
    if case .sfnt(_, let data, let faceIndex) = font.source,
      let glyphIndex = glyph.resolvedGlyphIndex,
      let map = try? SFNTCharacterMap(data: data, faceIndex: faceIndex),
      let scalarValue = map.uniqueUnicodeScalar(for: glyphIndex),
      let scalar = Unicode.Scalar(scalarValue)
    {
      return ([scalar], .fontCharacterMap)
    }
    if let glyphName = selection.glyphName, let value = AdobeGlyphList.unicodeScalars(for: glyphName) {
      return (value, .glyphName)
    }
    return (nil, nil)
  }

  private func unavailableGlyph(
    _ font: PDFResolvedFont,
    instruction: PDFContentInstruction
  ) -> PDFGraphicsError {
    .fontProgramUnavailable(
      name: font.description.postScriptName ?? font.resourceName,
      location: instruction.location
    )
  }

  private func fontSelector(_ selection: PDFGlyphSelection, glyphIndex: UInt32) -> FontGlyphSelector {
    if let cid = selection.cid { return .cid(cid) }
    if let name = selection.glyphName { return .name(name) }
    return .index(glyphIndex)
  }

  private func glyphIdentifier(
    font: PDFResolvedFont,
    selection: PDFGlyphSelection,
    glyphIndex: UInt32?
  ) -> GraphicsResourceIdentifier {
    let selected = glyphIndex.map(String.init) ?? selection.cid.map { "cid\($0)" }
      ?? selection.code.map { "code\($0)" } ?? "missing"
    return GraphicsResourceIdentifier(rawValue: "\(font.description.resourceIdentifier.rawValue):glyph:\(selected)")
  }

  private var textStyle: GraphicsTextStyle {
    GraphicsTextStyle(
      fill: textPaint(state.nonstroking, overprint: state.nonstrokingOverprint),
      stroke: textPaint(state.stroking, overprint: state.strokingOverprint)
    )
  }

  private func textPaint(_ color: PDFGraphicsState.ColorState, overprint: Bool) -> GraphicsTextPaint {
    GraphicsTextPaint(
      paint: color.paint,
      colorSpace: color.space,
      colorRealization: color.realization,
      components: color.components,
      overprint: overprint
    )
  }

  private func translateTextLine(x: Double, y: Double, instruction: PDFContentInstruction) throws {
    guard let line = textLineMatrix else { throw malformed("Missing PDF text line matrix.", instruction) }
    let translated = GraphicsMatrix(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y).concatenated(with: line)
    textLineMatrix = translated
    textMatrix = translated
  }

  private func advanceTextMatrix(x: Double, y: Double) {
    guard let textMatrix else { return }
    self.textMatrix = GraphicsMatrix(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y).concatenated(with: textMatrix)
  }

  private func oneNumber(_ instruction: PDFContentInstruction) throws -> Double {
    try operands(instruction, count: 1)
    return try PDFObjectAccess.number(instruction.operands[0])
  }

  private func oneInteger(_ instruction: PDFContentInstruction) throws -> Int {
    try operands(instruction, count: 1)
    return try PDFObjectAccess.integer(instruction.operands[0])
  }

  private func twoNumbers(_ instruction: PDFContentInstruction) throws -> GraphicsPoint {
    try operands(instruction, count: 2)
    return GraphicsPoint(
      x: try PDFObjectAccess.number(instruction.operands[0]),
      y: try PDFObjectAccess.number(instruction.operands[1])
    )
  }
}

private enum PDFTextElement {
  case bytes(Data)
  case adjustment(Double)
}

struct PDFGlyphSelection {
  let bytes: Data
  let code: UInt32?
  let cid: UInt32?
  let glyphName: String?
  let encodingUnicode: [Unicode.Scalar]?
}

private struct PDFPositionedGlyph {
  let placement: GraphicsGlyphPlacement
  let textAdvance: GraphicsPoint
}

private extension Array where Element == Unicode.Scalar {
  var only: Unicode.Scalar? { count == 1 ? self[0] : nil }
}
