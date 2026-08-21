import Foundation

extension Operators {
  static let halftoneOps: [OperatorValue] = [
    SetScreen.instance,
    CurrentScreen.instance,
    SetColorScreen.instance,
    CurrentColorScreen.instance,
    SetHalftone.instance,
    CurrentHalftone.instance,
  ]

  enum SetScreen: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setscreen"]

    func execute(context: isolated Context) async throws {
      try requireDeviceRenderingOperationAllowed(context)
      let (spot, angleObject, frequencyObject) = try context.operands.pop3()
      if let dictionary = spot.value as? DictionaryValue {
        let source = try overriddenTypeOneDictionary(
          dictionary,
          frequency: frequencyObject,
          angle: angleObject,
          context: context
        )
        try await installHalftone(
          dictionary: try source.value(as: DictionaryValue.self),
          source: source,
          context: context
        )
        return
      }
      try spot.checkProcedure()
      let frequency = try numeric(frequencyObject)
      let angle = try numeric(angleObject)
      let screen = try await compileSpotScreen(
        frequency: frequency,
        angle: angle,
        procedure: spot,
        transfer: nil,
        accurate: context.userParameters.boolean("AccurateScreens"),
        context: context
      )
      let source = try compatibilityArray(
        [try .real(screen.actualFrequency), try .real(screen.actualAngle), spot],
        context: context
      )
      try installHalftone(.spot(screen), source: source, context: context)
    }
  }

  enum CurrentScreen: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currentscreen"]

    func execute(context: isolated Context) async throws {
      if let values = try compatibilityValues(context.graphicsState.halftoneSource), values.count == 3 {
        context.operands.push(values[2], values[1], values[0])
        return
      }
      if let values = try compatibilityValues(context.graphicsState.halftoneSource), values.count == 12 {
        context.operands.push(values[11], values[10], values[9])
        return
      }
      context.operands.push(
        try currentHalftoneObject(context: context),
        try .real(0),
        try .real(60)
      )
    }
  }

  enum SetColorScreen: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setcolorscreen"]

    func execute(context: isolated Context) async throws {
      try requireDeviceRenderingOperationAllowed(context)
      let popped = try context.operands.pop(count: 12)
      let values = Array(popped.reversed())
      if let dictionary = values[11].value as? DictionaryValue {
        let source = try overriddenTypeOneDictionary(
          dictionary,
          frequency: values[9],
          angle: values[10],
          context: context
        )
        try await installHalftone(
          dictionary: try source.value(as: DictionaryValue.self),
          source: source,
          context: context
        )
        return
      }
      var screens: [String: GraphicsHalftone] = [:]
      for (offset, name) in zip(stride(from: 0, to: 12, by: 3), ["Red", "Green", "Blue", "Gray"]) {
        let procedure = values[offset + 2]
        try procedure.checkProcedure()
        screens[name] = .spot(try await compileSpotScreen(
          frequency: numeric(values[offset]),
          angle: numeric(values[offset + 1]),
          procedure: procedure,
          transfer: nil,
          accurate: context.userParameters.boolean("AccurateScreens"),
          context: context
        ))
      }
      screens["Default"] = screens["Gray"]
      var actualValues = values
      for (offset, name) in zip(stride(from: 0, to: 12, by: 3), ["Red", "Green", "Blue", "Gray"]) {
        guard case .spot(let screen) = screens[name] else { continue }
        actualValues[offset] = try .real(screen.actualFrequency)
        actualValues[offset + 1] = try .real(screen.actualAngle)
      }
      let source = try compatibilityArray(actualValues, context: context)
      try installHalftone(.colorants(screens), source: source, context: context)
    }
  }

  enum CurrentColorScreen: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currentcolorscreen"]

    func execute(context: isolated Context) async throws {
      if let values = try compatibilityValues(context.graphicsState.halftoneSource) {
        if values.count == 12 {
          context.operands.push(contentsOf: values.reversed())
          return
        }
        if values.count == 3 {
          context.operands.push(contentsOf: Array(repeating: values, count: 4).flatMap { $0 }.reversed())
          return
        }
      }
      let dictionary = try currentHalftoneObject(context: context)
      var values: [Object] = []
      for _ in 0..<4 {
        values.append(try .real(60))
        values.append(try .real(0))
        values.append(dictionary)
      }
      context.operands.push(contentsOf: values.reversed())
    }
  }

  enum SetHalftone: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["sethalftone"]

    func execute(context: isolated Context) async throws {
      try requireDeviceRenderingOperationAllowed(context)
      let source = try context.operands.pop()
      let dictionary = try source.value(as: DictionaryValue.self)
      try await installHalftone(dictionary: dictionary, source: source, context: context)
    }
  }

  enum CurrentHalftone: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currenthalftone"]

    func execute(context: isolated Context) async throws {
      context.operands.push(try currentHalftoneObject(context: context))
    }
  }

  static func installHalftone(
    dictionary: DictionaryValue,
    source: Object,
    context: isolated Context
  ) async throws {
    try dictionary.access.check(.read)
    let halftone = try await parseHalftone(dictionary, nested: false, context: context)
    try updateActualScreenEntries(dictionary, halftone: halftone, context: context)
    let normalizedSource = try currentHalftoneSource(
      dictionary,
      original: source,
      halftone: halftone,
      context: context
    )
    try installHalftone(halftone, source: normalizedSource, context: context)
  }

  static func installHalftone(
    _ halftone: GraphicsHalftone,
    source: Object,
    context: isolated Context
  ) throws {
    let lease = try context.environment.screenManager.lease(halftone)
    try context.applyGraphicsOperation(.state(.setHalftone)) {
      $0.halftoneSource = source
      $0.screenLease = lease
      $0.deviceRendering = GraphicsDeviceRenderingSnapshot(
        transferFunctions: $0.deviceRendering.transferFunctions,
        blackGeneration: $0.deviceRendering.blackGeneration,
        undercolorRemoval: $0.deviceRendering.undercolorRemoval,
        halftone: halftone
      )
    }
  }

  static func parseHalftone(
    _ dictionary: DictionaryValue,
    nested: Bool,
    context: isolated Context
  ) async throws -> GraphicsHalftone {
    try dictionary.access.check(.read)
    let type = try dictionary.objectValue(forKey: "HalftoneType", as: IntegerValue.self).value
    if nested, type == 2 || type == 4 || type == 5 { throw Error.rangeCheck }
    switch type {
    case 1:
      let procedure = try dictionary.object(forKey: "SpotFunction")
      try procedure.checkProcedure()
      return .spot(try await compileSpotScreen(
        frequency: numeric(dictionary.object(forKey: "Frequency")),
        angle: numeric(dictionary.object(forKey: "Angle")),
        procedure: procedure,
        transfer: try await transferFunction(dictionary, context: context),
        accurate: try dictionary.object(forKeyIfExists: "AccurateScreens")
          .map { try $0.value(as: BooleanValue.self).value }
          ?? context.userParameters.boolean("AccurateScreens"),
        context: context
      ))
    case 2:
      var screens: [String: GraphicsHalftone] = [:]
      for name in ["Red", "Green", "Blue", "Gray"] {
        let procedure = try dictionary.object(forKey: .literalName("\(name)SpotFunction"))
        try procedure.checkProcedure()
        screens[name] = .spot(try await compileSpotScreen(
          frequency: numeric(dictionary.object(forKey: .literalName("\(name)Frequency"))),
          angle: numeric(dictionary.object(forKey: .literalName("\(name)Angle"))),
          procedure: procedure,
          transfer: nil,
          accurate: context.userParameters.boolean("AccurateScreens"),
          context: context
        ))
      }
      screens["Default"] = screens["Gray"]
      return .colorants(screens)
    case 3, 6:
      return .threshold(try await thresholdScreen(
        dictionary,
        prefix: "",
        fileRequired: type == 6,
        context: context
      ))
    case 4:
      var screens: [String: GraphicsHalftone] = [:]
      for name in ["Red", "Green", "Blue", "Gray"] {
        screens[name] = .threshold(try await thresholdScreen(
          dictionary,
          prefix: name,
          fileRequired: false,
          context: context
        ))
      }
      screens["Default"] = screens["Gray"]
      return .colorants(screens)
    case 5:
      var screens: [String: GraphicsHalftone] = [:]
      // Dictionary traversal cannot suspend; collect children first and parse them in order.
      var children: [(String, DictionaryValue)] = []
      try dictionary.forEachUnchecked { key, value in
        let name = try halftoneColorantName(key)
        guard name != "HalftoneType", name != "HalftoneName" else { return }
        children.append((name, try value.value(as: DictionaryValue.self)))
      }
      screens.removeAll(keepingCapacity: true)
      for (name, child) in children {
        if !standardProcessColorants.contains(name),
          try child.object(forKeyIfExists: "TransferFunction") == nil
        {
          throw Error.undefined
        }
        screens[name] = try await parseHalftone(child, nested: true, context: context)
      }
      guard screens["Default"] != nil else { throw Error.rangeCheck }
      return .colorants(screens)
    case 10:
      let x = try positiveInteger(dictionary, key: "Xsquare")
      let y = try positiveInteger(dictionary, key: "Ysquare")
      let total = try checkedAdd(checkedMultiply(x, x), checkedMultiply(y, y))
      let bytes = try await thresholdBytes(
        dictionary.object(forKey: "Thresholds"),
        count: total,
        fileRequired: nil,
        context: context
      )
      return .threshold(try GraphicsThresholdScreen(
        width: x,
        height: x,
        thresholds: bytes.map(UInt16.init),
        secondaryWidth: y,
        secondaryHeight: y,
        usesAngledSquares: true,
        transferFunction: try await transferFunction(dictionary, context: context)
      ))
    case 16:
      let width = try positiveInteger(dictionary, key: "Width")
      let height = try positiveInteger(dictionary, key: "Height")
      let width2 = try dictionary.object(forKeyIfExists: "Width2").map {
        try positiveInteger($0)
      }
      let height2 = try dictionary.object(forKeyIfExists: "Height2").map {
        try positiveInteger($0)
      }
      guard (width2 == nil) == (height2 == nil) else { throw Error.rangeCheck }
      let primaryCount = try checkedMultiply(width, height)
      let secondaryCount = try width2.map { try checkedMultiply($0, height2!) } ?? 0
      let sampleCount = try checkedAdd(primaryCount, secondaryCount)
      let bytes = try await thresholdBytes(
        dictionary.object(forKey: "Thresholds"),
        count: try checkedMultiply(sampleCount, 2),
        fileRequired: true,
        context: context
      )
      var values: [UInt16] = []
      values.reserveCapacity(sampleCount)
      for offset in stride(from: 0, to: bytes.count, by: 2) {
        values.append(max(1, UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])))
      }
      return .threshold(try GraphicsThresholdScreen(
        width: width,
        height: height,
        bitsPerSample: 16,
        thresholds: values,
        secondaryWidth: width2,
        secondaryHeight: height2,
        transferFunction: try await transferFunction(dictionary, context: context)
      ))
    case 9, 100:
      throw Error.rangeCheck
    default:
      throw Error.rangeCheck
    }
  }

  static func validateHalftoneDictionaryStructure(
    _ dictionary: DictionaryValue,
    nested: Bool = false
  ) throws {
    try dictionary.access.check(.read)
    let type = try dictionary.objectValue(forKey: "HalftoneType", as: IntegerValue.self).value
    guard [1, 2, 3, 4, 5, 6, 10, 16].contains(type) else { throw Error.rangeCheck }
    if nested, type == 2 || type == 4 || type == 5 { throw Error.rangeCheck }
    try validateHalftoneName(dictionary)
    switch type {
    case 1:
      guard try numeric(dictionary.object(forKey: "Frequency")) > 0 else { throw Error.rangeCheck }
      _ = try numeric(dictionary.object(forKey: "Angle"))
      try dictionary.object(forKey: "SpotFunction").checkProcedure()
      try validateOptionalBoolean(dictionary, key: "AccurateScreens")
      try validateOptionalNumber(dictionary, key: "ActualFrequency")
      try validateOptionalNumber(dictionary, key: "ActualAngle")
      try validateOptionalProcedure(dictionary, key: "TransferFunction")
    case 2:
      for name in ["Red", "Green", "Blue", "Gray"] {
        guard try numeric(dictionary.object(forKey: .literalName("\(name)Frequency"))) > 0 else {
          throw Error.rangeCheck
        }
        _ = try numeric(dictionary.object(forKey: .literalName("\(name)Angle")))
        try dictionary.object(forKey: .literalName("\(name)SpotFunction")).checkProcedure()
      }
      try validateOptionalBoolean(dictionary, key: "AccurateScreens")
    case 3, 6:
      let width = try positiveInteger(dictionary, key: "Width")
      let height = try positiveInteger(dictionary, key: "Height")
      let count = try checkedMultiply(width, height)
      let thresholds = try dictionary.object(forKey: "Thresholds")
      if type == 3 {
        try validateThresholdString(thresholds, count: count)
      } else {
        _ = try thresholds.value(as: FileValue.self)
      }
      try validateOptionalProcedure(dictionary, key: "TransferFunction")
    case 4:
      for name in ["Red", "Green", "Blue", "Gray"] {
        let width = try positiveInteger(dictionary, key: "\(name)Width")
        let height = try positiveInteger(dictionary, key: "\(name)Height")
        try validateThresholdString(
          dictionary.object(forKey: .literalName("\(name)Thresholds")),
          count: checkedMultiply(width, height)
        )
      }
    case 5:
      _ = try dictionary.objectValue(forKey: "Default", as: DictionaryValue.self)
      try dictionary.forEachUnchecked { key, value in
        let name = try halftoneColorantName(key)
        guard name != "HalftoneType", name != "HalftoneName" else { return }
        let child = try value.value(as: DictionaryValue.self)
        if !standardProcessColorants.contains(name),
          try child.object(forKeyIfExists: "TransferFunction") == nil
        {
          throw Error.undefined
        }
        try validateHalftoneDictionaryStructure(child, nested: true)
      }
    case 10:
      let x = try positiveInteger(dictionary, key: "Xsquare")
      let y = try positiveInteger(dictionary, key: "Ysquare")
      let count = try checkedAdd(checkedMultiply(x, x), checkedMultiply(y, y))
      let thresholds = try dictionary.object(forKey: "Thresholds")
      if thresholds.value is StringValue {
        try validateThresholdString(thresholds, count: count)
      } else {
        _ = try thresholds.value(as: FileValue.self)
      }
      try validateOptionalProcedure(dictionary, key: "TransferFunction")
    case 16:
      _ = try positiveInteger(dictionary, key: "Width")
      _ = try positiveInteger(dictionary, key: "Height")
      let width2 = try dictionary.object(forKeyIfExists: "Width2").map(positiveInteger)
      let height2 = try dictionary.object(forKeyIfExists: "Height2").map(positiveInteger)
      guard (width2 == nil) == (height2 == nil) else { throw Error.rangeCheck }
      _ = try dictionary.objectValue(forKey: "Thresholds", as: FileValue.self)
      try validateOptionalProcedure(dictionary, key: "TransferFunction")
    default:
      break
    }
  }

  private static func compileSpotScreen(
    frequency: Double,
    angle: Double,
    procedure: Object,
    transfer: GraphicsComponentFunction?,
    accurate: Bool,
    context: isolated Context
  ) async throws -> GraphicsSpotScreen {
    guard frequency > 0, frequency.isFinite, angle.isFinite else { throw Error.rangeCheck }
    let key = screenCacheKey(
      procedure,
      frequency: frequency,
      angle: angle,
      transfer: transfer,
      accurate: accurate,
      context: context
    )
    if let cached = context.environment.screenManager.screen(for: key),
      case .spot(let screen) = cached
    {
      return screen
    }
    let resolution = min(
      context.graphicsDeviceDescriptor.horizontalResolution,
      context.graphicsDeviceDescriptor.verticalResolution
    )
    var side = max(1, Int((resolution / frequency).rounded()))
    let maximumSuperScreen = Int(context.userParameters.integer("MaxSuperScreen"))
    if maximumSuperScreen >= side * 2, side <= Int.max / 2 { side *= 2 }
    let count = try checkedMultiply(side, side)
    let bytes = try checkedMultiply(count, MemoryLayout<UInt16>.stride)
    guard bytes <= Int(context.userParameters.integer("MaxScreenItem")),
      bytes <= ScreenManager.maximumItemBytes
    else { throw Error.limitCheck }
    var samples: [(value: Double, index: Int)] = []
    samples.reserveCapacity(count)
    for row in 0..<side {
      for column in 0..<side {
        let x = (Double(column) + 0.5) * 2 / Double(side) - 1
        let y = (Double(row) + 0.5) * 2 / Double(side) - 1
        let depth = context.operands.depth
        try await context.execute(proc: procedure, ops: [try .real(x), try .real(y)])
        guard context.operands.depth == depth + 1 else { throw Error.typeCheck }
        let value = try numeric(context.operands.pop())
        guard value >= -1, value <= 1, value.isFinite else { throw Error.rangeCheck }
        samples.append((value, row * side + column))
      }
    }
    samples.sort { $0.value == $1.value ? $0.index < $1.index : $0.value < $1.value }
    var thresholds = Array(repeating: UInt16(1), count: count)
    for (rank, sample) in samples.enumerated() {
      thresholds[sample.index] = UInt16(max(1, (rank + 1) * Int(UInt16.max) / count))
    }
    let screen = try GraphicsSpotScreen(
      frequency: frequency,
      angle: angle,
      actualFrequency: resolution / Double(side),
      actualAngle: angle.truncatingRemainder(dividingBy: 360),
      width: side,
      height: side,
      thresholds: thresholds,
      transferFunction: transfer
    )
    context.environment.screenManager.insert(
      .spot(screen),
      for: key,
      maximumItemBytes: Int(context.userParameters.integer("MaxScreenItem"))
    )
    return screen
  }

  private static func thresholdScreen(
    _ dictionary: DictionaryValue,
    prefix: String,
    fileRequired: Bool,
    context: isolated Context
  ) async throws -> GraphicsThresholdScreen {
    let width = try positiveInteger(dictionary, key: "\(prefix)Width")
    let height = try positiveInteger(dictionary, key: "\(prefix)Height")
    let count = try checkedMultiply(width, height)
    let bytes = try await thresholdBytes(
      dictionary.object(forKey: .literalName("\(prefix)Thresholds")),
      count: count,
      fileRequired: fileRequired,
      context: context
    )
    return try GraphicsThresholdScreen(
      width: width,
      height: height,
      thresholds: bytes.map(UInt16.init),
      transferFunction: prefix.isEmpty ? try await transferFunction(dictionary, context: context) : nil
    )
  }

  private static func thresholdBytes(
    _ object: Object,
    count: Int,
    fileRequired: Bool?,
    context: isolated Context
  ) async throws -> Data {
    guard count >= 0, count <= ScreenManager.maximumItemBytes else { throw Error.limitCheck }
    if let string = object.value as? StringValue {
      guard fileRequired != true else { throw Error.typeCheck }
      try string.access.check(.read)
      let bytes = try string.characters(in: string.range)
      guard bytes.count == count else { throw Error.rangeCheck }
      return bytes
    }
    guard fileRequired != false else { throw Error.typeCheck }
    let file = try object.value(as: FileValue.self)
    guard let bytes = try await context.read(max: count, from: file.file), bytes.count == count else {
      throw Error.rangeCheck
    }
    return bytes
  }

  private static func transferFunction(
    _ dictionary: DictionaryValue,
    context: isolated Context
  ) async throws -> GraphicsComponentFunction? {
    guard let procedure = try dictionary.object(forKeyIfExists: "TransferFunction") else { return nil }
    try procedure.checkProcedure()
    return try await compileComponentFunction(procedure, context: context)
  }

  private static func currentHalftoneObject(context: isolated Context) throws -> Object {
    if let source = context.graphicsState.halftoneSource {
      if source.value is DictionaryValue { return source }
      if let values = try compatibilityValues(source) {
        if values.count == 3 {
          return try halftoneDictionary(
            [
              ("HalftoneType", .integer(1)),
              ("Frequency", values[0]),
              ("Angle", values[1]),
              ("SpotFunction", values[2]),
            ],
            context: context
          )
        }
        if values.count == 12 {
          var entries: [(String, Object)] = [("HalftoneType", .integer(2))]
          for (offset, name) in zip(stride(from: 0, to: 12, by: 3), ["Red", "Green", "Blue", "Gray"]) {
            entries.append(("\(name)Frequency", values[offset]))
            entries.append(("\(name)Angle", values[offset + 1]))
            entries.append(("\(name)SpotFunction", values[offset + 2]))
          }
          return try halftoneDictionary(entries, context: context)
        }
      }
    }
    guard case .threshold(let screen) = context.graphicsState.deviceRendering.halftone else {
      return try halftoneDictionary([("HalftoneType", .integer(1))], context: context)
    }
    let data = Data(screen.thresholds.map { UInt8(clamping: $0) })
    let string = Object.string(data, access: .readOnly, vm: context.allocationMode, kind: .literal)
    try context.preflightAllocation(bytes: data.count + 16)
    try context.adopt(string)
    return try halftoneDictionary(
      [
        ("HalftoneType", .integer(3)),
        ("Width", .integer(Int32(clamping: screen.width))),
        ("Height", .integer(Int32(clamping: screen.height))),
        ("Thresholds", string),
      ],
      context: context
    )
  }

  private static func overriddenTypeOneDictionary(
    _ dictionary: DictionaryValue,
    frequency: Object,
    angle: Object,
    context: isolated Context
  ) throws -> Object {
    try dictionary.access.check(.read)
    guard try dictionary.objectValue(forKey: "HalftoneType", as: IntegerValue.self).value == 1 else {
      return Object.dictionary(sharing: dictionary, kind: .literal)
    }
    _ = try numeric(frequency)
    _ = try numeric(angle)
    return try copyDictionary(
      dictionary,
      replacing: [("Frequency", frequency), ("Angle", angle)],
      context: context
    )
  }

  private static func updateActualScreenEntries(
    _ dictionary: DictionaryValue,
    halftone: GraphicsHalftone,
    context: isolated Context
  ) throws {
    guard case .spot(let screen) = halftone else { return }
    for (key, value) in [
      ("ActualFrequency", screen.actualFrequency),
      ("ActualAngle", screen.actualAngle),
    ] {
      guard let existing = try dictionary.object(forKeyIfExists: .literalName(key)) else { continue }
      _ = try numeric(existing)
      let replacement = try Object.real(value)
      var mutation = try dictionary.prepareInterpreterUpdateObject(replacement, forKey: .literalName(key))
      while true {
        try context.preflightAllocation(bytes: mutation.allocationGrowthBytes, vm: dictionary.vm)
        if try dictionary.commit(mutation) { break }
        mutation = try dictionary.prepareInterpreterUpdateObject(replacement, forKey: .literalName(key))
      }
    }
  }

  private static func currentHalftoneSource(
    _ dictionary: DictionaryValue,
    original: Object,
    halftone: GraphicsHalftone,
    context: isolated Context
  ) throws -> Object {
    let type = try dictionary.objectValue(forKey: "HalftoneType", as: IntegerValue.self).value
    guard type == 6 || type == 10 || type == 16,
      let originalThresholds = try dictionary.object(forKeyIfExists: "Thresholds"),
      let originalFile = originalThresholds.value as? FileValue,
      case .threshold(let screen) = halftone
    else { return original }

    let data: Data
    if screen.bitsPerSample == 16 {
      data = Data(screen.thresholds.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xff)] })
    } else {
      data = Data(screen.thresholds.map(UInt8.init(clamping:)))
    }
    let access = type == 16 ? ObjectAccess.noAccess : originalFile.access
    let thresholds = Object.file(
      CircularThresholdFile(data: data),
      access: access,
      vm: originalFile.vm,
      kind: .literal
    )
    try context.preflightAllocation(bytes: 32, vm: originalFile.vm)
    try context.adopt(thresholds)
    return try copyDictionary(
      dictionary,
      replacing: [("Thresholds", thresholds)],
      context: context
    )
  }

  private static func copyDictionary(
    _ dictionary: DictionaryValue,
    replacing replacements: [(String, Object)],
    context: isolated Context
  ) throws -> Object {
    let replacementKeys = Set(replacements.map(\.0))
    var entries: [(Object, Object)] = []
    entries.reserveCapacity(Int(dictionary.count) + replacements.count)
    try dictionary.forEachUnchecked { key, value in
      if let name = key.value as? NameValue, replacementKeys.contains(name.value) { return }
      entries.append((key, value))
    }
    entries.append(contentsOf: replacements.map { (.literalName($0.0), $0.1) })
    let result = try Object.dictionary(
      uniqueKeysWithValues: entries,
      access: dictionary.access,
      vm: dictionary.vm,
      kind: .literal
    )
    try context.preflightAllocation(
      bytes: context.estimatedAllocationSize(count: entries.count, objectType: .dictionary),
      vm: dictionary.vm
    )
    try context.adopt(result)
    return result
  }

  private static func halftoneDictionary(
    _ entries: [(String, Object)],
    context: isolated Context
  ) throws -> Object {
    let object = try Object.dictionary(
      uniqueKeysWithValues: entries.map { (.literalName($0.0), $0.1) },
      access: .readOnly,
      vm: context.allocationMode,
      kind: .literal
    )
    try context.preflightAllocation(bytes: context.estimatedAllocationSize(count: entries.count, objectType: .dictionary))
    try context.adopt(object)
    return object
  }

  private static func compatibilityArray(
    _ values: [Object],
    context: isolated Context
  ) throws -> Object {
    let object = try Object.array(values, access: .readOnly, vm: context.allocationMode, kind: .literal)
    try context.preflightAllocation(bytes: context.estimatedAllocationSize(count: values.count, objectType: .array))
    try context.adopt(object)
    return object
  }

  private static func compatibilityValues(_ object: Object?) throws -> [Object]? {
    guard let object, let array = object.value as? ArrayValue else { return nil }
    return Array(try array.objects(in: array.range, for: .read))
  }

  private static func positiveInteger(_ dictionary: DictionaryValue, key: String) throws -> Int {
    try positiveInteger(dictionary.object(forKey: Object.literalName(key)))
  }

  private static func positiveInteger(_ object: Object) throws -> Int {
    let value = try object.value(as: IntegerValue.self).value
    guard value > 0 else { throw Error.rangeCheck }
    return Int(value)
  }

  private static func checkedMultiply(_ lhs: Int, _ rhs: Int) throws -> Int {
    let result = lhs.multipliedReportingOverflow(by: rhs)
    guard !result.overflow else { throw Error.limitCheck }
    return result.partialValue
  }

  private static func checkedAdd(_ lhs: Int, _ rhs: Int) throws -> Int {
    let result = lhs.addingReportingOverflow(rhs)
    guard !result.overflow else { throw Error.limitCheck }
    return result.partialValue
  }

  private static func halftoneColorantName(_ object: Object) throws -> String {
    if let name = object.value as? NameValue { return name.value }
    let string = try object.value(as: StringValue.self)
    try string.access.check(.read)
    return String(decoding: try string.characters(in: string.range), as: UTF8.self)
  }

  private static let standardProcessColorants = Set([
    "Default", "Red", "Green", "Blue", "Gray", "Cyan", "Magenta", "Yellow", "Black",
  ])

  private static func validateHalftoneName(_ dictionary: DictionaryValue) throws {
    guard let object = try dictionary.object(forKeyIfExists: "HalftoneName") else { return }
    if object.value is NameValue { return }
    let string = try object.value(as: StringValue.self)
    try string.access.check(.read)
  }

  private static func validateOptionalBoolean(_ dictionary: DictionaryValue, key: String) throws {
    guard let object = try dictionary.object(forKeyIfExists: .literalName(key)) else { return }
    _ = try object.value(as: BooleanValue.self)
  }

  private static func validateOptionalNumber(_ dictionary: DictionaryValue, key: String) throws {
    guard let object = try dictionary.object(forKeyIfExists: .literalName(key)) else { return }
    _ = try numeric(object)
  }

  private static func validateOptionalProcedure(_ dictionary: DictionaryValue, key: String) throws {
    guard let object = try dictionary.object(forKeyIfExists: .literalName(key)) else { return }
    try object.checkProcedure()
  }

  private static func validateThresholdString(_ object: Object, count: Int) throws {
    let string = try object.value(as: StringValue.self)
    try string.access.check(.read)
    guard string.count == UInt(count) else { throw Error.rangeCheck }
  }

  private static func screenCacheKey(
    _ procedure: Object,
    frequency: Double,
    angle: Double,
    transfer: GraphicsComponentFunction?,
    accurate: Bool,
    context: isolated Context
  ) -> ScreenCacheKey {
    let identity: ObjectIdentifier?
    let revision: UInt64
    if let array = procedure.value as? ArrayValue {
      identity = array.allocation.identity
      revision = array.revision
    } else if let packed = procedure.value as? PackedArrayValue {
      identity = packed.allocation.identity
      revision = packed.revision
    } else {
      identity = nil
      revision = 0
    }
    return ScreenCacheKey(
      sourceIdentity: identity,
      sourceRevision: revision,
      frequency: frequency,
      angle: angle,
      transferFunction: transfer,
      descriptor: context.graphicsDeviceDescriptor,
      accurate: accurate,
      maximumSuperScreen: context.userParameters.integer("MaxSuperScreen")
    )
  }

}
