import Foundation
import SolidRaster

extension Operators {
  static let formOps: [OperatorValue] = [ExecuteForm.instance]

  enum ExecuteForm: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["execform"]

    func execute(context: isolated Context) async throws {
      let formObject = try context.operands.pop()
      let dictionary = try formObject.value(as: DictionaryValue.self)
      try dictionary.access.check(.read)
      let definition = try formDefinition(dictionary)
      try initializeFormIfNeeded(dictionary, context: context)

      let key = formCacheKey(dictionary: dictionary, definition: definition, context: context)
      let form: GraphicsForm
      if let cached = context.environment.formCache.form(for: key) {
        form = cached
      } else {
        form = try await compileForm(
          formObject,
          dictionary: dictionary,
          definition: definition,
          context: context
        )
        context.environment.formCache.insert(
          form,
          for: key,
          maximumItemBytes: Int(context.userParameters.integer("MaxFormItem"))
        )
      }
      let state = context.graphicsState
      try context.emitGraphicsOperation(.paint(.form(form)), before: state, after: state)
    }
  }

  private static func initializeFormIfNeeded(
    _ dictionary: DictionaryValue,
    context: isolated Context
  ) throws {
    if let object = try dictionary.objectUnchecked(forKey: "Implementation"),
      let implementation = object.value as? DictionaryValue,
      context.environment.formInitializationRegistry.contains(
        form: dictionary.allocation.identity,
        implementation: implementation.allocation.identity
      )
    {
      return
    }

    let implementation = try Object.dictionary(
      uniqueKeysWithValues: EmptyCollection<(Object, Object)>(),
      access: .noAccess,
      vm: dictionary.vm,
      kind: .literal
    )
    var mutation = try dictionary.prepareInterpreterUpdateObject(implementation, forKey: "Implementation")
    let implementationBytes = context.estimatedAllocationSize(count: 0, objectType: .dictionary)
    while true {
      let combined = implementationBytes.addingReportingOverflow(mutation.allocationGrowthBytes)
      try context.preflightAllocation(
        bytes: combined.overflow ? .max : combined.partialValue,
        vm: dictionary.vm
      )
      if try dictionary.commit(mutation) { break }
      mutation = try dictionary.prepareInterpreterUpdateObject(implementation, forKey: "Implementation")
    }
    try context.adopt(implementation)
    try dictionary.setAccess(to: .readOnly)
    let implementationDictionary = try implementation.value(as: DictionaryValue.self)
    context.environment.formInitializationRegistry.register(
      form: dictionary.allocation.identity,
      implementation: implementationDictionary.allocation.identity
    )
  }

  private static func compileForm(
    _ formObject: Object,
    dictionary: DictionaryValue,
    definition: FormDefinition,
    context: isolated Context
  ) async throws -> GraphicsForm {
    guard context.encapsulatedPaintDepth < 16,
      context.activeEncapsulatedPaintAllocations.insert(dictionary.allocation.identity).inserted
    else { throw Error.limitCheck }
    context.encapsulatedPaintDepth += 1
    defer {
      context.encapsulatedPaintDepth -= 1
      context.activeEncapsulatedPaintAllocations.remove(dictionary.allocation.identity)
    }

    let callerState = context.graphicsState
    let callerStack = context.graphicsStack
    let callerConsumer = context.graphicsEventConsumer
    defer {
      context.graphicsState = callerState
      context.graphicsStack = callerStack
      context.graphicsEventConsumer = callerConsumer
    }

    let matrix = definition.matrix.concatenated(with: callerState.matrix)
    let boundsPath = try rectanglePath(
      x: definition.bounds.x,
      y: definition.bounds.y,
      width: definition.bounds.width,
      height: definition.bounds.height,
      matrix: matrix
    )
    let boundsRegion = try GraphicsPathGeometry.region(
      for: boundsPath,
      rule: .winding,
      flatness: callerState.flatness
    )
    var formState = callerState
    formState.matrix = matrix
    formState.clip = try formState.clip.appending(.init(path: boundsPath, rule: .winding))
    formState.resolvedClip = try GraphicsPathGeometry.intersect(formState.resolvedClip, boundsRegion)
    formState.clearPath()

    let collector = GraphicsDisplayListCollector()
    context.graphicsStack.append(GraphicsStackFrame(kind: .graphicsSave, state: callerState))
    context.graphicsState = formState
    context.graphicsEventConsumer = collector
    do {
      try await context.execute(proc: definition.paintProcedure, ops: [formObject])
    } catch {
      collector.abort()
      throw error
    }
    return GraphicsForm(
      bounds: definition.bounds,
      matrix: definition.matrix,
      deviceDescriptor: context.graphicsDeviceDescriptor,
      compilationState: formState.snapshot,
      displayList: GraphicsDisplayList(effects: collector.effects)
    )
  }

  private static func formCacheKey(
    dictionary: DictionaryValue,
    definition: FormDefinition,
    context: isolated Context
  ) -> FormCacheKey {
    let usesXUID = definition.xuid != nil
    let state = context.graphicsState.snapshot
    let cacheDevice = GraphicsDeviceSnapshot(
      identifier: .cacheKey,
      kind: state.device.kind,
      descriptor: state.device.descriptor,
      pageNumber: 0,
      numberOfCopies: nil
    )
    return FormCacheKey(
      identity: usesXUID ? nil : dictionary.allocation.identity,
      revision: usesXUID ? 0 : dictionary.revision,
      xuid: definition.xuid,
      bounds: definition.bounds,
      matrix: definition.matrix,
      paintProcedureIdentity: usesXUID ? nil : definition.paintProcedureIdentity,
      paintProcedureRevision: usesXUID ? 0 : definition.paintProcedureRevision,
      device: context.graphicsDeviceDescriptor,
      savedState: state.replacingDevice(cacheDevice),
      colorSelectionFingerprint: context.graphicsState.colorSelection.cacheFingerprint
    )
  }
}
