import Foundation

extension Context {
  enum PageDeviceCallback {
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
    defer { _ = pageDeviceCallbackStack.popLast() }
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
      operands: [try pageNumberObject(), .integer(reason)]
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
        let event = GraphicsEvent(
          operation: .page(.show),
          before: graphicsState.snapshot,
          after: graphicsState.snapshot
        )
        try graphicsEventConsumer?.transmitPage(event, copies: effectiveCopyCount())
      }
      try graphicsEventConsumer?.deactivateDevice(oldState.device.snapshot)
    }

    let record = PostScriptDeviceRecord(configuration: configuration)
    graphicsDeviceDescriptor = configuration.descriptor
    graphicsState = .initial(for: configuration.descriptor, device: record)
    graphicsState.pageDeviceParameters = parameters
    graphicsStack.removeAll()
    do {
      try graphicsEventConsumer?.activateDevice(record.snapshot)
    } catch {
      throw Error.ioError
    }
    try await executePageDeviceProcedure(parameters.install, callback: .beginPage, operands: [])
    try applyInstalledDefaultMatrix()
    try applyGraphicsOperation(.paint(.erasePage)) { _ in }
    graphicsState.initializeGraphics(for: graphicsDeviceDescriptor)
    try await callBeginPage()
  }

  func activateNullDevice() throws {
    guard graphicsState.device.kind != .null else { return }
    suspendedPageStates.append(graphicsState)
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

  func effectiveCopyCount() throws -> Int {
    if let copies = graphicsState.device.configuration?.numberOfCopies { return copies }
    let object = try dictionaries.object(forKey: .literalName("#copies"))
    let count = try object.value(as: IntegerValue.self).value
    guard count >= 0 else { throw Error.rangeCheck }
    return Int(count)
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
      colorDevice: colorDevice
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
      descriptor: descriptor
    )
  }
}
