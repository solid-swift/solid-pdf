import Foundation
import SolidFont

struct GlyphBuildState {
  var metrics: GraphicsGlyphMetrics?
  var cacheBounds: GraphicsRect?
  var cacheable = false
}

extension Context {
  func resolveGlyph(
    selector: GraphicsGlyphSelector,
    characterCode: UInt8?,
    font: Operators.FontDefinition,
    transform: GraphicsMatrix
  ) async throws -> GraphicsGlyphDescription {
    if font.type == 32 {
      return environment.fontManager.glyphCache.pinnedGlyph(
        font: font.identifier,
        selector: selector
      ) ?? .missing(selector)
    }
    let programKey = FontGlyphProgramCacheKey(
      font: font.description.identifier,
      selector: selector,
      writingMode: font.description.writingMode,
      revision: font.dictionary.revision
    )
    let cache = environment.fontManager.glyphCache
    let itemLimit = Int(userParameters.integer("MaxFontItem"))

    if font.type == 3 || font.type == 10 {
      let realizationKey = FontGlyphRealizationCacheKey(
        program: programKey,
        transform: FontGlyphTransformKey(transform),
        device: graphicsDeviceDescriptor,
        paint: graphicsState.paint
      )
      if let cached = cache.realization(for: realizationKey) { return cached }
      let (glyph, cacheable) = try await buildType3Glyph(
        selector: selector,
        characterCode: characterCode,
        font: font,
        transform: transform
      )
      if cacheable { cache.insertRealization(glyph, for: realizationKey, maximumItemBytes: itemLimit) }
      return glyph
    }

    let decoded: GraphicsGlyphDescription
    if let cached = cache.program(for: programKey) {
      decoded = cached
    } else {
      if let face = font.providerFace,
        let provider = environment.fontManager.provider(identifier: face.providerIdentifier)
      {
        let portableSelector = try selector.fontSelector
        let resolved = try await withUserTimeSuspended { try await provider.glyph(portableSelector, in: face) }
        decoded = resolved.map { GraphicsGlyphDescription($0, selector: selector) } ?? .missing(selector)
      } else {
        decoded = try Operators.decodeDictionaryGlyph(selector: selector, font: font)
      }
      cache.insertProgram(decoded, for: programKey, maximumItemBytes: itemLimit)
    }

    return try await applyMetricOverrides(to: decoded, selector: selector, font: font)
  }

  private func buildType3Glyph(
    selector: GraphicsGlyphSelector,
    characterCode: UInt8?,
    font: Operators.FontDefinition,
    transform: GraphicsMatrix
  ) async throws -> (GraphicsGlyphDescription, cacheable: Bool) {
    let procedure: Object
    let arguments: [Object]
    if let buildGlyph = try font.dictionary.object(forKeyIfExists: "BuildGlyph") {
      procedure = buildGlyph
      let glyph: Object = switch selector {
      case .cid(let cid): .integer(Int32(bitPattern: cid))
      case .index(let index): .integer(Int32(bitPattern: index))
      case .character(let code): .integer(Int32(code))
      case .name(let name): .literalName(name)
      }
      arguments = [glyph, font.object]
    } else {
      guard let characterCode else { return (.missing(selector), false) }
      procedure = try font.dictionary.object(forKey: "BuildChar")
      arguments = [.integer(Int32(characterCode)), font.object]
    }

    let savedState = graphicsState
    let savedStack = graphicsStack
    let savedConsumer = graphicsEventConsumer
    let savedBuild = activeGlyphBuild
    let collector = GraphicsDisplayListCollector()
    graphicsState.matrix = transform
    graphicsState.clearPath()
    graphicsEventConsumer = collector
    activeGlyphBuild = GlyphBuildState()
    defer {
      graphicsState = savedState
      graphicsStack = savedStack
      graphicsEventConsumer = savedConsumer
      activeGlyphBuild = savedBuild
    }
    do {
      try await execute(proc: procedure, ops: arguments)
      guard let metrics = activeGlyphBuild?.metrics else { throw Error.invalidFont }
      let build = activeGlyphBuild
      return (GraphicsGlyphDescription(
        selector: selector,
        metrics: metrics,
        program: collector.effects.isEmpty ? .empty : .displayList(GraphicsDisplayList(effects: collector.effects))
      ), build?.cacheable == true)
    } catch {
      collector.abort()
      throw error
    }
  }

