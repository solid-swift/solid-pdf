import Foundation

extension Operators {
  static let textOps: [OperatorValue] = [
    Show.instance, AShow.instance, WidthShow.instance, AWidthShow.instance,
    XShow.instance, YShow.instance, XYShow.instance, GlyphShow.instance,
    StringWidth.instance, CharPath.instance, CShow.instance, KShow.instance,
    SetCacheDevice.instance, SetCacheDevice2.instance, SetCharWidth.instance,
  ]

  enum Show: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["show"]
    func execute(context: isolated Context) async throws {
      try await showString(context.operands.pop(), context: context)
    }
  }

  enum AShow: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["ashow"]
    func execute(context: isolated Context) async throws {
      let (string, ay, ax) = try context.operands.pop3()
      let addition = GraphicsPoint(x: try numeric(ax), y: try numeric(ay))
      try await showString(string, perGlyph: { _ in addition }, context: context)
    }
  }

  enum WidthShow: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["widthshow"]
    func execute(context: isolated Context) async throws {
      let (string, character, cy, cx) = try context.operands.pop4()
      let code = try character.value(as: IntegerValue.self).value
      guard (0...255).contains(code) else { throw Error.rangeCheck }
      let addition = GraphicsPoint(x: try numeric(cx), y: try numeric(cy))
      try await showString(string, perGlyph: { $0 == UInt8(code) ? addition : .zero }, context: context)
    }
  }

  enum AWidthShow: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["awidthshow"]
    func execute(context: isolated Context) async throws {
      let values = try context.operands.pop(count: 6)
      let string = values[0]
      let ay = try numeric(values[1])
      let ax = try numeric(values[2])
      let code = try values[3].value(as: IntegerValue.self).value
      let cy = try numeric(values[4])
      let cx = try numeric(values[5])
      guard (0...255).contains(code) else { throw Error.rangeCheck }
      try await showString(string, perGlyph: { character in
        var result = GraphicsPoint(x: ax, y: ay)
        if character == UInt8(code) { result = GraphicsPoint(x: result.x + cx, y: result.y + cy) }
        return result
      }, context: context)
    }
  }

  enum XShow: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["xshow"]
    func execute(context: isolated Context) async throws {
      let (displacements, string) = try context.operands.pop2()
      let values = try displacementValues(displacements)
      try await showString(string, displacements: values.map { GraphicsPoint(x: $0, y: 0) }, context: context)
    }
  }

  enum YShow: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["yshow"]
    func execute(context: isolated Context) async throws {
      let (displacements, string) = try context.operands.pop2()
      let values = try displacementValues(displacements)
      try await showString(string, displacements: values.map { GraphicsPoint(x: 0, y: $0) }, context: context)
    }
  }

  enum XYShow: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["xyshow"]
    func execute(context: isolated Context) async throws {
      let (displacements, string) = try context.operands.pop2()
      let values = try displacementValues(displacements)
      guard values.count.isMultiple(of: 2) else { throw Error.rangeCheck }
      let points = stride(from: 0, to: values.count, by: 2).map {
        GraphicsPoint(x: values[$0], y: values[$0 + 1])
      }
      try await showString(string, displacements: points, context: context)
    }
  }

  enum GlyphShow: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["glyphshow"]
    func execute(context: isolated Context) async throws {
      let name = try context.operands.pop().value(as: NameValue.self).value
      try await showGlyph(.name(name), characterCode: nil, context: context)
    }
  }

  enum StringWidth: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["stringwidth"]
    func execute(context: isolated Context) async throws {
      let string = try context.operands.pop().value(as: StringValue.self)
      let bytes = try string.characters(in: string.range)
      let font = try currentFontDefinition(context: context)
      let transform = glyphTransform(font: font, ctm: context.graphicsState.matrix, origin: .zero)
      var width = GraphicsPoint.zero
      for byte in bytes {
        let selector = try glyphSelector(byte, font: font)
        let glyph = try await context.resolveGlyph(
          selector: selector,
          characterCode: byte,
          font: font,
          transform: transform
        )
        let advance = font.matrix.transformDistance(glyph.metrics.horizontalAdvance)
        width = GraphicsPoint(x: width.x + advance.x, y: width.y + advance.y)
      }
      context.operands.push(try .real(width.y), try .real(width.x))
    }
  }

  enum CharPath: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["charpath"]
    func execute(context: isolated Context) async throws {
      _ = try context.operands.popAs(BooleanValue.self)
      let string = try context.operands.pop().value(as: StringValue.self)
      let bytes = try string.characters(in: string.range)
      guard let start = context.graphicsState.path.currentPoint else { throw Error.noCurrentPoint }
      let font = try currentFontDefinition(context: context)
      var current = start
      var additions: [GraphicsPath.Element] = []
      for byte in bytes {
        let selector = try glyphSelector(byte, font: font)
        let transform = glyphTransform(font: font, ctm: context.graphicsState.matrix, origin: current)
        let glyph = try await context.resolveGlyph(
          selector: selector,
          characterCode: byte,
          font: font,
          transform: transform
        )
        if case .outline(let outline) = glyph.program {
          additions.append(contentsOf: outline.transformed(by: transform).elements)
        }
        let advance = context.graphicsState.matrix.transformDistance(
          font.matrix.transformDistance(glyph.metrics.horizontalAdvance)
        )
        current = GraphicsPoint(x: current.x + advance.x, y: current.y + advance.y)
      }
      additions.append(.move(to: current))
      try context.applyGraphicsOperation(.path(.textOutline)) { state in
        for element in additions { try state.appendPath(element) }
      }
    }
  }

  enum CShow: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["cshow"]
    func execute(context: isolated Context) async throws {
      let (string, procedure) = try context.operands.pop2()
      try procedure.checkProcedure()
      let value = try string.value(as: StringValue.self)
      let bytes = try value.characters(in: value.range)
      let originalFont = context.graphicsState.fontSource
      defer { context.graphicsState.fontSource = originalFont }
      for character in bytes {
        let font = try currentFontDefinition(context: context)
        let selector = try glyphSelector(character, font: font)
        let transform = glyphTransform(font: font, ctm: context.graphicsState.matrix, origin: .zero)
        let glyph = try await context.resolveGlyph(
          selector: selector,
          characterCode: character,
          font: font,
          transform: transform
        )
        let advance = font.matrix.transformDistance(glyph.metrics.horizontalAdvance)
        try await context.execute(
          proc: procedure,
          ops: [try .real(advance.y), try .real(advance.x), .integer(Int32(character))]
        )
        context.graphicsState.fontSource = originalFont
      }
    }
  }

  enum KShow: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["kshow"]
    func execute(context: isolated Context) async throws {
      let (string, procedure) = try context.operands.pop2()
      try procedure.checkProcedure()
      let value = try string.value(as: StringValue.self)
      let bytes = Array(try value.characters(in: value.range))
      guard !bytes.isEmpty else { return }
      let font = try currentFontDefinition(context: context)
      guard font.type != 0 else { throw Error.invalidFont }
      for index in bytes.indices {
        _ = try await showGlyph(
          try glyphSelector(bytes[index], font: currentFontDefinition(context: context)),
          characterCode: bytes[index],
          context: context
        )
        guard index + 1 < bytes.count else { continue }
        let savedFont = context.graphicsState.fontSource
        do {
          try await context.execute(
            proc: procedure,
            ops: [.integer(Int32(bytes[index + 1])), .integer(Int32(bytes[index]))]
          )
          context.graphicsState.fontSource = savedFont
        } catch {
          context.graphicsState.fontSource = savedFont
          throw error
        }
      }
    }
  }

  enum SetCharWidth: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setcharwidth"]
    func execute(context: isolated Context) async throws {
      let (wy, wx) = try context.operands.pop2()
      guard context.activeGlyphBuild != nil else { throw Error.undefined }
      context.activeGlyphBuild?.metrics = GraphicsGlyphMetrics(
        horizontalAdvance: GraphicsPoint(x: try numeric(wx), y: try numeric(wy))
      )
    }
  }

  enum SetCacheDevice: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setcachedevice"]
    func execute(context: isolated Context) async throws {
      let values = try context.operands.pop(count: 6).reversed().map(numeric)
      guard context.activeGlyphBuild != nil else { throw Error.undefined }
      try setGlyphMetrics(values, context: context)
    }
  }

  enum SetCacheDevice2: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setcachedevice2"]
    func execute(context: isolated Context) async throws {
      let values = try context.operands.pop(count: 10).reversed().map(numeric)
      guard context.activeGlyphBuild != nil else { throw Error.undefined }
      try setGlyphMetrics(values, context: context)
      context.activeGlyphBuild?.metrics = GraphicsGlyphMetrics(
        horizontalAdvance: GraphicsPoint(x: values[0], y: values[1]),
        verticalAdvance: GraphicsPoint(x: values[6], y: values[7]),
        verticalOrigin: GraphicsPoint(x: values[8], y: values[9]),
        bounds: context.activeGlyphBuild?.cacheBounds
      )
    }
  }

  private static func showString(
    _ object: Object,
    perGlyph: (UInt8) -> GraphicsPoint = { _ in .zero },
    displacements: [GraphicsPoint]? = nil,
    afterGlyph: ((UInt8, GraphicsPoint) async throws -> Void)? = nil,
    context: isolated Context
  ) async throws {
    let string = try object.value(as: StringValue.self)
    let bytes = Array(try string.characters(in: string.range))
    if let displacements, displacements.count != bytes.count { throw Error.rangeCheck }
    for (index, byte) in bytes.enumerated() {
      let extra = displacements?[index] ?? perGlyph(byte)
      let advance = try await showGlyph(
        try glyphSelector(byte, font: currentFontDefinition(context: context)),
        characterCode: byte,
        extraAdvance: extra,
        context: context
      )
      try await afterGlyph?(byte, advance)
    }
  }

  @discardableResult
  private static func showGlyph(
    _ selector: GraphicsGlyphSelector,
    characterCode: UInt8?,
    extraAdvance: GraphicsPoint = .zero,
    context: isolated Context
  ) async throws -> GraphicsPoint {
    guard let origin = context.graphicsState.path.currentPoint else { throw Error.noCurrentPoint }
    let font = try currentFontDefinition(context: context)
    let transform = glyphTransform(font: font, ctm: context.graphicsState.matrix, origin: origin)
    let glyph = try await context.resolveGlyph(
      selector: selector,
      characterCode: characterCode,
      font: font,
      transform: transform
    )
    var advance = font.matrix.transformDistance(glyph.metrics.horizontalAdvance)
    advance = GraphicsPoint(x: advance.x + extraAdvance.x, y: advance.y + extraAdvance.y)
    let deviceAdvance = context.graphicsState.matrix.transformDistance(advance)
    let end = GraphicsPoint(x: origin.x + deviceAdvance.x, y: origin.y + deviceAdvance.y)
    let placement = GraphicsGlyphPlacement(
      glyph: glyph,
      origin: origin,
      transform: transform,
      advance: advance
    )
    let run = GraphicsGlyphRun(rootFont: font.description, glyphs: [placement])
    try context.applyGraphicsOperation(.paint(.text(run))) { try $0.appendPath(.move(to: end)) }
    return advance
  }

  private static func currentFontDefinition(context: isolated Context) throws -> FontDefinition {
    guard let object = context.graphicsState.fontSource else { throw Error.invalidFont }
    return try fontDefinition(object, context: context)
  }

  private static func glyphSelector(_ byte: UInt8, font: FontDefinition) throws -> GraphicsGlyphSelector {
    let encoding = try font.dictionary.objectValue(forKey: "Encoding", as: ArrayValue.self)
    let name = try encoding.object(at: UInt(byte), for: .read).value(as: NameValue.self).value
    return .name(name)
  }

  private static func glyphTransform(
    font: FontDefinition,
    ctm: GraphicsMatrix,
    origin: GraphicsPoint
  ) -> GraphicsMatrix {
    let combined = font.matrix.concatenated(with: ctm)
    return GraphicsMatrix(
      a: combined.a,
      b: combined.b,
      c: combined.c,
      d: combined.d,
      tx: origin.x + combined.tx - ctm.tx,
      ty: origin.y + combined.ty - ctm.ty
    )
  }

  private static func displacementValues(_ object: Object) throws -> [Double] {
    if let string = object.value as? StringValue {
      return try EncodedNumberString.decode(string.characters(in: string.range)).map(numeric)
    }
    return try arrayObjects(object).map(numeric)
  }

  private static func setGlyphMetrics(_ values: [Double], context: isolated Context) throws {
    guard values.count >= 6,
      values.allSatisfy(\.isFinite),
      values[2] <= values[4], values[3] <= values[5]
    else { throw Error.rangeCheck }
    let bounds = GraphicsRect(
      x: values[2], y: values[3], width: values[4] - values[2], height: values[5] - values[3]
    )
    context.activeGlyphBuild?.metrics = GraphicsGlyphMetrics(
      horizontalAdvance: GraphicsPoint(x: values[0], y: values[1]),
      bounds: bounds
    )
    context.activeGlyphBuild?.cacheBounds = bounds
    context.activeGlyphBuild?.cacheable = true
  }
}

private extension GraphicsPoint {
  static let zero = Self(x: 0, y: 0)
}
