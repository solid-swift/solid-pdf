import Foundation

extension Context {
  enum PageDeviceCallback {
    case install
    case beginPage
    case endPage
    case policyReport
  }

  func ensurePageDevice() throws {
    if graphicsPageDeviceSession == nil {
      graphicsPageDeviceSession = try StandardGraphicsPageDeviceProvider(mode: .adaptive)
        .makeSession(for: graphicsDeviceDescriptor)
    }
    guard graphicsState.pageDeviceParameters == nil else { return }
    graphicsState.pageDeviceParameters = try makeDefaultPageDeviceParameters()
  }

  func makeDefaultPageDeviceParameters() throws -> PostScriptPageDeviceParameters {
    let vm = VM.global
    let install = try makeProcedure([], vm: vm)
    let beginPage = try makeProcedure([.executableName("pop")], vm: vm)
    let endPage = try makeProcedure([
      .executableName("exch"),
      .executableName("pop"),
      .integer(2),
      .executableName("ne"),
    ], vm: vm)
    let policyReport = try makeProcedure([.executableName("pop")], vm: vm)
    let policies = try makeDictionary([
      (.literalName("PolicyNotFound"), .integer(1)),
      (.literalName("PageSize"), .integer(0)),
      (.literalName("PolicyReport"), policyReport),
    ], access: .readOnly, vm: vm)
    return PostScriptPageDeviceParameters(
      install: install,
      beginPage: beginPage,
      endPage: endPage,
      policies: policies
    )
  }

  func makeProcedure(_ objects: [Object], vm: VM) throws -> Object {
    try preflightAllocation(bytes: estimatedAllocationSize(count: objects.count, objectType: .array), vm: vm)
    let procedure = try Object.array(objects, access: .unlimited, vm: vm, kind: .executable)
    try adopt(procedure)
    return procedure
  }

  func makeDictionary(
    _ entries: [(Object, Object)],
    access: ObjectAccess,
    vm: VM
  ) throws -> Object {
    try limitCheck(size: entries.count, objectType: .dictionary)
    try preflightAllocation(bytes: estimatedAllocationSize(count: entries.count, objectType: .dictionary), vm: vm)
    let dictionary = try Object.dictionary(
      uniqueKeysWithValues: entries,
      access: access,
      vm: vm,
      kind: .literal
    )
    try adopt(dictionary)
    return dictionary
  }

  func executePageDeviceProcedure(
    _ procedure: Object,
    callback: PageDeviceCallback,
    operands callbackOperands: [Object]
  ) async throws {
    pageDeviceCallbackStack.append(callback)
    let operandLimit = operands.reserveAdditionalDepth(callbackOperands.count)
    defer {
      operands.setMaximumDepth(operandLimit)
      _ = pageDeviceCallbackStack.popLast()
    }
    try await execute(proc: procedure, ops: callbackOperands)
  }

  func callEndPage(reason: Int32) async throws -> Bool {
    try ensurePageDevice()
    guard graphicsState.device.kind == .page,
      let parameters = graphicsState.pageDeviceParameters
    else { return false }
    try await executePageDeviceProcedure(
      parameters.endPage,
      callback: .endPage,
      operands: [.integer(reason), try pageNumberObject()]
    )
    return try operands.popAs(BooleanValue.self).value
  }

  func callBeginPage() async throws {
    try ensurePageDevice()
    guard graphicsState.device.kind == .page,
      let parameters = graphicsState.pageDeviceParameters
    else { return }
    try await executePageDeviceProcedure(
      parameters.beginPage,
      callback: .beginPage,
      operands: [try pageNumberObject()]
    )
  }

  func activatePageDevice(
    configuration: GraphicsPageDeviceConfiguration,
    parameters: PostScriptPageDeviceParameters
  ) async throws {
    let oldState = graphicsState
    if oldState.device.kind == .page {
      let transmit = try await callEndPage(reason: 2)
      if transmit {
        try transmitCurrentPage(.show)
      }
      oldState.device.discardPageTrappingZones()
      do {
        try graphicsEventConsumer?.deactivateDevice(oldState.device.snapshot)
      } catch {
        throw Error.ioError
      }
    }

    let record = PostScriptDeviceRecord(configuration: configuration)
    graphicsDeviceDescriptor = configuration.descriptor
    graphicsState = .initial(for: configuration.descriptor, device: record)
    selectInitialColor(for: configuration.colorants)
    graphicsState.pageDeviceParameters = parameters
    graphicsStack.removeAll()
    do {
      try graphicsEventConsumer?.activateDevice(record.snapshot)
    } catch {
      throw Error.ioError
    }
    try await executePageDeviceProcedure(parameters.install, callback: .install, operands: [])
    record.captureDefaultTrappingZones()
    try applyInstalledDefaultMatrix()
    try applyGraphicsOperation(.paint(.erasePage)) { _ in }
    graphicsState.initializeGraphics(for: graphicsDeviceDescriptor)
    selectInitialColor(for: configuration.colorants)
    try installCurrentOutputDeviceResource()
    try await callBeginPage()
  }

  func activateNullDevice() throws {
    guard graphicsState.device.kind != .null else { return }
    let record = PostScriptDeviceRecord.null()
    graphicsDeviceDescriptor = record.descriptor
    graphicsState = .initial(for: record.descriptor, device: record)
    graphicsState.matrix = .identity
    do {
      try graphicsEventConsumer?.activateDevice(record.snapshot)
    } catch {
      throw Error.ioError
    }
  }

  func transmitCurrentPage(_ operation: GraphicsOperation.Page) throws {
    let state = graphicsState
    let event = GraphicsEvent(operation: .page(operation), before: state.snapshot, after: state.snapshot)
    do {
      try graphicsEventConsumer?.transmitPage(event, copies: effectiveCopyCount())
    } catch let error as Error {
      throw error
    } catch {
      throw Error.ioError
    }
  }

