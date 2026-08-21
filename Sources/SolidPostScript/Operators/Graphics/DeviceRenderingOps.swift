import Foundation

extension Operators {
  static let deviceRenderingOps: [OperatorValue] = [
    SetTransfer.instance,
    CurrentTransfer.instance,
    SetColorTransfer.instance,
    CurrentColorTransfer.instance,
    SetBlackGeneration.instance,
    CurrentBlackGeneration.instance,
    SetUndercolorRemoval.instance,
    CurrentUndercolorRemoval.instance,
  ]

  enum SetTransfer: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["settransfer"]

    func execute(context: isolated Context) async throws {
      try requireDeviceRenderingOperationAllowed(context)
      let procedure = try context.operands.pop()
      try procedure.checkProcedure()
      let function = try await compileComponentFunction(procedure, context: context)
      try context.applyGraphicsOperation(.state(.setTransferFunctions)) {
        $0.transferFunctionSources = [procedure, procedure, procedure, procedure]
        $0.deviceRendering = GraphicsDeviceRenderingSnapshot(
          transferFunctions: GraphicsTransferFunctions(
            red: function,
            green: function,
            blue: function,
            gray: function
          ),
          blackGeneration: $0.deviceRendering.blackGeneration,
          undercolorRemoval: $0.deviceRendering.undercolorRemoval,
          halftone: $0.deviceRendering.halftone
        )
      }
    }
  }

  enum CurrentTransfer: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currenttransfer"]

    func execute(context: isolated Context) async throws {
      context.operands.push(
        try context.graphicsState.transferFunctionSources[3] ?? identityProcedure(context: context)
      )
    }
  }

  enum SetColorTransfer: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setcolortransfer"]

    func execute(context: isolated Context) async throws {
      try requireDeviceRenderingOperationAllowed(context)
      let popped = try context.operands.pop(count: 4)
      let procedures = [popped[3], popped[2], popped[1], popped[0]]
      try procedures.forEach { try $0.checkProcedure() }
      var functions: [GraphicsComponentFunction] = []
      functions.reserveCapacity(4)
      for procedure in procedures {
        functions.append(try await compileComponentFunction(procedure, context: context))
      }
      try context.applyGraphicsOperation(.state(.setTransferFunctions)) {
        $0.transferFunctionSources = procedures
        $0.deviceRendering = GraphicsDeviceRenderingSnapshot(
          transferFunctions: GraphicsTransferFunctions(
            red: functions[0],
            green: functions[1],
            blue: functions[2],
            gray: functions[3]
          ),
          blackGeneration: $0.deviceRendering.blackGeneration,
          undercolorRemoval: $0.deviceRendering.undercolorRemoval,
          halftone: $0.deviceRendering.halftone
        )
      }
    }
  }

  enum CurrentColorTransfer: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currentcolortransfer"]

    func execute(context: isolated Context) async throws {
      var procedures: [Object] = []
      procedures.reserveCapacity(4)
      for source in context.graphicsState.transferFunctionSources {
        procedures.append(try source ?? identityProcedure(context: context))
      }
      context.operands.push(contentsOf: procedures.reversed())
    }
  }

  enum SetBlackGeneration: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setblackgeneration"]

    func execute(context: isolated Context) async throws {
      try requireDeviceRenderingOperationAllowed(context)
      let procedure = try context.operands.pop()
      try procedure.checkProcedure()
      let function = try await compileComponentFunction(procedure, context: context)
      try context.applyGraphicsOperation(.state(.setBlackGeneration)) {
        $0.blackGenerationSource = procedure
        $0.deviceRendering = GraphicsDeviceRenderingSnapshot(
          transferFunctions: $0.deviceRendering.transferFunctions,
          blackGeneration: function,
          undercolorRemoval: $0.deviceRendering.undercolorRemoval,
          halftone: $0.deviceRendering.halftone
        )
      }
    }
  }

  enum CurrentBlackGeneration: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currentblackgeneration"]

    func execute(context: isolated Context) async throws {
      context.operands.push(
        try context.graphicsState.blackGenerationSource ?? zeroProcedure(context: context)
      )
    }
  }

  enum SetUndercolorRemoval: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setundercolorremoval"]

    func execute(context: isolated Context) async throws {
      try requireDeviceRenderingOperationAllowed(context)
      let procedure = try context.operands.pop()
      try procedure.checkProcedure()
      let function = try await compileComponentFunction(procedure, context: context)
      try context.applyGraphicsOperation(.state(.setUndercolorRemoval)) {
        $0.undercolorRemovalSource = procedure
        $0.deviceRendering = GraphicsDeviceRenderingSnapshot(
          transferFunctions: $0.deviceRendering.transferFunctions,
          blackGeneration: $0.deviceRendering.blackGeneration,
          undercolorRemoval: function,
          halftone: $0.deviceRendering.halftone
        )
      }
    }
  }

  enum CurrentUndercolorRemoval: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currentundercolorremoval"]

    func execute(context: isolated Context) async throws {
      context.operands.push(
        try context.graphicsState.undercolorRemovalSource ?? zeroProcedure(context: context)
      )
    }
  }

  static func compileComponentFunction(
    _ procedure: Object,
    context: isolated Context
  ) async throws -> GraphicsComponentFunction {
    let precision = context.graphicsDeviceDescriptor.deviceRendering.samplePrecision
    let maximum = 1 << precision
    var samples: [Double] = []
    samples.reserveCapacity(maximum + 1)
    for index in 0...maximum {
      let input = Double(index) / Double(maximum)
      let depth = context.operands.depth
      try await context.execute(proc: procedure, ops: [try .real(input)])
      guard context.operands.depth == depth + 1 else { throw Error.typeCheck }
      let output = try numeric(context.operands.pop())
      guard output.isFinite else { throw Error.undefinedResult }
      samples.append(output)
    }
    return try GraphicsComponentFunction(samples: samples)
  }

  static func requireDeviceRenderingOperationAllowed(_ context: isolated Context) throws {
    guard context.uncoloredPatternExecutionDepth == 0,
      context.activeImageDictionaries.isEmpty
    else { throw Error.undefined }
  }

  static func identityProcedure(context: isolated Context) throws -> Object {
    try emptyProcedure(context: context)
  }

  static func zeroProcedure(context: isolated Context) throws -> Object {
    let procedure = try Object.array(
      [.executableName("pop"), .integer(0)],
      access: .readOnly,
      vm: context.allocationMode,
      kind: .executable
    )
    try context.preflightAllocation(bytes: context.estimatedAllocationSize(count: 2, objectType: .array))
    try context.adopt(procedure)
    return procedure
  }

  private static func emptyProcedure(context: isolated Context) throws -> Object {
    let procedure = try Object.array(
      [],
      access: .readOnly,
      vm: context.allocationMode,
      kind: .executable
    )
    try context.preflightAllocation(bytes: context.estimatedAllocationSize(count: 0, objectType: .array))
    try context.adopt(procedure)
    return procedure
  }
}
