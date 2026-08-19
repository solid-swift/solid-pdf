import Foundation

extension Operators {
  static let trappingOps: [OperatorValue] = [
    SetTrapParameters.instance,
    CurrentTrapParameters.instance,
    SetTrapZone.instance,
  ]

  enum SetTrapParameters: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".settrapparams"]

    func execute(context: isolated Context) async throws {
      try context.requireTrappingSupport()
      try context.requireUnencapsulatedTrappingOperation()
      let source = try context.operands.pop()
      let dictionary = try source.value(as: DictionaryValue.self)
      try validateTrapParameterDictionary(dictionary)
      let current = context.graphicsState.device.trapping
      let parsed = try parseTrapParameters(
        dictionary,
        merging: current.parameters,
        trapSetNameSource: context.graphicsState.device.trapSetNameSource
      )
      try context.updateTrapping(
        GraphicsTrappingSnapshot(
          enabled: current.enabled,
          details: current.details,
          parameters: parsed.parameters,
          zones: current.zones
        ),
        trapSetNameSource: parsed.trapSetNameSource,
        operation: .state(.setTrappingParameters(parsed.parameters))
      )
    }
  }

  enum CurrentTrapParameters: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".currenttrapparams"]

    func execute(context: isolated Context) async throws {
      try context.requireTrappingSupport()
      let snapshot = context.graphicsState.device.trapping
      let dictionary = try trapParameterDictionary(
        snapshot.parameters,
        trapSetNameSource: context.graphicsState.device.trapSetNameSource,
        context: context
      )
      context.operands.push(dictionary)
    }
  }

  enum SetTrapZone: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = [".settrapzone"]

    func execute(context: isolated Context) async throws {
      try context.requireTrappingSupport()
      try context.requireUnencapsulatedTrappingOperation()
      let current = context.graphicsState.device.trapping
      let maximumZones = context.graphicsDeviceDescriptor.trapping.capabilities.maximumZones
      guard current.zones.count < maximumZones else { throw Error.limitCheck }
      let region = try GraphicsPathGeometry.region(
        for: context.graphicsState.path,
        rule: .winding,
        flatness: context.graphicsState.flatness
      )
      let path = try GraphicsPathGeometry.clippingPath(region)
      let zone = GraphicsTrappingZone(
        path: path,
        parameters: current.parameters,
        sequence: current.zones.count
      )
      try context.updateTrapping(
        GraphicsTrappingSnapshot(
          enabled: current.enabled,
          details: current.details,
          parameters: current.parameters,
          zones: current.zones + [zone]
        ),
        trapSetNameSource: context.graphicsState.device.trapSetNameSource,
        operation: .state(.setTrappingZone(zone))
      )
      context.graphicsState.clearPath()
    }
  }

  private static func parseTrapParameters(
    _ dictionary: DictionaryValue,
    merging current: GraphicsTrappingParameters,
    trapSetNameSource currentSource: Object?
  ) throws -> (parameters: GraphicsTrappingParameters, trapSetNameSource: Object?) {
    var trapSetName = current.trapSetName
    var trapSetNameSource = currentSource
    var enabled = current.enabled
    var stepLimit = current.stepLimit
    var trapWidth = current.trapWidth
    var trapColorScaling = current.trapColorScaling
    var blackDensityLimit = current.blackDensityLimit
    var blackColorLimit = current.blackColorLimit
    var blackWidth = current.blackWidth
    var slidingTrapLimit = current.slidingTrapLimit
    var imageToObjectTrapping = current.imageToObjectTrapping
    var imageInternalTrapping = current.imageInternalTrapping
    var imageTrapPlacement = current.imageTrapPlacement
    var imageResolution = current.imageResolution
    var colorantZoneDetails = current.colorantZoneDetails

    try dictionary.forEachUnchecked { key, value in
      switch try key.value(as: NameValue.self).value {
      case "TrapSetName":
        let string = try value.value(as: StringValue.self)
        trapSetName = try string.readableString
        trapSetNameSource = value
      case "Enabled": enabled = try value.value(as: BooleanValue.self).value
      case "StepLimit": stepLimit = try trappingNumber(value)
      case "TrapWidth": trapWidth = min(10, try trappingNumber(value))
      case "TrapColorScaling": trapColorScaling = try trappingNumber(value)
      case "BlackDensityLimit": blackDensityLimit = try trappingNumber(value)
      case "BlackColorLimit": blackColorLimit = try trappingNumber(value)
      case "BlackWidth": blackWidth = try trappingNumber(value)
      case "SlidingTrapLimit": slidingTrapLimit = try trappingNumber(value)
      case "ImageToObjectTrapping":
        imageToObjectTrapping = try value.value(as: BooleanValue.self).value
      case "ImageInternalTrapping":
        imageInternalTrapping = try value.value(as: BooleanValue.self).value
      case "ImageTrapPlacement":
        let name = try value.value(as: NameValue.self).value
        guard let placement = GraphicsImageTrapPlacement(rawValue: name) else { throw Error.rangeCheck }
        imageTrapPlacement = placement
      case "ImageResolution": imageResolution = try trappingNumber(value)
      case "ColorantZoneDetails": colorantZoneDetails = try parseColorantZoneDetails(value)
      default: break
      }
    }
    return (
      GraphicsTrappingParameters(
        trapSetName: trapSetName,
        enabled: enabled,
        stepLimit: stepLimit,
        trapWidth: trapWidth,
        trapColorScaling: trapColorScaling,
        blackDensityLimit: blackDensityLimit,
        blackColorLimit: blackColorLimit,
        blackWidth: blackWidth,
        slidingTrapLimit: slidingTrapLimit,
        imageToObjectTrapping: imageToObjectTrapping,
        imageInternalTrapping: imageInternalTrapping,
        imageTrapPlacement: imageTrapPlacement,
        imageResolution: imageResolution,
        colorantZoneDetails: colorantZoneDetails
      ),
      trapSetNameSource
    )
  }

  private static func parseColorantZoneDetails(
    _ object: Object
  ) throws -> [String: GraphicsTrappingColorantZoneParameters] {
    let dictionary = try object.value(as: DictionaryValue.self)
    var result: [String: GraphicsTrappingColorantZoneParameters] = [:]
    try dictionary.forEachUnchecked { key, value in
      let name = try key.value(as: NameValue.self).value
      let parameters = try value.value(as: DictionaryValue.self)
      let step = try parameters.object(forKeyIfExists: .literalName("StepLimit")).map(trappingNumber)
      let scale = try parameters.object(forKeyIfExists: .literalName("TrapColorScaling")).map(trappingNumber)
      result[name] = GraphicsTrappingColorantZoneParameters(
        stepLimit: step,
        trapColorScaling: scale
      )
    }
    return result
  }

  private static func trapParameterDictionary(
    _ parameters: GraphicsTrappingParameters,
    trapSetNameSource: Object?,
    context: isolated Context
  ) throws -> Object {
    let vm = context.allocationMode
    let colorants = try parameters.colorantZoneDetails.sorted { $0.key < $1.key }.map { name, values in
      var entries: [(Object, Object)] = []
      if let stepLimit = values.stepLimit {
        entries.append((.literalName("StepLimit"), try Object.real(stepLimit)))
      }
      if let scaling = values.trapColorScaling {
        entries.append((.literalName("TrapColorScaling"), try Object.real(scaling)))
      }
      return (Object.literalName(name), try context.makeDictionary(entries, access: .unlimited, vm: vm))
    }
    let colorantDetails = try context.makeDictionary(colorants, access: .unlimited, vm: vm)
    var entries: [(Object, Object)] = [
      (.literalName("Enabled"), .boolean(parameters.enabled)),
      (.literalName("StepLimit"), try Object.real(parameters.stepLimit)),
      (.literalName("TrapWidth"), try Object.real(parameters.trapWidth)),
      (.literalName("TrapColorScaling"), try Object.real(parameters.trapColorScaling)),
      (.literalName("BlackDensityLimit"), try Object.real(parameters.blackDensityLimit)),
      (.literalName("BlackColorLimit"), try Object.real(parameters.blackColorLimit)),
      (.literalName("BlackWidth"), try Object.real(parameters.blackWidth)),
      (.literalName("SlidingTrapLimit"), try Object.real(parameters.slidingTrapLimit)),
      (.literalName("ImageToObjectTrapping"), .boolean(parameters.imageToObjectTrapping)),
      (.literalName("ImageInternalTrapping"), .boolean(parameters.imageInternalTrapping)),
      (.literalName("ImageTrapPlacement"), .literalName(parameters.imageTrapPlacement.rawValue)),
      (.literalName("ImageResolution"), try Object.real(parameters.imageResolution)),
      (.literalName("ColorantZoneDetails"), colorantDetails),
    ]
    if let trapSetNameSource {
      entries.append((.literalName("TrapSetName"), trapSetNameSource))
    }
    return try context.makeDictionary(entries, access: .unlimited, vm: vm)
  }
}

extension Context {
  func requireTrappingSupport() throws {
    guard graphicsState.device.kind == .page,
      graphicsDeviceDescriptor.trapping.capabilities.supportedTypes.contains(1001)
    else { throw Error.undefined }
  }

  func requireUnencapsulatedTrappingOperation() throws {
    guard encapsulatedPaintDepth == 0,
      imageDataSourceCallbackDepth == 0,
      activeGlyphBuild == nil
    else { throw Error.undefined }
  }

  func updateTrapping(
    _ snapshot: GraphicsTrappingSnapshot,
    trapSetNameSource: Object?,
    operation: GraphicsOperation
  ) throws {
    let before = graphicsState.snapshot
    graphicsState.device.updateTrapping(snapshot, trapSetNameSource: trapSetNameSource)
    let after = graphicsState.snapshot
    do {
      try graphicsEventConsumer?.process(GraphicsEvent(operation: operation, before: before, after: after))
    } catch {
      throw Error.ioError
    }
  }
}
