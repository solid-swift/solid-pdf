import Foundation
import SolidRaster

extension Operators {
  static let patternOps: [OperatorValue] = [
    MakePattern.instance,
    SetPattern.instance,
  ]

  enum MakePattern: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["makepattern"]

    func execute(context: isolated Context) async throws {
      let matrix = try readMatrix(context.operands.pop())
      let prototypeObject = try context.operands.pop()
      let prototype = try prototypeObject.value(as: DictionaryValue.self)
      try prototype.access.check(.read)
      let type = Int(try prototype.objectValue(forKey: "PatternType", as: IntegerValue.self).value)
      guard type == 1 || type == 2 else { throw Error.rangeCheck }
      if type == 1 { try validateTilingPattern(prototype) }
      if type == 2 {
        try validateShadingDictionaryStructure(
          prototype.objectValue(forKey: "Shading", as: DictionaryValue.self)
        )
      }

      let adjustedMatrix = matrix.concatenated(with: context.graphicsState.matrix)
      let savedState = context.graphicsState
      let gstateBytes = GraphicsStateValue.footprint(savedState)
      var entries: [Object: Object] = [:]
      try prototype.forEachUnchecked { entries[$0] = $1 }

      let savedMode = context.allocationMode
      context.allocationMode = .local
      defer { context.allocationMode = savedMode }
      try context.preflightAllocation(bytes: gstateBytes, vm: .local)
      let gstate = try Object.graphicsState(savedState, vm: .local)
      let matrixObject = try makeMatrixObject(adjustedMatrix, context: context)
      let implementation = try Object.dictionary(
        uniqueKeysWithValues: [
          (.literalName("GState"), gstate),
          (.literalName("Matrix"), matrixObject),
        ],
        access: .noAccess,
        vm: .local,
        kind: .literal
      )
      entries[.literalName("Implementation")] = implementation
      try context.preflightAllocation(
        bytes: context.estimatedAllocationSize(count: entries.count, objectType: .dictionary),
        vm: .local
      )
      let pattern = try Object.dictionary(
        uniqueKeysWithValues: entries.map { ($0.key, $0.value) },
        access: .readOnly,
        vm: .local,
        kind: .literal
      )
      try context.adopt([gstate, matrixObject, implementation, pattern])
      if type == 2 {
        _ = try await compileShadingPattern(
          dictionary: try pattern.value(as: DictionaryValue.self),
          context: context
        )
      }
      context.operands.push(pattern)
    }
  }

  enum SetPattern: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setpattern"]

    func execute(context: isolated Context) async throws {
      try requireColorOperationAllowed(context)
      let pattern = try context.operands.pop()
      let dictionary = try pattern.value(as: DictionaryValue.self)
      let patternType = Int(try dictionary.objectValue(forKey: "PatternType", as: IntegerValue.self).value)
      guard patternType == 1 || patternType == 2 else { throw Error.rangeCheck }
      let paintType = patternType == 1
        ? Int(try dictionary.objectValue(forKey: "PaintType", as: IntegerValue.self).value)
        : 1

      let underlying: PostScriptColorSpace?
      let underlyingSelection: PostScriptColorSelection?
      let components: [Double]
      switch context.graphicsState.colorSpace {
      case .pattern(_, let base):
        underlying = base
        underlyingSelection = context.graphicsState.colorSelection.patternUnderlyingSelection
        components = context.graphicsState.colorComponents
      default:
        underlying = paintType == 2 ? context.graphicsState.colorSpace : nil
        underlyingSelection = paintType == 2 ? context.graphicsState.colorSelection : nil
        components = paintType == 2 ? context.graphicsState.colorComponents : []
      }
      let source = try makePatternColorSpaceObject(underlying, context: context)
      let space = PostScriptColorSpace.pattern(source: source, underlying: underlying)
      let selection = PostScriptColorSelection(
        source: space,
        route: .pattern(underlying: underlyingSelection?.route)
      )
      let paint = try await resolvePattern(
        pattern,
        dictionary: dictionary,
        underlying: underlyingSelection,
        components: components,
        context: context
      )
      try context.applyGraphicsOperation(.state(.setColorSpace(space.description))) {
        $0.colorSelection = selection
        $0.colorComponents = components
        $0.patternSource = pattern
        $0.paint = .pattern(paint)
      }
    }
  }

  static func validateTilingPattern(_ dictionary: DictionaryValue) throws {
    try dictionary.object(forKey: "PaintProc").checkProcedure()
    let bounds = try numericArray(dictionary.object(forKey: "BBox"))
    guard bounds.count == 4, bounds.allSatisfy(\.isFinite), bounds[0] <= bounds[2], bounds[1] <= bounds[3]
    else { throw Error.rangeCheck }
    let xStep = try numeric(dictionary.object(forKey: "XStep"))
    let yStep = try numeric(dictionary.object(forKey: "YStep"))
    guard xStep != 0, yStep != 0 else { throw Error.rangeCheck }
    let paintType = try dictionary.objectValue(forKey: "PaintType", as: IntegerValue.self).value
    let tilingType = try dictionary.objectValue(forKey: "TilingType", as: IntegerValue.self).value
    guard paintType == 1 || paintType == 2, (1...3).contains(tilingType) else { throw Error.rangeCheck }
    if let xuid = try dictionary.object(forKeyIfExists: "XUID") {
      _ = try arrayObjects(xuid).map { try $0.value(as: IntegerValue.self) }
    }
  }

  static func resolvePattern(
    _ pattern: Object,
    dictionary: DictionaryValue,
    underlying: PostScriptColorSelection?,
    components: [Double],
    context: isolated Context
  ) async throws -> GraphicsPatternPaint {
    let type = Int(try dictionary.objectValue(forKey: "PatternType", as: IntegerValue.self).value)
    if type == 2 {
      guard underlying == nil, components.isEmpty else { throw Error.typeCheck }
      return .shading(try await compileShadingPattern(dictionary: dictionary, context: context))
    }
    let paintType = Int(try dictionary.objectValue(forKey: "PaintType", as: IntegerValue.self).value)
    guard (paintType == 1 && underlying == nil) || (paintType == 2 && underlying != nil) else {
      throw Error.typeCheck
    }
    let basePaint: GraphicsPaint?
    if let underlying {
      basePaint = graphicsPaint(try await resolveColor(components, in: underlying, context: context))
    } else {
      basePaint = nil
    }
    let tiling = try await compileTilingPattern(pattern, dictionary: dictionary, context: context)
    return .tiling(tiling, underlying: basePaint)
  }

  static func compileTilingPattern(
    _ pattern: Object,
    dictionary: DictionaryValue,
    context: isolated Context
  ) async throws -> GraphicsTilingPattern {
    let implementation = try dictionary.objectValue(forKey: "Implementation", as: DictionaryValue.self)
    let gstateObject = try implementation.objectUnchecked(forKey: "GState") ?? { throw Error.undefined }()
    let matrixObject = try implementation.objectUnchecked(forKey: "Matrix") ?? { throw Error.undefined }()
    let savedState = try gstateObject.value(as: GraphicsStateValue.self).state()
    let matrix = try readMatrix(matrixObject)
    let xuid = try dictionary.object(forKeyIfExists: "XUID").map {
      try arrayObjects($0).map { try $0.value(as: IntegerValue.self).value }
    }
    let key = patternCacheKey(
      dictionary: dictionary,
      xuid: xuid,
      matrix: matrix,
      savedState: savedState,
      context: context
    )
    if let cached = context.environment.patternCache.pattern(for: key) { return cached }

    guard context.encapsulatedPaintDepth < 16,
      context.activeEncapsulatedPaintAllocations.insert(dictionary.allocation.identity).inserted
    else { throw Error.limitCheck }
    context.encapsulatedPaintDepth += 1
    defer {
      context.encapsulatedPaintDepth -= 1
      context.activeEncapsulatedPaintAllocations.remove(dictionary.allocation.identity)
    }

    let values = try numericArray(dictionary.object(forKey: "BBox"))
    let bounds = GraphicsRect(
      x: values[0],
      y: values[1],
      width: values[2] - values[0],
      height: values[3] - values[1]
    )
    let cellPath = try rectanglePath(
      x: bounds.x,
      y: bounds.y,
      width: bounds.width,
      height: bounds.height,
      matrix: matrix
    )
    let cellRegion = try GraphicsPathGeometry.region(
      for: cellPath,
      rule: .winding,
      flatness: savedState.flatness
    )
    let consumer = GraphicsDisplayListCollector()
    let callerState = context.graphicsState
    let callerStack = context.graphicsStack
    let callerOperands = context.operands
    let callerDictionaries = context.dictionaries
    let callerConsumer = context.graphicsEventConsumer
    defer {
      context.graphicsState = callerState
      context.graphicsStack = callerStack
      context.operands = callerOperands
      context.dictionaries = callerDictionaries
      context.graphicsEventConsumer = callerConsumer
    }
    var cellState = savedState
    cellState.matrix = matrix
    cellState.clearPath()
    cellState.clip = try cellState.clip.appending(.init(path: cellPath, rule: .winding))
    cellState.resolvedClip = try GraphicsPathGeometry.intersect(cellState.resolvedClip, cellRegion)
    context.graphicsState = cellState
    context.graphicsStack.removeAll()
    context.graphicsEventConsumer = consumer
    let uncolored = try dictionary.objectValue(forKey: "PaintType", as: IntegerValue.self).value == 2
    if uncolored {
      context.uncoloredPatternExecutionDepth += 1
    }
    defer { if uncolored { context.uncoloredPatternExecutionDepth -= 1 } }
    try await context.execute(proc: dictionary.object(forKey: "PaintProc"), ops: [pattern])
    let result = GraphicsTilingPattern(
      paintType: Int(try dictionary.objectValue(forKey: "PaintType", as: IntegerValue.self).value),
      tilingType: Int(try dictionary.objectValue(forKey: "TilingType", as: IntegerValue.self).value),
      bounds: bounds,
      xStep: try numeric(dictionary.object(forKey: "XStep")),
      yStep: try numeric(dictionary.object(forKey: "YStep")),
      matrix: matrix,
      displayList: GraphicsDisplayList(effects: consumer.effects)
    )
    context.environment.patternCache.insert(
      result,
      for: key,
      maximumItemBytes: Int(context.userParameters.integer("MaxPatternItem"))
    )
    return result
  }

  static func compileShadingPattern(
    dictionary: DictionaryValue,
    context: isolated Context
  ) async throws -> GraphicsShading {
    let implementation = try dictionary.objectValue(forKey: "Implementation", as: DictionaryValue.self)
    let gstateObject = try implementation.objectUnchecked(forKey: "GState") ?? { throw Error.undefined }()
    let matrixObject = try implementation.objectUnchecked(forKey: "Matrix") ?? { throw Error.undefined }()
    let savedState = try gstateObject.value(as: GraphicsStateValue.self).state()
    let matrix = try readMatrix(matrixObject)
    let xuid = try dictionary.object(forKeyIfExists: "XUID").map {
      try arrayObjects($0).map { try $0.value(as: IntegerValue.self).value }
    }
    let key = patternCacheKey(
      dictionary: dictionary,
      xuid: xuid,
      matrix: matrix,
      savedState: savedState,
      context: context
    )
    if let cached = context.environment.patternCache.shading(for: key) { return cached }
    let shading = try await compileShading(
      dictionary.object(forKey: "Shading"),
      matrix: matrix,
      includeBackground: true,
      reusableDataRequired: true,
      context: context
    )
    context.environment.patternCache.insert(
      shading,
      for: key,
      maximumItemBytes: Int(context.userParameters.integer("MaxPatternItem"))
    )
    return shading
  }

  private static func patternCacheKey(
    dictionary: DictionaryValue,
    xuid: [Int32]?,
    matrix: GraphicsMatrix,
    savedState: GraphicsCanonicalState,
    context: isolated Context
  ) -> PatternCacheKey {
    PatternCacheKey(
      identity: xuid == nil ? dictionary.allocation.identity : nil,
      revision: dictionary.revision,
      xuid: xuid,
      matrix: matrix,
      device: context.graphicsDeviceDescriptor,
      savedState: savedState.snapshot,
      colorSelectionFingerprint: savedState.colorSelection.cacheFingerprint
    )
  }

  static func makePatternColorSpaceObject(
    _ underlying: PostScriptColorSpace?,
    context: isolated Context
  ) throws -> Object {
    let elements: [Object]
    if let underlying {
      guard let source = underlying.source else {
        let name: String = switch underlying {
        case .deviceGray: "DeviceGray"
        case .deviceRGB: "DeviceRGB"
        case .deviceCMYK: "DeviceCMYK"
        default: throw Error.rangeCheck
        }
        elements = [.literalName("Pattern"), .literalName(name)]
        return try makeReadOnlyArray(elements, context: context)
      }
      elements = [.literalName("Pattern"), source]
    } else {
      elements = [.literalName("Pattern")]
    }
    return try makeReadOnlyArray(elements, context: context)
  }

  private static func makeReadOnlyArray(_ objects: [Object], context: isolated Context) throws -> Object {
    try context.preflightAllocation(bytes: context.estimatedAllocationSize(count: objects.count, objectType: .array))
    let object = try Object.array(objects, access: .readOnly, vm: context.allocationMode, kind: .literal)
    try context.adopt(object)
    return object
  }
}
