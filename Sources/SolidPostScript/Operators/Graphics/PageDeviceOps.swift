import Foundation

extension Operators {
  static let pageDeviceOps: [OperatorValue] = [
    SetPageDevice.instance,
    CurrentPageDevice.instance,
    NullDevice.instance,
  ]

  enum SetPageDevice: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setpagedevice"]

    func execute(context: isolated Context) async throws {
      guard context.encapsulatedPaintDepth == 0,
        context.imageDataSourceCallbackDepth == 0,
        context.pageDeviceCallbackStack.last == nil
          || context.pageDeviceCallbackStack.last == .policyReport
      else { throw Error.undefined }
      let requestObject = try context.operands.pop()
      let request = try requestObject.value(as: DictionaryValue.self)
      try request.access.check(.read)
      try context.ensurePageDevice()
      guard let session = context.graphicsPageDeviceSession,
        let currentConfiguration = context.graphicsState.device.configuration,
        let currentParameters = context.graphicsState.pageDeviceParameters
      else { throw Error.configurationError }

      let parsed = try parse(
        request,
        currentConfiguration: currentConfiguration,
        currentParameters: currentParameters,
        context: context
      )
      let negotiation: GraphicsPageDeviceNegotiation
      do {
        negotiation = try session.negotiate(parsed.request)
      } catch GraphicsPageDeviceError.limitExceeded {
        throw Error.limitCheck
      } catch {
        throw Error.configurationError
      }

      var recovered = parsed.recovered
      for name in negotiation.unsatisfiedParameters {
        let value = parsed.originalValues[name]
        let policy = try policy(for: name, in: parsed.parameters.policies)
        guard name == "PageSize" ? (1...7).contains(policy) : policy == 1 else {
          throw PostScriptParameterFailure(
            error: .configurationError,
            key: .literalName(name),
            value: value
          )
        }
        recovered[name] = policy
      }

      try await context.activatePageDevice(
        configuration: negotiation.configuration,
        parameters: parsed.parameters
      )
      if !recovered.isEmpty {
        try await report(recovered, policies: parsed.parameters.policies, context: context)
      }
    }
  }

  enum CurrentPageDevice: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currentpagedevice"]

    func execute(context: isolated Context) async throws {
      try context.ensurePageDevice()
      guard context.graphicsState.device.kind == .page,
        let configuration = context.graphicsState.device.configuration,
        let parameters = context.graphicsState.pageDeviceParameters
      else {
        context.operands.push(try context.makeDictionary([], access: .readOnly, vm: context.allocationMode))
        return
      }
      let vm = resultVM(parameters: parameters, preferred: context.allocationMode)
      let pageSize = try numberArray(
        [configuration.pageSize.width, configuration.pageSize.height],
        vm: vm,
        context: context
      )
      let resolution = try numberArray(
        [
          configuration.descriptor.horizontalResolution,
          configuration.descriptor.verticalResolution,
        ],
        vm: vm,
        context: context
      )
      let imagingBoundingBox: Object
      if let box = configuration.imagingBoundingBox {
        imagingBoundingBox = try numberArray(
          [box.x, box.y, box.maxX, box.maxY],
          vm: vm,
          context: context
        )
      } else {
        imagingBoundingBox = .null
      }
      let name = Object.string(configuration.name, access: .readOnly, vm: vm, kind: .literal)
      let separationNames = try nameArray(
        configuration.colorants.additionalColorants.map(\.name),
        vm: vm,
        context: context
      )
      let separationOrder = try nameArray(
        configuration.colorants.separationOrder,
        vm: vm,
        context: context
      )
      let trappingDetails = try trappingDetailsDictionary(
        configuration.trappingDetails,
        vm: vm,
        context: context
      )
      let copies: Object = if let numberOfCopies = configuration.numberOfCopies,
        let integer = Object.integer(exactly: numberOfCopies)
      {
        integer
      } else {
        .null
      }
      let dictionary = try context.makeDictionary([
        (.literalName("PageSize"), pageSize),
        (.literalName("HWResolution"), resolution),
        (.literalName("ImagingBBox"), imagingBoundingBox),
        (.literalName("NumCopies"), copies),
        (.literalName("Install"), parameters.install),
        (.literalName("BeginPage"), parameters.beginPage),
        (.literalName("EndPage"), parameters.endPage),
        (.literalName("Policies"), parameters.policies),
        (.literalName("PageDeviceName"), name),
        (.literalName("ProcessColorModel"), .literalName(configuration.colorants.processModel.rawValue)),
        (.literalName("Separations"), .boolean(configuration.colorants.producesSeparations)),
        (.literalName("MaxSeparations"), .integer(Int32(configuration.colorants.maximumSeparations))),
        (.literalName("SeparationColorNames"), separationNames),
        (.literalName("SeparationOrder"), separationOrder),
        (.literalName("Trapping"), .boolean(configuration.trappingEnabled)),
        (.literalName("TrappingDetails"), trappingDetails),
      ], access: .readOnly, vm: vm)
      context.operands.push(dictionary)
    }
  }

  enum NullDevice: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["nulldevice"]

    func execute(context: isolated Context) async throws {
      guard context.encapsulatedPaintDepth == 0,
        context.imageDataSourceCallbackDepth == 0,
        context.pageDeviceCallbackStack.isEmpty
      else { throw Error.undefined }
      try context.activateNullDevice()
    }
  }

  private struct ParsedPageDeviceRequest {
    let request: GraphicsPageDeviceRequest
    let parameters: PostScriptPageDeviceParameters
    let recovered: [String: Int32]
    let originalValues: [String: Object]
  }

  private static func parse(
    _ dictionary: DictionaryValue,
    currentConfiguration: GraphicsPageDeviceConfiguration,
    currentParameters: PostScriptPageDeviceParameters,
    context: isolated Context
  ) throws -> ParsedPageDeviceRequest {
    var entries: [String: Object] = [:]
    try dictionary.forEachUnchecked { key, value in
      let name = try PostScriptParameterFailure.wrapping(key: key, value: value) {
        try key.value(as: NameValue.self).value
      }
      entries[name] = value
    }

    let policies = try mergedPolicies(
      entries.removeValue(forKey: "Policies"),
      current: currentParameters.policies,
      context: context
    )
    var pageSize = currentConfiguration.pageSize
    var resolution = GraphicsSize(
      width: currentConfiguration.descriptor.horizontalResolution,
      height: currentConfiguration.descriptor.verticalResolution
    )
    var imagingBoundingBox = currentConfiguration.imagingBoundingBox
    var numberOfCopies = currentConfiguration.numberOfCopies
    var install = currentParameters.install
    var beginPage = currentParameters.beginPage
    var endPage = currentParameters.endPage
    var processModel = currentConfiguration.colorants.processModel
    var producesSeparations = currentConfiguration.colorants.producesSeparations
    var additionalColorants = currentConfiguration.colorants.additionalColorants
    var separationOrder = currentConfiguration.colorants.separationOrder
    var trappingEnabled = currentConfiguration.trappingEnabled
    var trappingDetails = currentConfiguration.trappingDetails
    var recovered: [String: Int32] = [:]
    let originals = entries

    for (name, value) in entries {
      do {
        switch name {
        case "PageSize":
          let values = try pageDeviceNumericArray(value, count: 2)
          guard values.allSatisfy({ $0.isFinite && $0 > 0 }) else { throw Error.rangeCheck }
          pageSize = GraphicsSize(width: values[0], height: values[1])
        case "HWResolution":
          let values = try pageDeviceNumericArray(value, count: 2)
          guard values.allSatisfy({ $0.isFinite && $0 > 0 }) else { throw Error.rangeCheck }
          resolution = GraphicsSize(width: values[0], height: values[1])
        case "ImagingBBox":
          if value.value is NullValue {
            imagingBoundingBox = nil
          } else {
            let values = try pageDeviceNumericArray(value, count: 4)
            guard values.allSatisfy(\.isFinite), values[2] >= values[0], values[3] >= values[1] else {
              throw Error.rangeCheck
            }
            imagingBoundingBox = GraphicsRect(
              x: values[0],
              y: values[1],
              width: values[2] - values[0],
              height: values[3] - values[1]
            )
          }
        case "NumCopies":
          if value.value is NullValue {
            numberOfCopies = nil
          } else {
            let integer = try value.value(as: IntegerValue.self).value
            guard integer >= 0 else { throw Error.rangeCheck }
            numberOfCopies = Int(integer)
          }
        case "Install":
          try value.checkProcedure()
          install = value
        case "BeginPage":
          try value.checkProcedure()
          beginPage = value
        case "EndPage":
          try value.checkProcedure()
          endPage = value
        case "ProcessColorModel":
          let modelName = try value.value(as: NameValue.self).value
          guard let selected = GraphicsProcessColorModel(rawValue: modelName) else {
            try recover(name: name, value: value, policies: policies, into: &recovered)
            continue
          }
          processModel = selected
        case "Separations":
          producesSeparations = try value.value(as: BooleanValue.self).value
        case "MaxSeparations":
          try recover(name: name, value: value, policies: policies, into: &recovered)
        case "SeparationColorNames":
          let names = try pageDeviceNameArray(value)
          var seen = Set<String>()
          additionalColorants = names.compactMap { colorant -> GraphicsColorant? in
            guard !processModel.colorantNames.contains(colorant), seen.insert(colorant).inserted else {
              return nil
            }
            return GraphicsColorant(name: colorant, isProcessColorant: false)
          }
        case "SeparationOrder":
          separationOrder = try pageDeviceNameArray(value)
        case "Trapping":
          trappingEnabled = try value.value(as: BooleanValue.self).value
        case "TrappingDetails":
          trappingDetails = try parseTrappingDetails(value, merging: trappingDetails)
        case "PageDeviceName":
          let requested = try value.value(as: StringValue.self).readableString
          guard requested == currentConfiguration.name else {
            try recover(name: name, value: value, policies: policies, into: &recovered)
            continue
          }
        default:
          try recover(name: name, value: value, policies: policies, into: &recovered)
        }
      } catch let failure as PostScriptParameterFailure {
        throw failure
      } catch let error as Error {
        throw PostScriptParameterFailure(error: error, key: .literalName(name), value: value)
      }
    }

    additionalColorants.removeAll { processModel.colorantNames.contains($0.name) }

    return ParsedPageDeviceRequest(
      request: GraphicsPageDeviceRequest(
        pageSize: pageSize,
        resolution: resolution,
        imagingBoundingBox: imagingBoundingBox,
        numberOfCopies: numberOfCopies,
        colorants: GraphicsColorantConfiguration(
          processModel: processModel,
          producesSeparations: producesSeparations,
          additionalColorants: additionalColorants,
          separationOrder: separationOrder,
          maximumSeparations: currentConfiguration.colorants.maximumSeparations,
          supportsOverprint: currentConfiguration.colorants.supportsOverprint,
          rgbToDeviceN: currentConfiguration.colorants.rgbToDeviceN
        ),
        trappingEnabled: trappingEnabled,
        trappingDetails: trappingDetails
      ),
      parameters: PostScriptPageDeviceParameters(
        install: install,
        beginPage: beginPage,
        endPage: endPage,
        policies: policies
      ),
      recovered: recovered,
      originalValues: originals
    )
  }

  private static func mergedPolicies(
    _ requested: Object?,
    current: Object,
    context: isolated Context
  ) throws -> Object {
    guard let requested else { return current }
    let requestedDictionary = try requested.value(as: DictionaryValue.self)
    try requestedDictionary.access.check(.read)
    let currentDictionary = try current.value(as: DictionaryValue.self)
    var entries: [(Object, Object)] = []
    try currentDictionary.forEachUnchecked { entries.append(($0, $1)) }
    var indexes: [String: Int] = [:]
    for (index, entry) in entries.enumerated() {
      indexes[try entry.0.value(as: NameValue.self).value] = index
    }
    try requestedDictionary.forEachUnchecked { key, value in
      let name = try key.value(as: NameValue.self).value
      let normalized = Object.literalName(name)
      if let index = indexes[name] {
        entries[index] = (normalized, value)
      } else {
        indexes[name] = entries.count
        entries.append((normalized, value))
      }
    }
    for (key, value) in entries {
      let name = try key.value(as: NameValue.self).value
      if name == "PolicyReport" {
        try value.checkProcedure()
      } else {
        let code = try value.value(as: IntegerValue.self).value
        guard code >= 0 else { throw Error.rangeCheck }
      }
    }
    let vm: VM = compositeVM(requested) == .local || compositeVM(current) == .local
      ? .local
      : context.allocationMode
    return try context.makeDictionary(entries, access: .readOnly, vm: vm)
  }

  private static func recover(
    name: String,
    value: Object,
    policies: Object,
    into recovered: inout [String: Int32]
  ) throws {
    let code = try policy(for: name, in: policies)
    guard code == 1 else {
      throw PostScriptParameterFailure(
        error: .configurationError,
        key: .literalName(name),
        value: value
      )
    }
    recovered[name] = code
  }

  private static func policy(for name: String, in policies: Object) throws -> Int32 {
    let dictionary = try policies.value(as: DictionaryValue.self)
    let value = try dictionary.object(forKeyIfExists: .literalName(name))
      ?? dictionary.object(forKey: .literalName("PolicyNotFound"))
    return try value.value(as: IntegerValue.self).value
  }

  private static func report(
    _ recovered: [String: Int32],
    policies: Object,
    context: isolated Context
  ) async throws {
    let dictionary = try policies.value(as: DictionaryValue.self)
    let procedure = try dictionary.object(forKey: .literalName("PolicyReport"))
    let report = try context.makeDictionary(
      recovered.map { (.literalName($0.key), .integer($0.value)) },
      access: .unlimited,
      vm: context.allocationMode
    )
    try await context.executePageDeviceProcedure(
      procedure,
      callback: .policyReport,
      operands: [report]
    )
  }

  private static func pageDeviceNumericArray(_ object: Object, count: Int) throws -> [Double] {
    let values: [Object]
    if let array = object.value as? ArrayValue {
      values = Array(try array.objects(in: array.range, for: .read))
    } else if let array = object.value as? PackedArrayValue {
      values = Array(try array.objects(in: array.range, for: .read))
    } else {
      throw Error.typeCheck
    }
    guard values.count == count else { throw Error.rangeCheck }
    return try values.map(numeric)
  }

  private static func pageDeviceNameArray(_ object: Object) throws -> [String] {
    let values: [Object]
    if let array = object.value as? ArrayValue {
      values = Array(try array.objects(in: array.range, for: .read))
    } else if let array = object.value as? PackedArrayValue {
      values = Array(try array.objects(in: array.range, for: .read))
    } else {
      throw Error.typeCheck
    }
    return try values.map { value in
      if let name = value.value as? NameValue { return name.value }
      if let string = value.value as? StringValue { return try string.readableString }
      throw Error.typeCheck
    }
  }

  private static func numberArray(
    _ values: [Double],
    vm: VM,
    context: isolated Context
  ) throws -> Object {
    try context.preflightAllocation(
      bytes: context.estimatedAllocationSize(count: values.count, objectType: .array),
      vm: vm
    )
    let array = try Object.array(
      values.map { try Object.real($0) },
      access: .readOnly,
      vm: vm,
      kind: .literal
    )
    try context.adopt(array)
    return array
  }

  private static func nameArray(
    _ values: [String],
    vm: VM,
    context: isolated Context
  ) throws -> Object {
    try context.preflightAllocation(
      bytes: context.estimatedAllocationSize(count: values.count, objectType: .array),
      vm: vm
    )
    let array = try Object.array(
      values.map(Object.literalName),
      access: .readOnly,
      vm: vm,
      kind: .literal
    )
    try context.adopt(array)
    return array
  }

  private static func parseTrappingDetails(
    _ object: Object,
    merging current: GraphicsTrappingDetails
  ) throws -> GraphicsTrappingDetails {
    let dictionary = try object.value(as: DictionaryValue.self)
    try dictionary.access.check(.read)
    var type = current.type
    var order = current.trappingOrder
    var details = current.colorantDetails
    if let value = try dictionary.object(forKeyIfExists: .literalName("Type")) {
      type = Int(try value.value(as: IntegerValue.self).value)
    }
    if let value = try dictionary.object(forKeyIfExists: .literalName("TrappingOrder")) {
      order = try pageDeviceNameArray(value)
    }
    if let value = try dictionary.object(forKeyIfExists: .literalName("ColorantDetails")) {
      let colorants = try value.value(as: DictionaryValue.self)
      try colorants.access.check(.read)
      try colorants.forEachUnchecked { key, value in
        let name = try key.value(as: NameValue.self).value
        let colorant = try value.value(as: DictionaryValue.self)
        try colorant.access.check(.read)
        let previous = details[name]
        let reportedName = try colorant.object(forKeyIfExists: .literalName("ColorantName"))
          .map { try $0.value(as: NameValue.self).value } ?? previous?.colorantName ?? name
        let kind = try colorant.object(forKeyIfExists: .literalName("ColorantType"))
          .map { try $0.value(as: NameValue.self).value }
          .flatMap(GraphicsTrappingColorantType.init(rawValue:)) ?? previous?.colorantType ?? .normal
        let density = try colorant.object(forKeyIfExists: .literalName("NeutralDensity"))
          .map(trappingNumber) ?? previous?.neutralDensity ?? 1
        guard (0.001...10).contains(density) else { throw Error.rangeCheck }
        details[name] = GraphicsColorantTrappingProperties(
          colorantName: reportedName,
          colorantType: kind,
          neutralDensity: density
        )
      }
    }
    return GraphicsTrappingDetails(type: type, trappingOrder: order, colorantDetails: details)
  }

  private static func trappingDetailsDictionary(
    _ details: GraphicsTrappingDetails,
    vm: VM,
    context: isolated Context
  ) throws -> Object {
    let order = try nameArray(details.trappingOrder, vm: vm, context: context)
    let colorantEntries = try details.colorantDetails.sorted { $0.key < $1.key }.map { name, properties in
      let value = try context.makeDictionary([
        (.literalName("ColorantName"), .literalName(properties.colorantName)),
        (.literalName("ColorantType"), .literalName(properties.colorantType.rawValue)),
        (.literalName("NeutralDensity"), try Object.real(properties.neutralDensity)),
      ], access: .readOnly, vm: vm)
      return (Object.literalName(name), value)
    }
    let colorants = try context.makeDictionary(colorantEntries, access: .readOnly, vm: vm)
    return try context.makeDictionary([
      (.literalName("Type"), .integer(Int32(clamping: details.type))),
      (.literalName("TrappingOrder"), order),
      (.literalName("ColorantDetails"), colorants),
    ], access: .readOnly, vm: vm)
  }

  private static func resultVM(
    parameters: PostScriptPageDeviceParameters,
    preferred: VM
  ) -> VM {
    [parameters.install, parameters.beginPage, parameters.endPage, parameters.policies]
      .contains { compositeVM($0) == .local } ? .local : preferred
  }

  private static func compositeVM(_ object: Object) -> VM? {
    (object.value as? any CompositeValue)?.vm
  }
}