  private func applyMetricOverrides(
    to glyph: GraphicsGlyphDescription,
    selector: GraphicsGlyphSelector,
    font: Operators.FontDefinition
  ) async throws -> GraphicsGlyphDescription {
    var metrics = glyph.metrics
    var program = glyph.program
    let key = selector.dictionaryKey

    if let dictionary = try font.dictionary.objectValue(forKeyIfExists: "Metrics", as: DictionaryValue.self),
      let value = try dictionary.object(forKeyIfExists: key)
    {
      let override = try horizontalMetrics(value)
      if let bearing = override.bearing {
        let currentBearing = metrics.bounds.map { GraphicsPoint(x: $0.x, y: $0.y) } ?? .zero
        let offset = GraphicsPoint(x: bearing.x - currentBearing.x, y: bearing.y - currentBearing.y)
        program = program.translated(by: offset)
        if let bounds = metrics.bounds {
          metrics = GraphicsGlyphMetrics(
            horizontalAdvance: metrics.horizontalAdvance,
            verticalAdvance: metrics.verticalAdvance,
            verticalOrigin: metrics.verticalOrigin,
            bounds: GraphicsRect(
              x: bounds.x + offset.x,
              y: bounds.y + offset.y,
              width: bounds.width,
              height: bounds.height
            )
          )
        }
      }
      metrics = GraphicsGlyphMetrics(
        horizontalAdvance: override.advance,
        verticalAdvance: metrics.verticalAdvance,
        verticalOrigin: metrics.verticalOrigin,
        bounds: metrics.bounds
      )
    }

    if let dictionary = try font.dictionary.objectValue(forKeyIfExists: "Metrics2", as: DictionaryValue.self),
      let value = try dictionary.object(forKeyIfExists: key)
    {
      let values = try Operators.numericArray(value, count: 4)
      metrics = GraphicsGlyphMetrics(
        horizontalAdvance: metrics.horizontalAdvance,
        verticalAdvance: GraphicsPoint(x: values[0], y: values[1]),
        verticalOrigin: GraphicsPoint(x: values[2], y: values[3]),
        bounds: metrics.bounds
      )
    }

    if let procedure = try font.dictionary.object(forKeyIfExists: "CDevProc") {
      try procedure.checkProcedure()
      let bounds = metrics.bounds ?? GraphicsRect(x: 0, y: 0, width: 0, height: 0)
      let verticalAdvance = metrics.verticalAdvance ?? .zero
      let verticalOrigin = metrics.verticalOrigin ?? .zero
      let depth = operands.depth
      let selectorObject = selector.cDevObject
      try await execute(proc: procedure, ops: [
        try .real(metrics.horizontalAdvance.x), try .real(metrics.horizontalAdvance.y),
        try .real(bounds.x), try .real(bounds.y), try .real(bounds.maxX), try .real(bounds.maxY),
        try .real(verticalAdvance.x), try .real(verticalAdvance.y),
        try .real(verticalOrigin.x), try .real(verticalOrigin.y), selectorObject,
      ])
      guard operands.depth == depth + 10 else { throw Error.invalidFont }
      let values = try operands.pop(count: 10).reversed().map(Operators.numeric)
      let adjustedBounds = GraphicsRect(
        x: values[2], y: values[3], width: values[4] - values[2], height: values[5] - values[3]
      )
      guard values.allSatisfy(\.isFinite), adjustedBounds.width >= 0, adjustedBounds.height >= 0 else {
        throw Error.invalidFont
      }
      metrics = GraphicsGlyphMetrics(
        horizontalAdvance: GraphicsPoint(x: values[0], y: values[1]),
        verticalAdvance: GraphicsPoint(x: values[6], y: values[7]),
        verticalOrigin: GraphicsPoint(x: values[8], y: values[9]),
        bounds: adjustedBounds
      )
    }

    return GraphicsGlyphDescription(
      selector: selector,
      metrics: metrics,
      program: program,
      resolvedGlyphIndex: glyph.resolvedGlyphIndex
    )
  }

  private func horizontalMetrics(_ object: Object) throws -> (bearing: GraphicsPoint?, advance: GraphicsPoint) {
    if object.type == .integer || object.type == .real {
      return (nil, GraphicsPoint(x: try Operators.numeric(object), y: 0))
    }
    let values = try Operators.arrayObjects(object).map(Operators.numeric)
    switch values.count {
    case 2:
      return (
        GraphicsPoint(x: values[0], y: 0),
        GraphicsPoint(x: values[1], y: 0)
      )
    case 4:
      return (
        GraphicsPoint(x: values[0], y: values[1]),
        GraphicsPoint(x: values[2], y: values[3])
      )
    default:
      throw Error.invalidFont
    }
  }
}

