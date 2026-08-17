import Foundation

extension Operators {

  static let graphicsStateOps: [OperatorValue] = [
    GraphicsSave.instance,
    GraphicsRestore.instance,
    GraphicsRestoreAll.instance,
    InitializeGraphics.instance,
    ClipSave.instance,
    ClipRestore.instance,
    MakeGraphicsState.instance,
    CurrentGraphicsState.instance,
    SetGraphicsState.instance,
    SetLineWidth.instance,
    CurrentLineWidth.instance,
    SetLineCap.instance,
    CurrentLineCap.instance,
    SetLineJoin.instance,
    CurrentLineJoin.instance,
    SetMiterLimit.instance,
    CurrentMiterLimit.instance,
    SetDash.instance,
    CurrentDash.instance,
    SetGray.instance,
    CurrentGray.instance,
  ]

  enum GraphicsSave: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["gsave"]

    func execute(context: isolated Context) async throws {
      guard context.graphicsStack.count < LanguageLimits.maximumGraphicsStackDepth else { throw Error.limitCheck }
      let saved = context.graphicsState
      try context.applyGraphicsOperation(.state(.save)) { $0.clipStack.removeAll() }
      context.graphicsStack.append(GraphicsStackFrame(kind: .graphicsSave, state: saved))
    }
  }

  enum GraphicsRestore: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["grestore"]

    func execute(context: isolated Context) async throws {
      let before = context.graphicsState
      guard let frame = context.graphicsStack.last else { return }
      let after: GraphicsCanonicalState
      let removesFrame: Bool
      switch frame.kind {
      case .graphicsSave:
        after = frame.state
        removesFrame = true
      case .languageSave:
        after = frame.state
        removesFrame = false
      }
      try context.emitGraphicsOperation(.state(.restore), before: before, after: after)
      if removesFrame {
        _ = context.graphicsStack.popLast()
      }
      context.graphicsState = after
    }
  }

  enum GraphicsRestoreAll: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["grestoreall"]

    func execute(context: isolated Context) async throws {
      let before = context.graphicsState
      let languageIndex = context.graphicsStack.lastIndex {
        if case .languageSave = $0.kind { return true }
        return false
      }
      let after: GraphicsCanonicalState
      var nextStack = context.graphicsStack
      if let languageIndex {
        after = context.graphicsStack[languageIndex].state
        nextStack.removeSubrange((languageIndex + 1)...)
      } else if let first = context.graphicsStack.first {
        after = first.state
        nextStack.removeAll()
      } else {
        after = .initial(for: context.graphicsDeviceDescriptor)
      }
      try context.emitGraphicsOperation(.state(.restoreAll), before: before, after: after)
      context.graphicsStack = nextStack
      context.graphicsState = after
    }
  }

  enum InitializeGraphics: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["initgraphics"]

    func execute(context: isolated Context) async throws {
      try context.applyGraphicsOperation(.state(.initialize)) {
        $0 = .initial(for: context.graphicsDeviceDescriptor)
      }
    }
  }

  enum ClipSave: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["clipsave"]

    func execute(context: isolated Context) async throws {
      guard context.graphicsState.clipStack.count < LanguageLimits.maximumClipStackDepth else {
        throw Error.limitCheck
      }
      try context.applyGraphicsOperation(.state(.clipSave)) { $0.clipStack.append($0.clip) }
    }
  }

  enum ClipRestore: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["cliprestore"]

    func execute(context: isolated Context) async throws {
      guard let clip = context.graphicsState.clipStack.last else { throw Error.invalidRestore }
      try context.applyGraphicsOperation(.state(.clipRestore)) {
        _ = $0.clipStack.popLast()
        $0.clip = clip
      }
    }
  }

  enum MakeGraphicsState: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["gstate"]

    func execute(context: isolated Context) async throws {
      let state = context.graphicsState
      try state.checkStorage(in: context.allocationMode)
      let footprint = GraphicsStateValue.footprint(state)
      try context.preflightAllocation(bytes: footprint)
      let object = try Object.graphicsState(state, vm: context.allocationMode)
      try context.adopt(object)
      context.operands.push(object)
    }
  }

  enum CurrentGraphicsState: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currentgstate"]

    func execute(context: isolated Context) async throws {
      let object = try context.operands.pop()
      let value = try object.value(as: GraphicsStateValue.self)
      try value.update(context.graphicsState, context: context)
      context.operands.push(object)
    }
  }

  enum SetGraphicsState: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setgstate"]

    func execute(context: isolated Context) async throws {
      let value: GraphicsStateValue = try context.operands.popAs()
      let state = value.state()
      try context.applyGraphicsOperation(.state(.setGraphicsState)) { $0 = state }
    }
  }

  enum SetLineWidth: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setlinewidth"]

    func execute(context: isolated Context) async throws {
      let width = try numeric(context.operands.pop())
      guard width >= 0 else { throw Error.rangeCheck }
      try context.applyGraphicsOperation(.state(.setLineWidth(width))) { $0.lineWidth = width }
    }
  }

  enum CurrentLineWidth: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currentlinewidth"]

    func execute(context: isolated Context) async throws {
      context.operands.push(try .real(context.graphicsState.lineWidth))
    }
  }

  enum SetLineCap: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setlinecap"]

    func execute(context: isolated Context) async throws {
      let raw: IntegerValue = try context.operands.popAs()
      guard let cap = GraphicsLineCap(rawValue: raw.value) else { throw Error.rangeCheck }
      try context.applyGraphicsOperation(.state(.setLineCap(cap))) { $0.lineCap = cap }
    }
  }

  enum CurrentLineCap: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currentlinecap"]

    func execute(context: isolated Context) async throws {
      context.operands.push(.integer(context.graphicsState.lineCap.rawValue))
    }
  }

  enum SetLineJoin: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setlinejoin"]

    func execute(context: isolated Context) async throws {
      let raw: IntegerValue = try context.operands.popAs()
      guard let join = GraphicsLineJoin(rawValue: raw.value) else { throw Error.rangeCheck }
      try context.applyGraphicsOperation(.state(.setLineJoin(join))) { $0.lineJoin = join }
    }
  }

  enum CurrentLineJoin: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currentlinejoin"]

    func execute(context: isolated Context) async throws {
      context.operands.push(.integer(context.graphicsState.lineJoin.rawValue))
    }
  }

  enum SetMiterLimit: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setmiterlimit"]

    func execute(context: isolated Context) async throws {
      let limit = try numeric(context.operands.pop())
      guard limit >= 1 else { throw Error.rangeCheck }
      try context.applyGraphicsOperation(.state(.setMiterLimit(limit))) { $0.miterLimit = limit }
    }
  }

  enum CurrentMiterLimit: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currentmiterlimit"]

    func execute(context: isolated Context) async throws {
      context.operands.push(try .real(context.graphicsState.miterLimit))
    }
  }

  enum SetDash: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setdash"]

    func execute(context: isolated Context) async throws {
      let operands = try context.operands.pop(count: 2)
      let phase = try numeric(operands[0])
      let array = try operands[1].value(as: ArrayValue.self)
      let objects = try array.objects(in: array.range)
      let pattern = try objects.map(numeric)
      guard pattern.allSatisfy({ $0 >= 0 }), pattern.isEmpty || pattern.contains(where: { $0 > 0 }) else {
        throw Error.rangeCheck
      }
      let dash = GraphicsDash(pattern: pattern, phase: phase)
      try context.applyGraphicsOperation(.state(.setDash(dash))) {
        $0.dash = dash
        $0.dashSource = operands[1]
      }
    }
  }

  enum CurrentDash: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currentdash"]

    func execute(context: isolated Context) async throws {
      let pattern = try context.makeDashObject()
      context.operands.push(try .real(context.graphicsState.dash.phase), pattern)
    }
  }

  enum SetGray: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setgray"]

    func execute(context: isolated Context) async throws {
      let gray = min(1, max(0, try numeric(context.operands.pop())))
      try context.applyGraphicsOperation(.state(.setGray(gray))) { $0.paint = .deviceGray(gray) }
    }
  }

  enum CurrentGray: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currentgray"]

    func execute(context: isolated Context) async throws {
      guard case .deviceGray(let gray) = context.graphicsState.paint else {
        preconditionFailure("The initial graphics tranche only supports DeviceGray")
      }
      context.operands.push(try .real(gray))
    }
  }

  static func numeric(_ object: Object) throws -> Double {
    guard let value = object.value as? NumericConvertible else { throw Error.typeCheck }
    return value.real
  }
}
