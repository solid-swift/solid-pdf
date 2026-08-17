import Foundation

extension Operators {

  static let paintOps: [OperatorValue] = [
    InitializeClip.instance,
    ClipPath.instance,
    EvenOddClipPath.instance,
    ErasePage.instance,
    FillPath.instance,
    EvenOddFillPath.instance,
    StrokePath.instance,
    ShowPage.instance,
  ]

  enum InitializeClip: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["initclip"]

    func execute(context: isolated Context) async throws {
      try context.applyGraphicsOperation(.clip(.initialize)) {
        $0.clip = GraphicsClip(imageableBounds: context.graphicsDeviceDescriptor.imageableBounds)
      }
    }
  }

  enum ClipPath: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["clip"]

    func execute(context: isolated Context) async throws {
      try intersectClip(context: context, rule: .winding)
    }
  }

  enum EvenOddClipPath: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["eoclip"]

    func execute(context: isolated Context) async throws {
      try intersectClip(context: context, rule: .evenOdd)
    }
  }

  enum ErasePage: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["erasepage"]

    func execute(context: isolated Context) async throws {
      try context.applyGraphicsOperation(.paint(.erasePage)) { _ in }
    }
  }

  enum FillPath: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["fill"]

    func execute(context: isolated Context) async throws {
      try paintFill(context: context, rule: .winding)
    }
  }

  enum EvenOddFillPath: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["eofill"]

    func execute(context: isolated Context) async throws {
      try paintFill(context: context, rule: .evenOdd)
    }
  }

  enum StrokePath: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["stroke"]

    func execute(context: isolated Context) async throws {
      try context.applyGraphicsOperation(.paint(.stroke)) { $0.path.removeAll() }
    }
  }

  enum ShowPage: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["showpage"]

    func execute(context: isolated Context) async throws {
      let before = context.graphicsState
      let after = GraphicsCanonicalState.initial(for: context.graphicsDeviceDescriptor)
      try context.emitGraphicsOperation(.page(.show), before: before, after: after)
      context.graphicsState = after
    }
  }

  static func intersectClip(context: isolated Context, rule: GraphicsFillRule) throws {
    try context.applyGraphicsOperation(.clip(.intersect(rule))) {
      $0.clip = try $0.clip.appending(GraphicsClipConstraint(path: $0.path, rule: rule))
      $0.path.removeAll()
    }
  }

  static func paintFill(context: isolated Context, rule: GraphicsFillRule) throws {
    try context.applyGraphicsOperation(.paint(.fill(rule))) { $0.path.removeAll() }
  }
}
