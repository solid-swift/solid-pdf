import Foundation

extension Context {

  func resetGraphics(for descriptor: GraphicsDeviceDescriptor) throws {
    let matrix = descriptor.defaultMatrix
    guard descriptor.mediaBounds.x.isFinite,
      descriptor.mediaBounds.y.isFinite,
      descriptor.mediaBounds.width.isFinite,
      descriptor.mediaBounds.height.isFinite,
      descriptor.mediaBounds.width > 0,
      descriptor.mediaBounds.height > 0,
      descriptor.imageableBounds.x.isFinite,
      descriptor.imageableBounds.y.isFinite,
      descriptor.imageableBounds.width.isFinite,
      descriptor.imageableBounds.height.isFinite,
      descriptor.imageableBounds.width >= 0,
      descriptor.imageableBounds.height >= 0,
      descriptor.horizontalResolution.isFinite,
      descriptor.verticalResolution.isFinite,
      descriptor.horizontalResolution > 0,
      descriptor.verticalResolution > 0,
      matrix.a.isFinite,
      matrix.b.isFinite,
      matrix.c.isFinite,
      matrix.d.isFinite,
      matrix.tx.isFinite,
      matrix.ty.isFinite,
      matrix.inverted != nil,
      descriptor.imageableBounds.x >= descriptor.mediaBounds.x,
      descriptor.imageableBounds.y >= descriptor.mediaBounds.y,
      descriptor.imageableBounds.maxX <= descriptor.mediaBounds.maxX,
      descriptor.imageableBounds.maxY <= descriptor.mediaBounds.maxY
    else {
      throw Error.configurationError
    }
    graphicsDeviceDescriptor = descriptor
    graphicsState = .initial(for: descriptor)
    graphicsStack.removeAll()
  }

  func applyGraphicsOperation(
    _ operation: GraphicsOperation,
    mutate: (inout GraphicsCanonicalState) throws -> Void
  ) throws {
    let before = graphicsState.snapshot
    var next = graphicsState
    try mutate(&next)
    let event = GraphicsEvent(operation: operation, before: before, after: next.snapshot)
    do {
      try graphicsEventConsumer?.process(event)
    } catch {
      throw Error.ioError
    }
    graphicsState = next
  }

  func emitGraphicsOperation(
    _ operation: GraphicsOperation,
    before: GraphicsCanonicalState,
    after: GraphicsCanonicalState
  ) throws {
    let event = GraphicsEvent(operation: operation, before: before.snapshot, after: after.snapshot)
    do {
      try graphicsEventConsumer?.process(event)
    } catch {
      throw Error.ioError
    }
  }

  func makeDashObject() throws -> Object {
    if let dashSource = graphicsState.dashSource {
      return dashSource
    }
    try preflightAllocation(bytes: estimatedAllocationSize(count: 0, objectType: .array))
    let object = try Object.array([], access: .unlimited, vm: allocationMode, kind: .literal)
    try adopt(object)
    graphicsState.dashSource = object
    return object
  }

  func pushLanguageGraphicsSave(sequence: UInt64) {
    graphicsStack.append(GraphicsStackFrame(kind: .languageSave(sequence), state: graphicsState))
  }

  func restoreGraphics(to sequence: UInt64) {
    if let index = graphicsStack.lastIndex(where: {
      if case .languageSave(let savedSequence) = $0.kind { return savedSequence == sequence }
      return false
    }) {
      graphicsState = graphicsStack[index].state
      graphicsStack.removeSubrange(index...)
    }
  }
}