private extension GraphicsGlyphSelector {
  var fontSelector: FontGlyphSelector {
    get throws {
      switch self {
      case .character(let code): .index(UInt32(code))
      case .name(let name): .name(name)
      case .index(let index): .index(index)
      case .cid(let cid): .cid(cid)
      }
    }
  }

  var nameValue: String {
    switch self {
    case .character(let code): String(code)
    case .name(let name): name
    case .index(let index): String(index)
    case .cid(let cid): String(cid)
    }
  }

  var dictionaryKey: Object {
    switch self {
    case .name(let name): .literalName(name)
    case .cid(let cid), .index(let cid):
      cid <= UInt32(Int32.max) ? .integer(Int32(cid)) : .null
    case .character(let code): .integer(Int32(code))
    }
  }

  var cDevObject: Object {
    switch self {
    case .name(let name): .literalName(name)
    case .cid(let cid), .index(let cid): .integer(Int32(bitPattern: cid))
    case .character(let code): .integer(Int32(code))
    }
  }
}

private extension GraphicsGlyphProgram {
  func translated(by offset: GraphicsPoint) -> Self {
    guard offset != .zero else { return self }
    switch self {
    case .outline(let path):
      return .outline(path.transformed(by: GraphicsMatrix(a: 1, b: 0, c: 0, d: 1, tx: offset.x, ty: offset.y)))
    case .bitmap, .displayList, .empty, .missing:
      return self
    }
  }
}

private extension GraphicsPoint {
  static let zero = Self(x: 0, y: 0)
}

extension GraphicsGlyphDescription {
  init(_ glyph: FontGlyph, selector: GraphicsGlyphSelector) {
    let program: GraphicsGlyphProgram = switch glyph.program {
    case .outline(let outline): .outline(GraphicsPath(outline))
    case .bitmap(let bitmap): .bitmap(bitmap)
    case .empty: .empty
    }
    self.init(
      selector: selector,
      metrics: GraphicsGlyphMetrics(
        horizontalAdvance: GraphicsPoint(
          x: glyph.metrics.horizontalAdvance.x,
          y: glyph.metrics.horizontalAdvance.y
        ),
        verticalAdvance: glyph.metrics.verticalAdvance.map { GraphicsPoint(x: $0.x, y: $0.y) },
        verticalOrigin: glyph.metrics.verticalOrigin.map { GraphicsPoint(x: $0.x, y: $0.y) },
        bounds: glyph.metrics.bounds.map {
          GraphicsRect(
            x: $0.minimumX,
            y: $0.minimumY,
            width: $0.maximumX - $0.minimumX,
            height: $0.maximumY - $0.minimumY
          )
        }
      ),
      program: program,
      resolvedGlyphIndex: glyph.resolvedGlyphIndex
    )
  }

  static func missing(_ selector: GraphicsGlyphSelector) -> Self {
    Self(
      selector: selector,
      metrics: GraphicsGlyphMetrics(horizontalAdvance: GraphicsPoint(x: 0, y: 0)),
      program: .missing
    )
  }
}

extension GraphicsPath {
  init(_ outline: FontOutline) {
    var current = GraphicsPoint(x: 0, y: 0)
    var subpathStart = current
    var elements: [Element] = []
    elements.reserveCapacity(outline.elements.count)
    for element in outline.elements {
      switch element {
      case .move(let point):
        current = GraphicsPoint(x: point.x, y: point.y)
        subpathStart = current
        elements.append(.move(to: current))
      case .line(let point):
        current = GraphicsPoint(x: point.x, y: point.y)
        elements.append(.line(to: current))
      case .quadratic(let control, let end):
        let control = GraphicsPoint(x: control.x, y: control.y)
        let end = GraphicsPoint(x: end.x, y: end.y)
        elements.append(
          .curve(
            control1: GraphicsPoint(
              x: current.x + (control.x - current.x) * 2 / 3,
              y: current.y + (control.y - current.y) * 2 / 3
            ),
            control2: GraphicsPoint(
              x: end.x + (control.x - end.x) * 2 / 3,
              y: end.y + (control.y - end.y) * 2 / 3
            ),
            end: end
          )
        )
        current = end
      case .cubic(let first, let second, let end):
        current = GraphicsPoint(x: end.x, y: end.y)
        elements.append(
          .curve(
            control1: GraphicsPoint(x: first.x, y: first.y),
            control2: GraphicsPoint(x: second.x, y: second.y),
            end: current
          )
        )
      case .close:
        current = subpathStart
        elements.append(.close)
      }
    }
    self.init(elements: elements)
  }
}
