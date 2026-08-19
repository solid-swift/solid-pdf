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
    SetFlatness.instance,
    CurrentFlatness.instance,
    SetStrokeAdjustment.instance,
    CurrentStrokeAdjustment.instance,
    SetGray.instance,
    CurrentGray.instance,
    SetRGBColor.instance,
    CurrentRGBColor.instance,
    SetCMYKColor.instance,
    CurrentCMYKColor.instance,
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
        $0.initializeGraphics(for: context.graphicsDeviceDescriptor)
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
      try context.applyGraphicsOperation(.state(.clipSave)) {
        $0.clipStack.append(GraphicsClipStackEntry(clip: $0.clip, region: $0.resolvedClip))
      }
    }
  }

  enum ClipRestore: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["cliprestore"]

    func execute(context: isolated Context) async throws {
      guard let entry = context.graphicsState.clipStack.last else { throw Error.invalidRestore }
      try context.applyGraphicsOperation(.state(.clipRestore)) {
        _ = $0.clipStack.popLast()
        $0.clip = entry.clip
        $0.resolvedClip = entry.region
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

  enum SetFlatness: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setflat"]

    func execute(context: isolated Context) async throws {
      let flatness = min(100, max(0.2, try numeric(context.operands.pop())))
      try context.applyGraphicsOperation(.state(.setFlatness(flatness))) { $0.flatness = flatness }
    }
  }

  enum CurrentFlatness: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currentflat"]

    func execute(context: isolated Context) async throws {
      context.operands.push(try .real(context.graphicsState.flatness))
    }
  }

  enum SetStrokeAdjustment: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setstrokeadjust"]

    func execute(context: isolated Context) async throws {
      let value: BooleanValue = try context.operands.popAs()
      try context.applyGraphicsOperation(.state(.setStrokeAdjustment(value.value))) {
        $0.strokeAdjustment = value.value
      }
    }
  }

  enum CurrentStrokeAdjustment: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currentstrokeadjust"]

    func execute(context: isolated Context) async throws {
      context.operands.push(.boolean(context.graphicsState.strokeAdjustment))
    }
  }

  enum SetGray: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setgray"]

    func execute(context: isolated Context) async throws {
      let gray = min(1, max(0, try numeric(context.operands.pop())))
      try context.applyGraphicsOperation(.state(.setGray(gray))) {
        $0.colorSpace = .deviceGray(nil)
        $0.colorComponents = [gray]
        $0.paint = .deviceGray(gray)
      }
    }
  }

  enum CurrentGray: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currentgray"]

    func execute(context: isolated Context) async throws {
      let gray = context.graphicsState.colorSpace.isDeviceSpace
        ? context.graphicsState.paint.grayComponent
        : 0
      context.operands.push(try .real(gray))
    }
  }

  enum SetRGBColor: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setrgbcolor"]

    func execute(context: isolated Context) async throws {
      let operands = try context.operands.pop(count: 3)
      let red = clamped(try numeric(operands[2]))
      let green = clamped(try numeric(operands[1]))
      let blue = clamped(try numeric(operands[0]))
      try context.applyGraphicsOperation(.state(.setRGB(red: red, green: green, blue: blue))) {
        $0.colorSpace = .deviceRGB(nil)
        $0.colorComponents = [red, green, blue]
        $0.paint = .deviceRGB(red: red, green: green, blue: blue)
      }
    }
  }

  enum CurrentRGBColor: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currentrgbcolor"]

    func execute(context: isolated Context) async throws {
      let components: (red: Double, green: Double, blue: Double) =
        context.graphicsState.colorSpace.isDeviceSpace
          ? context.graphicsState.paint.rgbComponents
          : (0, 0, 0)
      context.operands.push(
        try .real(components.blue),
        try .real(components.green),
        try .real(components.red)
      )
    }
  }

  enum SetCMYKColor: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setcmykcolor"]

    func execute(context: isolated Context) async throws {
      let operands = try context.operands.pop(count: 4)
      let cyan = clamped(try numeric(operands[3]))
      let magenta = clamped(try numeric(operands[2]))
      let yellow = clamped(try numeric(operands[1]))
      let black = clamped(try numeric(operands[0]))
      try context.applyGraphicsOperation(.state(.setCMYK(
        cyan: cyan,
        magenta: magenta,
        yellow: yellow,
        black: black
      ))) {
        $0.colorSpace = .deviceCMYK(nil)
        $0.colorComponents = [cyan, magenta, yellow, black]
        $0.paint = .deviceCMYK(cyan: cyan, magenta: magenta, yellow: yellow, black: black)
      }
    }
  }

  enum CurrentCMYKColor: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currentcmykcolor"]

    func execute(context: isolated Context) async throws {
      let components: (cyan: Double, magenta: Double, yellow: Double, black: Double) =
        context.graphicsState.colorSpace.isDeviceSpace
          ? context.graphicsState.paint.cmykComponents
          : (0, 0, 0, 1)
      context.operands.push(
        try .real(components.black),
        try .real(components.yellow),
        try .real(components.magenta),
        try .real(components.cyan)
      )
    }
  }

  static func clamped(_ value: Double) -> Double { min(1, max(0, value)) }

  static func numeric(_ object: Object) throws -> Double {
    guard let value = object.value as? NumericConvertible else { throw Error.typeCheck }
    return value.real
  }
}
