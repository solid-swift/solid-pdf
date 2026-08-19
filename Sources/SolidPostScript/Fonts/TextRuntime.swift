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
    let key = FontGlyphCacheKey(
      font: font.description.identifier,
      selector: selector,
      transform: transform,
      writingMode: font.description.writingMode,
      revision: font.dictionary.revision
    )
    if let cached = environment.fontManager.glyphCache.glyph(for: key) { return cached }

    let glyph: GraphicsGlyphDescription
    if font.type == 3 {
      glyph = try await buildType3Glyph(
        selector: selector,
        characterCode: characterCode,
        font: font,
        transform: transform
      )
    } else if let face = font.identifier.providerFace,
      let provider = environment.fontManager.provider(identifier: face.providerIdentifier)
    {
      let portableSelector = try selector.fontSelector
      let resolved = try await withUserTimeSuspended { try await provider.glyph(portableSelector, in: face) }
      glyph = resolved.map { GraphicsGlyphDescription($0, selector: selector) } ?? .missing(selector)
    } else {
      glyph = try Operators.decodeDictionaryGlyph(selector: selector, font: font)
    }

    environment.fontManager.glyphCache.insert(
      glyph,
      for: key,
      maximumItemBytes: Int(userParameters.integer("MaxFontItem"))
    )
    return glyph
  }

  private func buildType3Glyph(
    selector: GraphicsGlyphSelector,
    characterCode: UInt8?,
    font: Operators.FontDefinition,
    transform: GraphicsMatrix
  ) async throws -> GraphicsGlyphDescription {
    let procedure: Object
    let arguments: [Object]
    if let buildGlyph = try font.dictionary.object(forKeyIfExists: "BuildGlyph") {
      procedure = buildGlyph
      arguments = [.literalName(selector.nameValue), font.object]
    } else {
      guard let characterCode else { return .missing(selector) }
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
      return GraphicsGlyphDescription(
        selector: selector,
        metrics: metrics,
        program: collector.effects.isEmpty ? .empty : .displayList(GraphicsDisplayList(effects: collector.effects))
      )
    } catch {
      collector.abort()
      throw error
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
      program: program
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
