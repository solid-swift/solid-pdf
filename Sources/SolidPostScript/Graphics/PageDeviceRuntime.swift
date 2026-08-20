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
    let initialColor = try await initialColor(for: configuration)
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
    apply(initialColor, to: &graphicsState)
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
    try await initializeGraphicsState(emitOperation: false)
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
    try await initializeGraphicsState(emitOperation: false)
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

  func initializeGraphicsState(emitOperation: Bool) async throws {
    let initial = try await initialColor()
    if emitOperation {
      try applyGraphicsOperation(.state(.initialize)) {
        $0.initializeGraphics(for: graphicsDeviceDescriptor)
        apply(initial, to: &$0)
      }
    } else {
      graphicsState.initializeGraphics(for: graphicsDeviceDescriptor)
      apply(initial, to: &graphicsState)
    }
  }

  private struct InitialColor {
    let selection: PostScriptColorSelection
    let components: [Double]
    let paint: GraphicsPaint
  }

  private func initialColor() async throws -> InitialColor {
    let configuration = graphicsState.device.configuration
    return try await initialColor(
      colorants: configuration?.colorants ?? graphicsDeviceDescriptor.colorants,
      usesCIEColor: configuration?.usesCIEColor ?? false
    )
  }

  private func initialColor(for configuration: GraphicsPageDeviceConfiguration) async throws -> InitialColor {
    try await initialColor(
      colorants: configuration.colorants,
      usesCIEColor: configuration.usesCIEColor
    )
  }

  private func initialColor(
    colorants: GraphicsColorantConfiguration,
    usesCIEColor: Bool
  ) async throws -> InitialColor {
    let source: PostScriptColorSpace = switch colorants.processModel {
    case .deviceGray:
      .deviceGray(nil)
    case .deviceRGB, .deviceRGBK:
      .deviceRGB(nil)
    case .deviceCMY, .deviceCMYK:
      .deviceCMYK(nil)
    case .deviceN:
      .deviceGray(nil)
    }
    let selection = try await Operators.selectColorSpace(
      source,
      usesCIEColor: usesCIEColor,
      availableColorants: Set(colorants.availableColorants.map(\.name)),
      context: self
    )
    let components = source.initialComponents
    let paint = try await Operators.resolveColor(components, in: selection, context: self)
    return InitialColor(selection: selection, components: components, paint: Operators.graphicsPaint(paint))
  }

  private func apply(_ initial: InitialColor, to state: inout GraphicsCanonicalState) {
    state.colorSelection = initial.selection
    state.colorComponents = initial.components
    state.paint = initial.paint
    state.patternSource = nil
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
      trappingDetails: trappingDetails,
      usesCIEColor: usesCIEColor
    )
  }
}
