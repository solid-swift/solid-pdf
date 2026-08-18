import Foundation
import SolidRaster

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
    CopyPage.instance,
  ]

  enum InitializeClip: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["initclip"]

    func execute(context: isolated Context) async throws {
      let descriptor = context.graphicsDeviceDescriptor
      let region: RasterRegion
      do {
        region = try .rectangle(descriptor.imageableBounds.rasterRect)
      } catch {
        throw error.postScriptError
      }
      try context.applyGraphicsOperation(.clip(.initialize)) {
        $0.clip = GraphicsClip(imageableBounds: descriptor.imageableBounds)
        $0.resolvedClip = region
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
      try context.applyGraphicsOperation(.paint(.stroke)) { $0.clearPath() }
    }
  }

  enum ShowPage: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["showpage"]

    func execute(context: isolated Context) async throws {
      let before = context.graphicsState
      var after = before
      after.initializeGraphics(for: context.graphicsDeviceDescriptor)
      try context.emitGraphicsOperation(.page(.show), before: before, after: after)
      context.graphicsState = after
    }
  }

  enum CopyPage: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["copypage"]

    func execute(context: isolated Context) async throws {
      let state = context.graphicsState
      try context.emitGraphicsOperation(.page(.copy), before: state, after: state)
    }
  }

  static func intersectClip(context: isolated Context, rule: GraphicsFillRule) throws {
    let candidate = try GraphicsPathGeometry.region(
      for: context.graphicsState.path,
      rule: rule,
      flatness: context.graphicsState.flatness
    )
    let resolved = try GraphicsPathGeometry.intersect(context.graphicsState.resolvedClip, candidate)
    try context.applyGraphicsOperation(.clip(.intersect(rule))) {
      $0.clip = try $0.clip.appending(GraphicsClipConstraint(path: $0.path, rule: rule))
      $0.resolvedClip = resolved
      $0.clearPath()
    }
  }

  static func paintFill(context: isolated Context, rule: GraphicsFillRule) throws {
    try context.applyGraphicsOperation(.paint(.fill(rule))) { $0.clearPath() }
  }
}
