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
        session: session,
        context: context
      )
      var negotiation: GraphicsPageDeviceNegotiation
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
      let pageSizePolicy = try parsed.originalValues["PageSize"].map {
        _ in try policy(for: "PageSize", in: parsed.parameters.policies)
      }
      if !negotiation.unsatisfiedParameters.isEmpty || pageSizePolicy == 7 {
        let recoveredRequest = try recoverMediaRequest(
          parsed.request,
          unsatisfied: negotiation.unsatisfiedParameters,
          policies: parsed.parameters.policies,
          pageSizePolicy: pageSizePolicy
        )
        if recoveredRequest != parsed.request {
          do {
            negotiation = try session.negotiate(recoveredRequest)
          } catch GraphicsPageDeviceError.limitExceeded {
            throw Error.limitCheck
          } catch {
            throw Error.configurationError
          }
          guard negotiation.unsatisfiedParameters.isEmpty else {
            let name = negotiation.unsatisfiedParameters.sorted().first ?? "PageSize"
            throw PostScriptParameterFailure(
              error: .configurationError,
              key: .literalName(name),
              value: parsed.originalValues[name]
            )
          }
          if pageSizePolicy == 7 { recovered["PageSize"] = 7 }
        }
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
      var entries: [(Object, Object)] = [
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
        (.literalName("UseCIEColor"), .boolean(configuration.usesCIEColor)),
      ]
      if context.graphicsPageDeviceSession?.capabilities.physical.supportsMediaSelection == true {
        entries.append((
          .literalName("InputAttributes"),
          try inputAttributesDictionary(configuration.inputMedia, vm: vm, context: context)
        ))
        entries.append((
          .literalName("MediaColor"),
          byteStringOrNull(configuration.mediaRequest.attributes.color, vm: vm)
        ))
        entries.append((
          .literalName("MediaWeight"),
          configuration.mediaRequest.attributes.weight.flatMap(Object.real(finite:)) ?? .null
        ))
        entries.append((
          .literalName("MediaType"),
          byteStringOrNull(configuration.mediaRequest.attributes.type, vm: vm)
        ))
        entries.append((
          .literalName("MediaClass"),
          byteStringOrNull(configuration.mediaRequest.attributes.mediaClass, vm: vm)
        ))
        entries.append((
          .literalName("InsertSheet"),
          configuration.mediaRequest.attributes.insertsSheet.map(Object.boolean) ?? .null
        ))
        entries.append((
          .literalName("LeadingEdge"),
          configuration.mediaRequest.leadingEdge.map { .integer(Int32($0.rawValue)) } ?? .null
        ))
        entries.append((
          .literalName("MediaPosition"),
          configuration.mediaRequest.position.flatMap(Object.integer(exactly:)) ?? .null
        ))
        entries.append((.literalName("ManualFeed"), .boolean(configuration.mediaRequest.manualFeed)))
        entries.append((.literalName("TraySwitch"), .boolean(configuration.mediaRequest.traySwitch)))
        entries.append((
          .literalName("DeferredMediaSelection"),
          .boolean(configuration.mediaRequest.isDeferred)
        ))
      }
      if let outputDevice = configuration.outputDevice {
        entries.append((.literalName("OutputDevice"), .literalName(outputDevice)))
      }
      if context.graphicsPageDeviceSession?.capabilities.physical != .virtual {
        entries.append((.literalName("RollFedMedia"), .boolean(configuration.delivery.isRollFed)))
        entries.append((
          .literalName("Orientation"),
          .integer(Int32(configuration.placement.orientation.rawValue))
        ))
        entries.append((
          .literalName("AdvanceMedia"),
          .integer(Int32(configuration.delivery.advanceMedia.rawValue))
        ))
        entries.append((
          .literalName("AdvanceDistance"),
          Object.real(finite: configuration.delivery.advanceDistance) ?? .integer(0)
        ))
        entries.append((
          .literalName("CutMedia"),
          .integer(Int32(configuration.delivery.cutMedia.rawValue))
        ))
        entries.append((
          .literalName("ImageShift"),
          try numberArray(
            [configuration.placement.imageShift.x, configuration.placement.imageShift.y],
            vm: vm,
            context: context
          )
        ))
        entries.append((
          .literalName("PageOffset"),
          try numberArray(
            [configuration.placement.pageOffset.x, configuration.placement.pageOffset.y],
            vm: vm,
            context: context
          )
        ))
        entries.append((
          .literalName("Margins"),
          try numberArray(
            [configuration.placement.margins.x, configuration.placement.margins.y],
            vm: vm,
            context: context
          )
        ))
        entries.append((.literalName("MirrorPrint"), .boolean(configuration.placement.mirrorsPage)))
        entries.append((
          .literalName("NegativePrint"),
          .boolean(configuration.placement.producesNegative)
        ))
        entries.append((.literalName("Duplex"), .boolean(configuration.placement.isDuplex)))
        entries.append((.literalName("Tumble"), .boolean(configuration.placement.tumbles)))
      }
      let dictionary = try context.makeDictionary(entries, access: .readOnly, vm: vm)
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
    session: any GraphicsPageDeviceSession,
    context: isolated Context
  ) throws -> ParsedPageDeviceRequest {
    var entries: [String: Object] = [:]
    try dictionary.forEachUnchecked { key, value in
      let name = try PostScriptParameterFailure.wrapping(key: key, value: value) {
        try key.value(as: NameValue.self).value
      }
      entries[name] = value
    }
    let originals = entries

    let policies = try mergedPolicies(
      entries.removeValue(forKey: "Policies"),
      current: currentParameters.policies,
      context: context
    )
    var recovered: [String: Int32] = [:]
    var outputDevice = currentConfiguration.outputDevice
    var selectedProfile = session.outputDeviceProfiles.first {
      $0.resourceName == currentConfiguration.outputDevice
    } ?? session.outputDeviceProfiles[0]
    if let outputDeviceObject = entries.removeValue(forKey: "OutputDevice") {
      let requested = try PostScriptParameterFailure.wrapping(
        key: .literalName("OutputDevice"),
        value: outputDeviceObject
      ) {
        try pageDeviceNameOrString(outputDeviceObject)
      }
      if let profile = session.outputDeviceProfiles.first(where: { $0.resourceName == requested }) {
        selectedProfile = profile
        outputDevice = requested
      } else {
        try recover(
          name: "OutputDevice",
          value: outputDeviceObject,
          policies: policies,
          into: &recovered
        )
      }
    }
    let physical = selectedProfile.physicalCapabilities
    let changedOutputDevice = selectedProfile.identifier != currentConfiguration.outputDeviceIdentifier
    var inputMedia = changedOutputDevice ? selectedProfile.inputMedia : currentConfiguration.inputMedia
    if let inputAttributes = entries.removeValue(forKey: "InputAttributes") {
      if physical.supportsMediaSelection {
        inputMedia = try mergedInputMedia(
          inputAttributes,
          current: inputMedia
        )
      } else {
        try recover(
          name: "InputAttributes",
          value: inputAttributes,
          policies: policies,
          into: &recovered
        )
      }
    }
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
    var usesCIEColor = currentConfiguration.usesCIEColor
    var mediaAttributes = currentConfiguration.mediaRequest.attributes
    var leadingEdge = currentConfiguration.mediaRequest.leadingEdge
    var manualFeed = currentConfiguration.mediaRequest.manualFeed
    var traySwitch = currentConfiguration.mediaRequest.traySwitch
    var mediaPosition = currentConfiguration.mediaRequest.position
    var deferredMediaSelection = currentConfiguration.mediaRequest.isDeferred
    let basePlacement = changedOutputDevice ? GraphicsPagePlacement.simplex : currentConfiguration.placement
    let baseDelivery = changedOutputDevice
      ? GraphicsPageDeliveryConfiguration.virtual
      : currentConfiguration.delivery
    var orientation = basePlacement.orientation
    var imageShift = basePlacement.imageShift
    var pageOffset = basePlacement.pageOffset
    var margins = basePlacement.margins
    var mirrorPrint = basePlacement.mirrorsPage
    var negativePrint = basePlacement.producesNegative
    var duplex = basePlacement.isDuplex
    var tumble = basePlacement.tumbles
    var rollFedMedia = baseDelivery.isRollFed
    var advanceMedia = baseDelivery.advanceMedia
    var advanceDistance = baseDelivery.advanceDistance
    var cutMedia = baseDelivery.cutMedia

    for (name, value) in entries {
      do {
        switch name {
        case "PageSize":
          let values = try pageDeviceNumericArray(value, count: 2)
          guard values.allSatisfy({ $0.isFinite && $0 > 0 }) else { throw Error.rangeCheck }
          pageSize = GraphicsSize(width: values[0], height: values[1])
          mediaAttributes.pageSize = pageSize
        case "MediaColor":
          guard physical.supportsMediaSelection else {
            try recover(name: name, value: value, policies: policies, into: &recovered)
            continue
          }
          mediaAttributes.color = try pageDeviceOptionalBytes(value)
        case "MediaWeight":
          guard physical.supportsMediaSelection else {
            try recover(name: name, value: value, policies: policies, into: &recovered)
            continue
          }
          if value.value is NullValue {
            mediaAttributes.weight = nil
          } else {
            let weight = try numeric(value)
            guard weight.isFinite, weight >= 0 else { throw Error.rangeCheck }
            mediaAttributes.weight = weight
          }
        case "MediaType":
          guard physical.supportsMediaSelection else {
            try recover(name: name, value: value, policies: policies, into: &recovered)
            continue
          }
          mediaAttributes.type = try pageDeviceOptionalBytes(value)
        case "MediaClass":
          guard physical.supportsMediaSelection else {
            try recover(name: name, value: value, policies: policies, into: &recovered)
            continue
          }
          mediaAttributes.mediaClass = try pageDeviceOptionalBytes(value)
        case "InsertSheet":
          guard physical.supportsMediaSelection else {
            try recover(name: name, value: value, policies: policies, into: &recovered)
            continue
          }
          mediaAttributes.insertsSheet = try value.value(as: BooleanValue.self).value
        case "LeadingEdge":
          guard physical.supportsMediaSelection else {
            try recover(name: name, value: value, policies: policies, into: &recovered)
            continue
          }
          if value.value is NullValue {
            leadingEdge = nil
          } else {
            let raw = try value.value(as: IntegerValue.self).value
            guard let selected = GraphicsLeadingEdge(rawValue: Int(raw)) else { throw Error.rangeCheck }
            leadingEdge = selected
          }
        case "ManualFeed":
          guard physical.supportsManualFeed else {
            try recover(name: name, value: value, policies: policies, into: &recovered)
            continue
          }
          manualFeed = try value.value(as: BooleanValue.self).value
        case "TraySwitch":
          guard physical.supportsTraySwitch else {
            try recover(name: name, value: value, policies: policies, into: &recovered)
            continue
          }
          traySwitch = try value.value(as: BooleanValue.self).value
        case "MediaPosition":
          guard physical.supportsMediaSelection else {
            try recover(name: name, value: value, policies: policies, into: &recovered)
            continue
          }
          if value.value is NullValue {
            mediaPosition = nil
          } else {
            mediaPosition = Int(try value.value(as: IntegerValue.self).value)
          }
        case "DeferredMediaSelection":
          guard physical.supportsDeferredSelection else {
            try recover(name: name, value: value, policies: policies, into: &recovered)
            continue
          }
          deferredMediaSelection = try value.value(as: BooleanValue.self).value
        case "RollFedMedia":
          rollFedMedia = try value.value(as: BooleanValue.self).value
        case "Orientation":
          let raw = try value.value(as: IntegerValue.self).value
          guard let selected = GraphicsPageOrientation(rawValue: Int(raw)) else { throw Error.rangeCheck }
          orientation = selected
        case "AdvanceMedia":
          let raw = try value.value(as: IntegerValue.self).value
          guard let selected = GraphicsMediaActionMode(rawValue: Int(raw)) else { throw Error.rangeCheck }
          advanceMedia = selected
        case "AdvanceDistance":
          let distance = try numeric(value)
          guard distance.isFinite, distance >= 0 else { throw Error.rangeCheck }
          advanceDistance = distance
        case "CutMedia":
          let raw = try value.value(as: IntegerValue.self).value
          guard let selected = GraphicsMediaActionMode(rawValue: Int(raw)) else { throw Error.rangeCheck }
          cutMedia = selected
        case "ImageShift":
          imageShift = try pageDevicePoint(value)
        case "PageOffset":
          pageOffset = try pageDevicePoint(value)
        case "Margins":
          margins = try pageDevicePoint(value)
        case "MirrorPrint":
          mirrorPrint = try value.value(as: BooleanValue.self).value
        case "NegativePrint":
          negativePrint = try value.value(as: BooleanValue.self).value
        case "Duplex":
          duplex = try value.value(as: BooleanValue.self).value
        case "Tumble":
          tumble = try value.value(as: BooleanValue.self).value
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
        case "UseCIEColor":
          usesCIEColor = try value.value(as: BooleanValue.self).value
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
        trappingDetails: trappingDetails,
        usesCIEColor: usesCIEColor,
        outputDevice: outputDevice,
        inputMedia: inputMedia,
        mediaRequest: GraphicsMediaRequest(
          attributes: mediaAttributes,
          leadingEdge: leadingEdge,
          manualFeed: manualFeed,
          position: mediaPosition,
          traySwitch: traySwitch,
          isDeferred: deferredMediaSelection
        ),
        outputDestinations: changedOutputDevice
          ? selectedProfile.outputDestinations
          : currentConfiguration.outputDestinations,
        outputType: changedOutputDevice ? nil : currentConfiguration.outputType,
        placement: GraphicsPagePlacement(
          orientation: orientation,
          side: changedOutputDevice ? .recto : currentConfiguration.placement.side,
          leadingEdge: leadingEdge,
          imageShift: imageShift,
          pageOffset: pageOffset,
          margins: margins,
          mirrorsPage: mirrorPrint,
          producesNegative: negativePrint,
          isDuplex: duplex,
          tumbles: tumble
        ),
        delivery: GraphicsPageDeliveryConfiguration(
          destination: changedOutputDevice ? nil : currentConfiguration.delivery.destination,
          deferredOutputType: changedOutputDevice
            ? nil
            : currentConfiguration.delivery.deferredOutputType,
          collates: changedOutputDevice ? false : currentConfiguration.delivery.collates,
          outputFace: changedOutputDevice ? .faceDown : currentConfiguration.delivery.outputFace,
          jog: changedOutputDevice ? .never : currentConfiguration.delivery.jog,
          isRollFed: rollFedMedia,
          advanceMedia: advanceMedia,
          advanceDistance: advanceDistance,
          cutMedia: cutMedia
        )
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

  private static func mergedInputMedia(
    _ requested: Object,
    current: GraphicsMediaCatalog
  ) throws -> GraphicsMediaCatalog {
    if requested.value is NullValue { return .empty }
    let dictionary = try requested.value(as: DictionaryValue.self)
    try dictionary.access.check(.read)
    var sources = current.sources
    var priority = current.priority
    try dictionary.forEachUnchecked { key, value in
      if let name = key.value as? NameValue {
        guard name.value == "Priority" else { throw Error.typeCheck }
        priority = try pageDeviceIntegerArray(value)
        return
      }
      let position = Int(try key.value(as: IntegerValue.self).value)
      if value.value is NullValue {
        sources[position] = GraphicsMediaSource(
          position: position,
          attributes: nil,
          isManual: sources[position]?.isManual ?? false
        )
        return
      }
      let source = try value.value(as: DictionaryValue.self)
      try source.access.check(.read)
      guard let pageSizeObject = try source.object(forKeyIfExists: .literalName("PageSize")) else {
        throw Error.rangeCheck
      }
      let pageSizeValues = try pageDeviceNumericArray(pageSizeObject, count: 2)
      guard pageSizeValues.allSatisfy({ $0.isFinite && $0 > 0 }) else { throw Error.rangeCheck }
      var attributes = GraphicsMediaAttributes(pageSize: GraphicsSize(
        width: pageSizeValues[0],
        height: pageSizeValues[1]
      ))
      if let object = try source.object(forKeyIfExists: .literalName("MediaColor")) {
        attributes.color = try pageDeviceOptionalBytes(object)
      }
      if let object = try source.object(forKeyIfExists: .literalName("MediaWeight")) {
        if !(object.value is NullValue) {
          let weight = try numeric(object)
          guard weight.isFinite, weight >= 0 else { throw Error.rangeCheck }
          attributes.weight = weight
        }
      }
      if let object = try source.object(forKeyIfExists: .literalName("MediaType")) {
        attributes.type = try pageDeviceOptionalBytes(object)
      }
      if let object = try source.object(forKeyIfExists: .literalName("MediaClass")) {
        attributes.mediaClass = try pageDeviceOptionalBytes(object)
      }
      if let object = try source.object(forKeyIfExists: .literalName("InsertSheet")) {
        attributes.insertsSheet = try object.value(as: BooleanValue.self).value
      }
      let matchAll = try source.object(forKeyIfExists: .literalName("MatchAll"))
        .map { try $0.value(as: BooleanValue.self).value } ?? false
      sources[position] = GraphicsMediaSource(
        position: position,
        attributes: attributes,
        matchesAllAttributes: matchAll,
        isManual: sources[position]?.isManual ?? false
      )
    }
    return GraphicsMediaCatalog(sources: sources, priority: priority)
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

  private static func recoverMediaRequest(
    _ request: GraphicsPageDeviceRequest,
    unsatisfied: Set<String>,
    policies: Object,
    pageSizePolicy: Int32?
  ) throws -> GraphicsPageDeviceRequest {
    let mediaNames: Set<String> = [
      "PageSize", "MediaColor", "MediaWeight", "MediaType", "MediaClass", "InsertSheet",
      "ManualFeed", "MediaPosition",
    ]
    guard !unsatisfied.isDisjoint(with: mediaNames) || pageSizePolicy == 7 else { return request }

    var attributes = request.mediaRequest.attributes
    var manualFeed = request.mediaRequest.manualFeed
    var position = request.mediaRequest.position
    for name in unsatisfied where name != "PageSize" {
      guard try policy(for: name, in: policies) == 1 else { continue }
      switch name {
      case "MediaColor": attributes.color = nil
      case "MediaWeight": attributes.weight = nil
      case "MediaType": attributes.type = nil
      case "MediaClass": attributes.mediaClass = nil
      case "InsertSheet": attributes.insertsSheet = nil
      case "ManualFeed": manualFeed = false
      case "MediaPosition": position = nil
      default: break
      }
    }

    let code: Int32?
    if let pageSizePolicy {
      code = pageSizePolicy
    } else if unsatisfied.contains("PageSize") {
      code = try policy(for: "PageSize", in: policies)
    } else {
      code = nil
    }
    var pageSize = request.pageSize
    var placement = request.placement
    if let code {
      let base = GraphicsMediaRequest(
        attributes: attributes,
        leadingEdge: request.mediaRequest.leadingEdge,
        manualFeed: manualFeed,
        position: position,
        traySwitch: request.mediaRequest.traySwitch,
        isDeferred: false
      )
      let selected: GraphicsMediaSource?
      switch code {
      case 1:
        var withoutSize = attributes
        withoutSize.pageSize = nil
        selected = GraphicsMediaMatcher.select(
          request: GraphicsMediaRequest(
            attributes: withoutSize,
            leadingEdge: base.leadingEdge,
            manualFeed: base.manualFeed,
            position: base.position,
            traySwitch: base.traySwitch
          ),
          catalog: request.inputMedia,
          rollFed: request.delivery.isRollFed
        )
      case 3, 5:
        selected = GraphicsMediaMatcher.alternative(
          request: base,
          catalog: request.inputMedia,
          nextLarger: false
        )
      case 4, 6:
        selected = GraphicsMediaMatcher.alternative(
          request: base,
          catalog: request.inputMedia,
          nextLarger: true
        )
      case 7:
        selected = GraphicsMediaMatcher.select(
          request: base,
          catalog: request.inputMedia,
          rollFed: request.delivery.isRollFed
        )
      default:
        selected = nil
      }
      guard let selected, let selectedAttributes = selected.attributes,
        let selectedSize = selectedAttributes.pageSize
      else {
        throw PostScriptParameterFailure(
          error: .configurationError,
          key: .literalName("PageSize"),
          value: nil
        )
      }
      attributes = selectedAttributes
      position = selected.position
      if code == 1 || code == 5 || code == 6 { pageSize = selectedSize }
      if code == 3 || code == 4 {
        guard !request.mediaRequest.isDeferred else {
          throw PostScriptParameterFailure(
            error: .configurationError,
            key: .literalName("PageSize"),
            value: nil
          )
        }
        let scale = min(
          1,
          selectedSize.width / request.pageSize.width,
          selectedSize.height / request.pageSize.height
        )
        let offset = GraphicsPoint(
          x: (selectedSize.width - request.pageSize.width * scale) / 2,
          y: (selectedSize.height - request.pageSize.height * scale) / 2
        )
        placement = GraphicsPagePlacement(
          orientation: placement.orientation,
          side: placement.side,
          leadingEdge: placement.leadingEdge,
          imageShift: placement.imageShift,
          pageOffset: placement.pageOffset,
          mediaAdjustment: GraphicsMatrix(
            a: scale,
            b: 0,
            c: 0,
            d: scale,
            tx: offset.x,
            ty: offset.y
          ),
          margins: placement.margins,
          mirrorsPage: placement.mirrorsPage,
          producesNegative: placement.producesNegative,
          isDuplex: placement.isDuplex,
          tumbles: placement.tumbles
        )
      }
    }

    return GraphicsPageDeviceRequest(
      pageSize: pageSize,
      resolution: request.resolution,
      imagingBoundingBox: request.imagingBoundingBox,
      numberOfCopies: request.numberOfCopies,
      colorants: request.colorants,
      trappingEnabled: request.trappingEnabled,
      trappingDetails: request.trappingDetails,
      usesCIEColor: request.usesCIEColor,
      outputDevice: request.outputDevice,
      inputMedia: request.inputMedia,
      mediaRequest: GraphicsMediaRequest(
        attributes: attributes,
        leadingEdge: request.mediaRequest.leadingEdge,
        manualFeed: manualFeed,
        position: position,
        traySwitch: request.mediaRequest.traySwitch,
        isDeferred: request.mediaRequest.isDeferred
      ),
      outputDestinations: request.outputDestinations,
      outputType: request.outputType,
      placement: placement,
      delivery: request.delivery
    )
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

  private static func pageDevicePoint(_ object: Object) throws -> GraphicsPoint {
    let values = try pageDeviceNumericArray(object, count: 2)
    guard values.allSatisfy(\.isFinite) else { throw Error.rangeCheck }
    return GraphicsPoint(x: values[0], y: values[1])
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

  private static func pageDeviceIntegerArray(_ object: Object) throws -> [Int] {
    let values: [Object]
    if let array = object.value as? ArrayValue {
      values = Array(try array.objects(in: array.range, for: .read))
    } else if let array = object.value as? PackedArrayValue {
      values = Array(try array.objects(in: array.range, for: .read))
    } else {
      throw Error.typeCheck
    }
    return try values.map { Int(try $0.value(as: IntegerValue.self).value) }
  }

  private static func pageDeviceOptionalBytes(_ object: Object) throws -> Data? {
    if object.value is NullValue { return nil }
    let string = try object.value(as: StringValue.self)
    return try string.characters(in: string.range)
  }

  private static func pageDeviceNameOrString(_ object: Object) throws -> String {
    if let name = object.value as? NameValue { return name.value }
    if let string = object.value as? StringValue { return try string.readableString }
    throw Error.typeCheck
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

  private static func inputAttributesDictionary(
    _ catalog: GraphicsMediaCatalog,
    vm: VM,
    context: isolated Context
  ) throws -> Object {
    var entries: [(Object, Object)] = []
    for source in catalog.sources.values.sorted(by: { $0.position < $1.position }) {
      let value: Object
      if let attributes = source.attributes {
        var sourceEntries: [(Object, Object)] = []
        if let size = attributes.pageSize {
          sourceEntries.append((
            .literalName("PageSize"),
            try numberArray([size.width, size.height], vm: vm, context: context)
          ))
        }
        sourceEntries.append((.literalName("MediaColor"), byteStringOrNull(attributes.color, vm: vm)))
        sourceEntries.append((
          .literalName("MediaWeight"),
          attributes.weight.flatMap(Object.real(finite:)) ?? .null
        ))
        sourceEntries.append((.literalName("MediaType"), byteStringOrNull(attributes.type, vm: vm)))
        sourceEntries.append((.literalName("MediaClass"), byteStringOrNull(attributes.mediaClass, vm: vm)))
        sourceEntries.append((
          .literalName("InsertSheet"),
          attributes.insertsSheet.map(Object.boolean) ?? .null
        ))
        if source.matchesAllAttributes {
          sourceEntries.append((.literalName("MatchAll"), .boolean(true)))
        }
        value = try context.makeDictionary(sourceEntries, access: .readOnly, vm: vm)
      } else {
        value = .null
      }
      guard let key = Object.integer(exactly: source.position) else { throw Error.rangeCheck }
      entries.append((key, value))
    }
    if !catalog.priority.isEmpty {
      let priority = try integerArray(catalog.priority, vm: vm, context: context)
      entries.append((.literalName("Priority"), priority))
    }
    return try context.makeDictionary(entries, access: .readOnly, vm: vm)
  }

  private static func byteStringOrNull(_ data: Data?, vm: VM) -> Object {
    data.map { .string($0, access: .readOnly, vm: vm, kind: .literal) } ?? .null
  }

  private static func integerArray(
    _ values: [Int],
    vm: VM,
    context: isolated Context
  ) throws -> Object {
    try context.preflightAllocation(
      bytes: context.estimatedAllocationSize(count: values.count, objectType: .array),
      vm: vm
    )
    let objects = try values.map { value -> Object in
      guard let object = Object.integer(exactly: value) else { throw Error.rangeCheck }
      return object
    }
    let array = try Object.array(objects, access: .readOnly, vm: vm, kind: .literal)
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
        let kind: GraphicsTrappingColorantType
        if let object = try colorant.object(forKeyIfExists: .literalName("ColorantType")) {
          let name = try object.value(as: NameValue.self).value
          guard let value = GraphicsTrappingColorantType(rawValue: name) else { throw Error.rangeCheck }
          kind = value
        } else {
          kind = previous?.colorantType ?? .normal
        }
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