  func showCurrentPage() async throws {
    guard graphicsState.device.kind == .page else { return }
    let transmit = try await callEndPage(reason: 0)
    if transmit { try transmitCurrentPage(.show) }
    graphicsState.device.incrementPageNumber()
    graphicsState.device.restoreDefaultTrappingZones()
    graphicsState.initializeGraphics(for: graphicsDeviceDescriptor)
    try await callBeginPage()
  }

  func copyCurrentPage() async throws {
    guard graphicsState.device.kind == .page else { return }
    let transmit = try await callEndPage(reason: 0)
    if transmit { try transmitCurrentPage(.copy) }
    graphicsState.device.restoreDefaultTrappingZones()
    try await callBeginPage()
  }

  func finishCurrentPageDevice() async throws {
    guard graphicsState.device.kind == .page else { return }
    if try await callEndPage(reason: 2) {
      try transmitCurrentPage(.show)
    }
    graphicsState.device.discardPageTrappingZones()
    do {
      try graphicsEventConsumer?.deactivateDevice(graphicsState.device.snapshot)
    } catch {
      throw Error.ioError
    }
  }

  func transitionGraphicsState(to state: GraphicsCanonicalState) async throws {
    let current = graphicsState
    if current.device.identifier == state.device.identifier {
      graphicsState = state
      graphicsDeviceDescriptor = state.device.descriptor
      return
    }

    if current.device.kind == .null || state.device.kind == .null {
      graphicsState = state
      graphicsDeviceDescriptor = state.device.descriptor
      do {
        try graphicsEventConsumer?.activateDevice(state.device.snapshot)
      } catch {
        throw Error.ioError
      }
      return
    }

    if try await callEndPage(reason: 2) { try transmitCurrentPage(.show) }
    do {
      try graphicsEventConsumer?.deactivateDevice(current.device.snapshot)
    } catch {
      throw Error.ioError
    }
    graphicsState = state
    graphicsDeviceDescriptor = state.device.descriptor
    do {
      try graphicsEventConsumer?.activateDevice(state.device.snapshot)
    } catch {
      throw Error.ioError
    }
    try await callBeginPage()
  }

  func effectiveCopyCount() throws -> Int {
    let count: Int
    if let copies = graphicsState.device.configuration?.numberOfCopies {
      count = copies
    } else {
      let object = try dictionaries.object(forKey: .literalName("#copies"))
      let value = try object.value(as: IntegerValue.self).value
      guard value >= 0 else { throw Error.rangeCheck }
      count = Int(value)
    }
    guard count <= LanguageLimits.maximumPageCopies else { throw Error.limitCheck }
    return count
  }

  private func pageNumberObject() throws -> Object {
    guard let value = Int32(exactly: graphicsState.device.pageNumber) else { throw Error.limitCheck }
    return .integer(value)
  }

  private func applyInstalledDefaultMatrix() throws {
    guard let configuration = graphicsState.device.configuration else { return }
    let installedMatrix = graphicsState.matrix
    let descriptor = configuration.descriptor.replacing(defaultMatrix: installedMatrix)
    let installed = configuration.replacing(descriptor: descriptor)
    graphicsState.device.updateConfiguration(installed)
    graphicsDeviceDescriptor = descriptor
  }

  private func selectInitialColor(for colorants: GraphicsColorantConfiguration) {
    switch colorants.processModel {
    case .deviceGray:
      graphicsState.colorSelection = .direct(.deviceGray(nil))
      graphicsState.colorComponents = [0]
      graphicsState.paint = .deviceGray(0)
    case .deviceRGB, .deviceRGBK:
      graphicsState.colorSelection = .direct(.deviceRGB(nil))
      graphicsState.colorComponents = [0, 0, 0]
      graphicsState.paint = .deviceRGB(red: 0, green: 0, blue: 0)
    case .deviceCMY, .deviceCMYK:
      graphicsState.colorSelection = .direct(.deviceCMYK(nil))
      graphicsState.colorComponents = [0, 0, 0, 1]
      graphicsState.paint = .deviceCMYK(cyan: 0, magenta: 0, yellow: 0, black: 1)
    case .deviceN:
      graphicsState.colorSelection = .direct(.deviceGray(nil))
      graphicsState.colorComponents = [0]
      graphicsState.paint = .deviceGray(0)
    }
    graphicsState.patternSource = nil
  }
}

extension GraphicsDeviceDescriptor {
  func replacing(defaultMatrix: GraphicsMatrix) -> Self {
    Self(
      mediaBounds: mediaBounds,
      imageableBounds: imageableBounds,
      horizontalResolution: horizontalResolution,
      verticalResolution: verticalResolution,
      defaultMatrix: defaultMatrix,
      defaultFlatness: defaultFlatness,
      defaultStrokeAdjustment: defaultStrokeAdjustment,
      minimumSmoothness: minimumSmoothness,
      maximumSmoothness: maximumSmoothness,
      defaultSmoothness: defaultSmoothness,
      colorDevice: colorDevice,
      deviceRendering: deviceRendering,
      colorants: colorants,
      trapping: trapping
    )
  }
}

extension GraphicsPageDeviceConfiguration {
  func replacing(descriptor: GraphicsDeviceDescriptor) -> Self {
    Self(
      identifier: identifier,
      pageSize: pageSize,
      imagingBoundingBox: imagingBoundingBox,
      numberOfCopies: numberOfCopies,
      name: name,
      descriptor: descriptor,
      colorants: colorants,
      trappingEnabled: trappingEnabled,
      trappingDetails: trappingDetails
    )
  }
}
