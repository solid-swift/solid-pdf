import Foundation
import SolidPDF
import SolidPostScript

extension PDFGraphicsInstructionHandler {
  func realizeType3(
    _ selection: PDFGlyphSelection,
    font: PDFResolvedFont,
    transform: GraphicsMatrix,
    instruction: PDFContentInstruction
  ) async throws -> GraphicsGlyphDescription {
    guard case .type3(_, let procedures, let localResources) = font.mapping,
      let code = selection.code.flatMap(UInt8.init(exactly:))
    else {
      throw PDFGraphicsError.unsupportedFont(subtype: "Type3", location: instruction.location)
    }
    let selector = GraphicsGlyphSelector.character(code)
    let width = font.horizontalWidth(code: UInt32(code), cid: nil)
    if state.text.renderingMode == .invisible {
      return GraphicsGlyphDescription(
        selector: selector,
        metrics: GraphicsGlyphMetrics(horizontalAdvance: .init(x: width, y: 0), bounds: font.fontBounds),
        program: .empty,
        resourceIdentifier: type3GlyphIdentifier(font: font, code: code)
      )
    }
    let glyphName = PDFName(selection.glyphName ?? ".notdef")
    guard let procedureObject = procedures[glyphName] ?? procedures[PDFName(".notdef")],
      case .reference(let procedureReference) = procedureObject
    else {
      throw PDFGraphicsError.fontProgramUnavailable(
        name: font.description.postScriptName ?? font.resourceName,
        location: instruction.location
      )
    }
    if let mode = resources.type3Modes[procedureReference] {
      let key = type3CacheKey(
        font: font,
        procedure: procedureReference,
        code: code,
        transform: transform,
        mode: mode
      )
      if let cached = resources.type3GlyphCache[key] { return cached }
    }
    guard type3Depth < limits.maximumType3Depth else {
      throw PDFGraphicsError.limitExceeded("PDF Type 3 glyph nesting limit exceeded.", location: instruction.location)
    }
    let resolved = try await resources.document.resolve(procedureReference, in: resources.revision)
    guard case .stream(let stream) = resolved.value else {
      throw malformed("Type 3 CharProc is not an indirect stream.", instruction)
    }
    try resources.enter(procedureReference)
    do {
      try resources.push(resources: localResources)
    } catch {
      resources.leave(procedureReference)
      throw error
    }
    defer {
      resources.pop()
      resources.leave(procedureReference)
    }

    let capture = PDFType3GlyphCapture(location: instruction.location)
    var childState = state
    childState.matrix = transform
    childState.pathElements.removeAll(keepingCapacity: false)
    childState.pendingClip = nil
    childState.text = .init()
    let collector = PDFGraphicsCollectorOutput()
    let handler = PDFGraphicsInstructionHandler(
      device: state.device,
      resources: resources,
      limits: limits,
      output: collector,
      initialState: childState,
      type3Capture: capture,
      type3Depth: type3Depth + 1
    )
    let page = try await resources.document.page(at: instruction.location.pageIndex, in: resources.revision)
    let input = PDFContentInput(streams: [stream]) { [document = resources.document] stream in
      try await document.decodedStream(of: stream)
    }
    let parser = PDFContentParser(
      input: input,
      revision: resources.revision,
      page: page,
      maximumScratchBytes: limits.maximumScratchBytes,
      resourceStack: instruction.location.resourceStack + [procedureReference]
    )
    try await PDFContentExecutor(
      parser: parser,
      handler: handler,
      maximumOperators: limits.maximumOperatorsPerPage
    ).execute()
    guard let capturedMetrics = capture.metrics, let mode = capture.mode else {
      throw malformed("Type 3 CharProc did not establish metrics.", instruction)
    }
    let displayList = GraphicsDisplayList(
      effects: collector.collector.effects,
      resourceIdentifier: type3GlyphIdentifier(font: font, code: code)
    )
    let footprint = displayList.storageFootprint(maximumDepth: limits.maximumType3Depth)
    guard let footprint,
      footprint.displayBytes <= limits.maximumScratchBytes,
      footprint.sourceBytes <= limits.maximumScratchBytes - footprint.displayBytes
    else {
      throw PDFGraphicsError.limitExceeded("PDF Type 3 glyph storage limit exceeded.", location: instruction.location)
    }
    let glyph = GraphicsGlyphDescription(
      selector: selector,
      metrics: GraphicsGlyphMetrics(
        horizontalAdvance: .init(x: width, y: 0),
        bounds: capturedMetrics.bounds ?? font.fontBounds
      ),
      program: displayList.effects.isEmpty ? .empty : .displayList(displayList),
      resourceIdentifier: displayList.resourceIdentifier
    )
    resources.type3Modes[procedureReference] = mode
    if localResources != nil {
      resources.type3GlyphCache[type3CacheKey(
        font: font,
        procedure: procedureReference,
        code: code,
        transform: transform,
        mode: mode
      )] = glyph
    }
    return glyph
  }

  private func type3CacheKey(
    font: PDFResolvedFont,
    procedure: PDFObjectReference,
    code: UInt8,
    transform: GraphicsMatrix,
    mode: PDFType3GlyphCapture.Mode
  ) -> PDFType3GlyphCacheKey {
    let neutral = GraphicsTextPaint(
      paint: .deviceGray(0),
      colorSpace: .deviceGray,
      components: [0]
    )
    let nonstroking = state.snapshot(stroking: false)
    let stroking = state.snapshot(stroking: true)
    return PDFType3GlyphCacheKey(
      fontIdentifier: font.description.resourceIdentifier,
      procedure: procedure,
      code: code,
      transform: transform,
      nonstrokingState: mode == .uncolored ? nonstroking.replacingColor(with: neutral) : nonstroking,
      strokingState: mode == .uncolored ? stroking.replacingColor(with: neutral) : stroking,
      mode: mode
    )
  }

  private func type3GlyphIdentifier(font: PDFResolvedFont, code: UInt8) -> GraphicsResourceIdentifier {
    GraphicsResourceIdentifier(rawValue: "\(font.description.resourceIdentifier.rawValue):type3:\(code)")
  }
}
