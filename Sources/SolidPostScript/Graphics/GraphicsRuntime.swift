import Foundation

extension Context {

  func resetGraphics(for descriptor: GraphicsDeviceDescriptor) throws {
    let configuration = GraphicsPageDeviceConfiguration(
      identifier: GraphicsDeviceIdentifier(),
      pageSize: GraphicsSize(
        width: descriptor.mediaBounds.width * 72 / descriptor.horizontalResolution,
        height: descriptor.mediaBounds.height * 72 / descriptor.verticalResolution
      ),
      imagingBoundingBox: nil,
      numberOfCopies: 1,
      name: "SolidVirtualPageDevice",
      descriptor: descriptor,
      colorants: descriptor.colorants,
      trappingEnabled: false,
      trappingDetails: descriptor.trapping.defaultDetails
    )
    try resetGraphics(for: configuration)
  }

  func resetGraphics(for configuration: GraphicsPageDeviceConfiguration) throws {
    let descriptor = configuration.descriptor
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
      descriptor.defaultFlatness.isFinite,
      descriptor.defaultFlatness >= 0.2,
      descriptor.defaultFlatness <= 100,
      descriptor.minimumSmoothness.isFinite,
      descriptor.maximumSmoothness.isFinite,
      descriptor.defaultSmoothness.isFinite,
      descriptor.minimumSmoothness >= 0,
      descriptor.maximumSmoothness <= 1,
      descriptor.minimumSmoothness <= descriptor.defaultSmoothness,
      descriptor.defaultSmoothness <= descriptor.maximumSmoothness,
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
    let device = PostScriptDeviceRecord(configuration: configuration)
    graphicsState = .initial(for: descriptor, device: device)
    graphicsStack.removeAll()
  }

  func applyGraphicsOperation(
    _ operation: GraphicsOperation,
    mutate: (inout GraphicsCanonicalState) throws -> Void
  ) throws {
    guard imageDataSourceCallbackDepth == 0 else { throw Error.undefined }
    if let build = activeGlyphBuild, build.metrics == nil { throw Error.undefined }
    let before = graphicsState.snapshot
    var next = graphicsState
    try mutate(&next)
    let event = GraphicsEvent(operation: operation, before: before, after: next.snapshot)
    do {
      try graphicsEventConsumer?.process(event)
    } catch GraphicsStorageAccountingError.limitExceeded {
      throw Error.limitCheck
    } catch {
      throw Error.ioError
    }
    if graphicsEventConsumer?.takeStorageAccountingError() != nil { throw Error.limitCheck }
    graphicsState = next
  }

  func emitGraphicsOperation(
    _ operation: GraphicsOperation,
    before: GraphicsCanonicalState,
    after: GraphicsCanonicalState
  ) throws {
    guard imageDataSourceCallbackDepth == 0 else { throw Error.undefined }
    let event = GraphicsEvent(operation: operation, before: before.snapshot, after: after.snapshot)
    do {
      try graphicsEventConsumer?.process(event)
    } catch GraphicsStorageAccountingError.limitExceeded {
      throw Error.limitCheck
    } catch {
      throw Error.ioError
    }
    if graphicsEventConsumer?.takeStorageAccountingError() != nil { throw Error.limitCheck }
  }

  func beginGraphicsImage(_ descriptor: GraphicsImageDescriptor) throws {
    guard imageDataSourceCallbackDepth == 0 else { throw Error.undefined }
    let snapshot = graphicsState.snapshot
    let event = GraphicsEvent(operation: .paint(.image(descriptor)), before: snapshot, after: snapshot)
    do {
      try graphicsEventConsumer?.beginImage(event)
    } catch GraphicsStorageAccountingError.limitExceeded {
      throw Error.limitCheck
    } catch {
      throw Error.ioError
    }
  }

  func writeGraphicsImageRows(_ rows: GraphicsImageRows) throws {
    do {
      try graphicsEventConsumer?.writeImageRows(rows)
    } catch GraphicsStorageAccountingError.limitExceeded {
      throw Error.limitCheck
    } catch {
      throw Error.ioError
    }
  }

  func writeGraphicsImageMaskRows(_ rows: GraphicsImageMaskRows) throws {
    do {
      try graphicsEventConsumer?.writeImageMaskRows(rows)
    } catch GraphicsStorageAccountingError.limitExceeded {
      throw Error.limitCheck
    } catch {
      throw Error.ioError
    }
  }

  func endGraphicsImage() throws {
    do {
      try graphicsEventConsumer?.endImage()
    } catch GraphicsStorageAccountingError.limitExceeded {
      throw Error.limitCheck
    } catch {
      throw Error.ioError
    }
  }

  func abortGraphicsImage() {
    graphicsEventConsumer?.abortImage()
  }

  func executeImageDataSource(_ procedure: Object) async throws {
    imageDataSourceCallbackDepth += 1
    defer { imageDataSourceCallbackDepth -= 1 }
    try await execute(proc: procedure)
    guard activeImageDictionaries.allSatisfy({ $0.dictionary.revision == $0.revision }) else {
      throw Error.undefined
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
