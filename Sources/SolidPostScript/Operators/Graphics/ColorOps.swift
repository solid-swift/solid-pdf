import Foundation
import SolidColor

extension Operators {
  static let colorOps: [OperatorValue] = [
    SetColorSpace.instance,
    CurrentColorSpace.instance,
    SetColor.instance,
    CurrentColor.instance,
    SetHSBColor.instance,
    CurrentHSBColor.instance,
    SetColorRendering.instance,
    CurrentColorRendering.instance,
    FindColorRendering.instance,
    SetOverprint.instance,
    CurrentOverprint.instance,
  ]

  enum SetColorSpace: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setcolorspace"]

    func execute(context: isolated Context) async throws {
      try requireColorOperationAllowed(context)
      let object = try context.operands.pop()
      let space = try await parseColorSpace(object, context: context)
      let components = space.initialComponents
      let paint: GraphicsPaint = if case .pattern = space {
        .pattern(.empty)
      } else {
        .color(try await resolveColor(components, in: space, context: context))
      }
      try context.applyGraphicsOperation(.state(.setColorSpace(space.description))) {
        $0.colorSpace = space
        $0.colorComponents = components
        $0.patternSource = nil
        $0.paint = paint
      }
    }
  }

  enum CurrentColorSpace: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currentcolorspace"]

    func execute(context: isolated Context) async throws {
      if let source = context.graphicsState.colorSpace.source {
        context.operands.push(source)
      } else {
        let name: String = switch context.graphicsState.colorSpace {
        case .deviceGray: "DeviceGray"
        case .deviceRGB: "DeviceRGB"
        case .deviceCMYK: "DeviceCMYK"
        default: preconditionFailure("Composite color spaces retain their source array")
        }
        try context.preflightAllocation(
          bytes: context.estimatedAllocationSize(count: 1, objectType: .array)
        )
        let object = try Object.array(
          [.literalName(name)],
          access: .readOnly,
          vm: context.allocationMode,
          kind: .literal
        )
        try context.adopt(object)
        context.operands.push(object)
      }
    }
  }

  enum SetColor: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setcolor"]

    func execute(context: isolated Context) async throws {
      try requireColorOperationAllowed(context)
      if case .pattern(_, let underlying) = context.graphicsState.colorSpace {
        let count = (underlying?.componentCount ?? 0) + 1
        let values = Array(try context.operands.pop(count: count).reversed())
        let pattern = values[count - 1]
        let components = try values.dropLast().map(numeric)
        let dictionary = try pattern.value(as: DictionaryValue.self)
        let paint = try await resolvePattern(
          pattern,
          dictionary: dictionary,
          underlying: underlying,
          components: components,
          context: context
        )
        try context.applyGraphicsOperation(.state(.setColorSpace(context.graphicsState.colorSpace.description))) {
          $0.colorComponents = components
          $0.patternSource = pattern
          $0.paint = .pattern(paint)
        }
        return
      }
      let count = context.graphicsState.colorSpace.componentCount
      let rawComponents = try context.operands.pop(count: count).reversed().map(numeric)
      let components = context.graphicsState.colorSpace.normalized(rawComponents)
      let paint = try await resolveColor(components, in: context.graphicsState.colorSpace, context: context)
      try context.applyGraphicsOperation(.state(.setColor(paint))) {
        $0.colorComponents = components
        $0.patternSource = nil
        $0.paint = .color(paint)
      }
    }
  }

  enum CurrentColor: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currentcolor"]

    func execute(context: isolated Context) async throws {
      if case .pattern = context.graphicsState.colorSpace {
        context.operands.push(
          contentsOf: [context.graphicsState.patternSource ?? .null]
            + (try context.graphicsState.colorComponents.reversed().map { try Object.real($0) })
        )
        return
      }
      context.operands.push(
        contentsOf: try context.graphicsState.colorComponents.reversed().map { try Object.real($0) }
      )
    }
  }

  enum SetHSBColor: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["sethsbcolor"]

    func execute(context: isolated Context) async throws {
      try requireColorOperationAllowed(context)
      let operands = try context.operands.pop(count: 3)
      let hue = clamped(try numeric(operands[2]))
      let saturation = clamped(try numeric(operands[1]))
      let brightness = clamped(try numeric(operands[0]))
      let sector = hue * 6
      let index = Int(sector.rounded(.down)) % 6
      let fraction = sector - sector.rounded(.down)
      let low = brightness * (1 - saturation)
      let descending = brightness * (1 - saturation * fraction)
      let ascending = brightness * (1 - saturation * (1 - fraction))
      let rgb: (Double, Double, Double) = switch index {
      case 0: (brightness, ascending, low)
      case 1: (descending, brightness, low)
      case 2: (low, brightness, ascending)
      case 3: (low, descending, brightness)
      case 4: (ascending, low, brightness)
      default: (brightness, low, descending)
      }
      try setDeviceRGB(red: rgb.0, green: rgb.1, blue: rgb.2, context: context)
    }
  }

  enum CurrentHSBColor: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currenthsbcolor"]

    func execute(context: isolated Context) async throws {
      let rgb: (red: Double, green: Double, blue: Double)
      if context.graphicsState.colorSpace.isDeviceSpace {
        rgb = context.graphicsState.paint.rgbComponents
      } else {
        rgb = (0, 0, 0)
      }
      let maximum = max(rgb.red, rgb.green, rgb.blue)
      let minimum = min(rgb.red, rgb.green, rgb.blue)
      let delta = maximum - minimum
      let saturation = maximum == 0 ? 0 : delta / maximum
      let hue: Double
      if delta == 0 {
        hue = 0
      } else if maximum == rgb.red {
        hue = ((rgb.green - rgb.blue) / delta).truncatingRemainder(dividingBy: 6) / 6
      } else if maximum == rgb.green {
        hue = ((rgb.blue - rgb.red) / delta + 2) / 6
      } else {
        hue = ((rgb.red - rgb.green) / delta + 4) / 6
      }
      context.operands.push(
        try .real(maximum),
        try .real(saturation),
        try .real(hue < 0 ? hue + 1 : hue)
      )
    }
  }

  enum SetColorRendering: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setcolorrendering"]

    func execute(context: isolated Context) async throws {
      let object = try context.operands.pop()
      let dictionary = try object.value(as: DictionaryValue.self)
      try validateColorRendering(dictionary)
      try context.applyGraphicsOperation(.state(.setColorRendering)) {
        $0.colorRenderingSource = object
      }
    }
  }

  enum CurrentColorRendering: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currentcolorrendering"]

    func execute(context: isolated Context) async throws {
      if let source = context.graphicsState.colorRenderingSource {
        context.operands.push(source)
        return
      }
      let whitePoint = try Object.array(
        [try .real(ColorXYZ.d65.x), try .real(1), try .real(ColorXYZ.d65.z)],
        access: .readOnly,
        vm: context.allocationMode,
        kind: .literal
      )
      let dictionary = try Object.dictionary(
        uniqueKeysWithValues: [
          (.literalName("ColorRenderingType"), .integer(1)),
          (.literalName("WhitePoint"), whitePoint),
        ],
        access: .readOnly,
        vm: context.allocationMode,
        kind: .literal
      )
      try context.adopt(whitePoint)
      try context.adopt(dictionary)
      context.operands.push(dictionary)
    }
  }

  enum FindColorRendering: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["findcolorrendering"]

    func execute(context: isolated Context) async throws {
      let intent = try context.operands.pop()
      let intentName: String
      if let name = intent.value as? NameValue {
        intentName = name.value
      } else if let string = intent.value as? StringValue {
        try string.access.check(.read)
        intentName = String(decoding: try string.characters(in: string.range), as: UTF8.self)
      } else {
        throw Error.typeCheck
      }
      let procSet = try await ResourceRuntime.find(
        .literalName("ColorRendering"),
        in: "ProcSet",
        context: context
      ).value(as: DictionaryValue.self)
      let device = try await executeColorRenderingName(
        procSet.object(forKey: "GetPageDeviceName"),
        context: context
      )
      let halftone = try await executeColorRenderingName(
        procSet.object(forKey: "GetHalftoneName"),
        context: context
      )
      let exact = Object.literalName("\(intentName).\(device).\(halftone)")
      do {
        _ = try await ResourceRuntime.find(exact, in: "ColorRendering", context: context)
        context.operands.push(.boolean(true), exact)
      } catch Error.undefinedResource {
        let substitute = try await executeColorRenderingName(
          procSet.object(forKey: "GetSubstituteCRD"),
          operands: [intent],
          context: context
        )
        context.operands.push(.boolean(false), .literalName(substitute))
      }
    }
  }

  enum SetOverprint: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["setoverprint"]

    func execute(context: isolated Context) async throws {
      let value: BooleanValue = try context.operands.popAs()
      try context.applyGraphicsOperation(.state(.setOverprint(value.value))) { $0.overprint = value.value }
    }
  }

  enum CurrentOverprint: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["currentoverprint"]

    func execute(context: isolated Context) async throws {
      context.operands.push(.boolean(context.graphicsState.overprint))
    }
  }

  static func setDeviceRGB(
    red: Double,
    green: Double,
    blue: Double,
    context: isolated Context
  ) throws {
    try requireColorOperationAllowed(context)
    try context.applyGraphicsOperation(.state(.setRGB(red: red, green: green, blue: blue))) {
      $0.colorSpace = .deviceRGB(nil)
      $0.colorComponents = [red, green, blue]
      $0.patternSource = nil
      $0.paint = .deviceRGB(red: red, green: green, blue: blue)
    }
  }

  static func requireColorOperationAllowed(_ context: isolated Context) throws {
    guard context.uncoloredPatternExecutionDepth == 0 else { throw Error.undefined }
  }

  static func parseColorSpace(_ object: Object, context: isolated Context) async throws -> PostScriptColorSpace {
    if let name = object.value as? NameValue {
      switch name.value {
      case "DeviceGray": return .deviceGray(nil)
      case "DeviceRGB": return .deviceRGB(nil)
      case "DeviceCMYK": return .deviceCMYK(nil)
      case "Pattern": return .pattern(source: object, underlying: nil)
      default:
        let resource = try await ResourceRuntime.find(object, in: "ColorSpace", context: context)
        return try await parseColorSpace(resource, context: context)
      }
    }
    let elements = try arrayObjects(object)
    guard let familyObject = elements.first else { throw Error.rangeCheck }
    let family = try familyObject.value(as: NameValue.self).value
    switch family {
    case "DeviceGray":
      guard elements.count == 1 else { throw Error.rangeCheck }
      return .deviceGray(object)
    case "DeviceRGB":
      guard elements.count == 1 else { throw Error.rangeCheck }
      return .deviceRGB(object)
    case "DeviceCMYK":
      guard elements.count == 1 else { throw Error.rangeCheck }
      return .deviceCMYK(object)
    case "CIEBasedA", "CIEBasedABC", "CIEBasedDEF", "CIEBasedDEFG":
      guard elements.count == 2 else { throw Error.rangeCheck }
      let dictionary = try elements[1].value(as: DictionaryValue.self)
      let count = family == "CIEBasedA" ? 1 : family == "CIEBasedDEFG" ? 4 : 3
      let parameters = try cieParameters(dictionary, family: family, componentCount: count)
      return switch family {
      case "CIEBasedA": .cieA(source: object, parameters: parameters)
      case "CIEBasedABC": .cieABC(source: object, parameters: parameters)
      case "CIEBasedDEF": .cieDEF(source: object, parameters: parameters)
      default: .cieDEFG(source: object, parameters: parameters)
      }
    case "Indexed":
      guard elements.count == 4 else { throw Error.rangeCheck }
      let base = try await parseColorSpace(elements[1], context: context)
      guard isIndexedBase(base) else { throw Error.rangeCheck }
      let maximum = Int(try elements[2].value(as: IntegerValue.self).value)
      guard (0...4_095).contains(maximum) else { throw Error.rangeCheck }
      let lookup = elements[3]
      if let string = lookup.value as? StringValue {
        try string.access.check(.read)
        guard string.count >= UInt((maximum + 1) * base.componentCount) else { throw Error.rangeCheck }
      } else {
        try lookup.checkProcedure()
      }
      return .indexed(source: object, base: base, maximumIndex: maximum, lookup: lookup)
    case "Separation":
      guard elements.count == 4 else { throw Error.rangeCheck }
      let name = try elements[1].value(as: NameValue.self).value
      let alternative = try await parseColorSpace(elements[2], context: context)
      guard isRegularBase(alternative) else { throw Error.rangeCheck }
      try elements[3].checkProcedure()
      return .separation(source: object, name: name, alternative: alternative, transform: elements[3])
    case "DeviceN":
      guard elements.count == 4 || elements.count == 5 else { throw Error.rangeCheck }
      let names = try arrayObjects(elements[1]).map { try $0.value(as: NameValue.self).value }
      guard !names.isEmpty, Set(names).count == names.count else { throw Error.rangeCheck }
      let alternative = try await parseColorSpace(elements[2], context: context)
      guard isRegularBase(alternative) else { throw Error.rangeCheck }
      try elements[3].checkProcedure()
      if elements.count == 5 { _ = try elements[4].value(as: DictionaryValue.self) }
      return .deviceN(source: object, names: names, alternative: alternative, transform: elements[3])
    case "Pattern":
      guard elements.count == 1 || elements.count == 2 else { throw Error.rangeCheck }
      let underlying: PostScriptColorSpace?
      if elements.count == 2 {
        underlying = try await parseColorSpace(elements[1], context: context)
        if case .pattern = underlying { throw Error.rangeCheck }
      } else {
        underlying = nil
      }
      return .pattern(source: object, underlying: underlying)
    default:
      throw Error.rangeCheck
    }
  }

  static func resolveColor(
    _ rawComponents: [Double],
    in space: PostScriptColorSpace,
    context: isolated Context
  ) async throws -> GraphicsColorValue {
    guard rawComponents.count == space.componentCount, rawComponents.allSatisfy(\.isFinite) else {
      throw Error.typeCheck
    }
    switch space {
    case .deviceGray:
      return .deviceGray(clamped(rawComponents[0]))
    case .deviceRGB:
      return .deviceRGB(.init(
        red: clamped(rawComponents[0]),
        green: clamped(rawComponents[1]),
        blue: clamped(rawComponents[2])
      ))
    case .deviceCMYK:
      return .deviceCMYK(.init(
        cyan: clamped(rawComponents[0]),
        magenta: clamped(rawComponents[1]),
        yellow: clamped(rawComponents[2]),
        black: clamped(rawComponents[3])
      ))
    case .cieA(_, let parameters), .cieABC(_, let parameters), .cieDEF(_, let parameters),
         .cieDEFG(_, let parameters):
      let xyz = try await resolveCIE(rawComponents, parameters: parameters, context: context)
      let device = try await renderCIE(
        xyz,
        source: parameters,
        context: context
      )
      return .cie(space: space.description, source: rawComponents, xyz: xyz, device: device)
    case .indexed(_, let base, let maximum, let lookup):
      let index = min(maximum, max(0, Int(rawComponents[0].rounded())))
      let values: [Double]
      if let string = lookup.value as? StringValue {
        let data = try string.characters(in: string.range)
        let offset = index * base.componentCount
        values = data[offset..<(offset + base.componentCount)].map { Double($0) / 255 }
      } else {
        values = try await executeTransform(lookup, inputs: [Double(index)], outputs: base.componentCount, context: context)
      }
      return try await resolveColor(values, in: base, context: context)
    case .separation(_, let name, let alternative, let transform):
      let tints = rawComponents.map(clamped)
      let values = try await executeTransform(
        transform,
        inputs: tints,
        outputs: alternative.componentCount,
        context: context
      )
      let fallback = try await resolveColor(values, in: alternative, context: context)
      return .named(space: space.description, colorants: [name], tints: tints, alternative: fallback)
    case .deviceN(_, let names, let alternative, let transform):
      let tints = rawComponents.map(clamped)
      let values = try await executeTransform(
        transform,
        inputs: tints,
        outputs: alternative.componentCount,
        context: context
      )
      let fallback = try await resolveColor(values, in: alternative, context: context)
      return .named(space: space.description, colorants: names, tints: tints, alternative: fallback)
    case .pattern:
      throw Error.typeCheck
    }
  }

  static func resolveCIE(
    _ components: [Double],
    parameters: PostScriptColorSpace.CIE,
    context: isolated Context
  ) async throws -> ColorXYZ {
    let ranged = zip(components, parameters.range).map { $1.clamp($0) }
    let decoded = try await executeComponentProcedures(
      parameters.decode,
      inputs: ranged,
      context: context
    )
    let lmn: [Double]
    switch parameters.initialTransform {
    case .matrix(let matrix):
      lmn = postScriptTransform(matrix, inputs: decoded, outputs: 3)
    case .lookup(let inputRange, let table):
      let normalized: [Double] = zip(decoded, inputRange).map { component, range in
        guard range.upperBound > range.lowerBound else { return 0.0 }
        return (range.clamp(component) - range.lowerBound) / (range.upperBound - range.lowerBound)
      }
      let encodedABC: [Double]
      do {
        encodedABC = try table.interpolate(normalized)
      } catch {
        throw Error.rangeCheck
      }
      let abc = zip(encodedABC, parameters.rangeABC).map {
        $1.lowerBound + $0 * ($1.upperBound - $1.lowerBound)
      }
      let decodedABC = try await executeComponentProcedures(
        parameters.decodeABC,
        inputs: abc,
        context: context
      )
      lmn = postScriptTransform(parameters.matrixABC, inputs: decodedABC, outputs: 3)
    }
    let rangedLMN = zip(lmn, parameters.rangeLMN).map { $1.clamp($0) }
    let decodedLMN = try await executeComponentProcedures(parameters.decodeLMN, inputs: rangedLMN, context: context)
    let values = postScriptTransform(parameters.matrixLMN, inputs: decodedLMN, outputs: 3)
    let xyz = ColorXYZ(x: values[0], y: values[1], z: values[2])
    guard [xyz.x, xyz.y, xyz.z].allSatisfy(\.isFinite) else { throw Error.undefinedResult }
    return xyz
  }

  static func executeComponentProcedures(
    _ procedures: [Object],
    inputs: [Double],
    context: isolated Context
  ) async throws -> [Double] {
    guard procedures.isEmpty || procedures.count == inputs.count else { throw Error.rangeCheck }
    guard !procedures.isEmpty else { return inputs }
    var result: [Double] = []
    result.reserveCapacity(inputs.count)
    for (procedure, input) in zip(procedures, inputs) {
      result.append(try await executeTransform(procedure, inputs: [input], outputs: 1, context: context)[0])
    }
    return result
  }

  static func executeTransform(
    _ procedure: Object,
    inputs: [Double],
    outputs: Int,
    context: isolated Context
  ) async throws -> [Double] {
    let depth = context.operands.depth
    try await context.execute(proc: procedure, ops: try inputs.map { try Object.real($0) })
    guard context.operands.depth == depth + outputs else { throw Error.typeCheck }
    return try context.operands.pop(count: outputs).reversed().map(numeric)
  }

  static func cieParameters(
    _ dictionary: DictionaryValue,
    family: String,
    componentCount: Int
  ) throws -> PostScriptColorSpace.CIE {
    let white = try numericArray(dictionary.object(forKey: "WhitePoint"), count: 3)
    guard white[0] > 0, white[1] == 1, white[2] > 0 else { throw Error.rangeCheck }
    let black = try dictionary.object(forKeyIfExists: "BlackPoint").map {
      try numericArray($0, count: 3)
    } ?? [0, 0, 0]
    guard black.allSatisfy({ $0 >= 0 }) else { throw Error.rangeCheck }
    let rangeName = family == "CIEBasedA" ? "RangeA" : family == "CIEBasedDEFG" ? "RangeDEFG"
      : family == "CIEBasedDEF" ? "RangeDEF" : "RangeABC"
    let rangeValues = try dictionary.object(forKeyIfExists: Object.literalName(rangeName)).map {
      try numericArray($0, count: componentCount * 2)
    } ?? Array(repeating: [0.0, 1.0], count: componentCount).flatMap { $0 }
    let ranges = try componentRanges(rangeValues)
    let decodeName = family == "CIEBasedA" ? "DecodeA" : family == "CIEBasedDEFG" ? "DecodeDEFG"
      : family == "CIEBasedDEF" ? "DecodeDEF" : "DecodeABC"
    let decode: [Object] = try dictionary.object(forKeyIfExists: Object.literalName(decodeName)).map {
      if componentCount == 1 {
        try $0.checkProcedure()
        return [$0]
      }
      return try procedureArray($0, count: componentCount)
    } ?? []
    let matrixName = family == "CIEBasedA" ? "MatrixA" : family == "CIEBasedDEFG" ? "MatrixDEFG"
      : family == "CIEBasedDEF" ? "MatrixDEF" : "MatrixABC"
    let rangeABC = try componentRanges(
      dictionary.object(forKeyIfExists: "RangeABC").map { try numericArray($0, count: 6) }
        ?? [0, 1, 0, 1, 0, 1]
    )
    let decodeABC = try dictionary.object(forKeyIfExists: "DecodeABC").map {
      try procedureArray($0, count: 3)
    } ?? []
    let matrixABC = try dictionary.object(forKeyIfExists: "MatrixABC").map {
      try numericArray($0, count: 9)
    } ?? [1, 0, 0, 0, 1, 0, 0, 0, 1]
    let initialTransform: PostScriptColorSpace.CIE.InitialTransform
    if family == "CIEBasedDEF" || family == "CIEBasedDEFG" {
      let intermediateName = family == "CIEBasedDEF" ? "RangeHIJ" : "RangeHIJK"
      let intermediate = try componentRanges(
        dictionary.object(forKeyIfExists: Object.literalName(intermediateName)).map {
          try numericArray($0, count: componentCount * 2)
        } ?? Array(repeating: [0.0, 1.0], count: componentCount).flatMap { $0 }
      )
      let table = try cieLookupTable(
        dictionary.object(forKey: "Table"),
        dimensions: componentCount
      )
      initialTransform = .lookup(inputRange: intermediate, table: table)
    } else {
      let defaultMatrix: [Double] = componentCount == 1
        ? [1, 1, 1]
        : [1, 0, 0, 0, 1, 0, 0, 0, 1]
      let matrix: [Double]
      if let object = try dictionary.object(forKeyIfExists: Object.literalName(matrixName)) {
        matrix = try numericArray(object, count: componentCount * 3)
      } else {
        matrix = defaultMatrix
      }
      initialTransform = .matrix(matrix)
    }
    let rangeLMN = try componentRanges(
      dictionary.object(forKeyIfExists: "RangeLMN").map { try numericArray($0, count: 6) }
        ?? [0, 1, 0, 1, 0, 1]
    )
    let decodeLMN = try dictionary.object(forKeyIfExists: "DecodeLMN").map {
      try procedureArray($0, count: 3)
    } ?? []
    let matrixLMN = try dictionary.object(forKeyIfExists: "MatrixLMN").map {
      try numericArray($0, count: 9)
    } ?? [1, 0, 0, 0, 1, 0, 0, 0, 1]
    return .init(
      whitePoint: .init(x: white[0], y: white[1], z: white[2]),
      blackPoint: .init(x: black[0], y: black[1], z: black[2]),
      range: ranges,
      decode: decode,
      initialTransform: initialTransform,
      rangeABC: rangeABC,
      decodeABC: decodeABC,
      matrixABC: matrixABC,
      rangeLMN: rangeLMN,
      decodeLMN: decodeLMN,
      matrixLMN: matrixLMN
    )
  }

  static func componentRanges(_ values: [Double]) throws -> [ColorComponentRange] {
    do {
      return try stride(from: 0, to: values.count, by: 2).map {
        try ColorComponentRange(values[$0], values[$0 + 1])
      }
    } catch {
      throw Error.rangeCheck
    }
  }

  static func cieLookupTable(_ object: Object, dimensions: Int) throws -> ColorLookupTable {
    let values = try arrayObjects(object)
    guard values.count == dimensions + 1 else { throw Error.rangeCheck }
    let sizes = try values.prefix(dimensions).map {
      Int(try $0.value(as: IntegerValue.self).value)
    }
    guard sizes.allSatisfy({ $0 > 1 }) else { throw Error.rangeCheck }
    let outer = try arrayObjects(values[dimensions])
    guard outer.count == sizes[0] else { throw Error.rangeCheck }
    var bytes: [Double] = []
    if dimensions == 3 {
      let stringLength = 3 * sizes[1] * sizes[2]
      for object in outer {
        let string = try object.value(as: StringValue.self)
        try string.access.check(.read)
        let data = try string.characters(in: string.range)
        guard data.count == stringLength else { throw Error.rangeCheck }
        bytes.append(contentsOf: data.map { Double($0) / 255 })
      }
    } else {
      let stringLength = 3 * sizes[2] * sizes[3]
      for row in outer {
        let strings = try arrayObjects(row)
        guard strings.count == sizes[1] else { throw Error.rangeCheck }
        for object in strings {
          let string = try object.value(as: StringValue.self)
          try string.access.check(.read)
          let data = try string.characters(in: string.range)
          guard data.count == stringLength else { throw Error.rangeCheck }
          bytes.append(contentsOf: data.map { Double($0) / 255 })
        }
      }
    }
    do {
      return try ColorLookupTable(dimensions: sizes, outputComponentCount: 3, values: bytes)
    } catch {
      throw Error.limitCheck
    }
  }

  static func postScriptTransform(_ matrix: [Double], inputs: [Double], outputs: Int) -> [Double] {
    (0..<outputs).map { output in
      inputs.indices.reduce(0) { result, input in
        result + inputs[input] * matrix[input * outputs + output]
      }
    }
  }

  static func validateColorRendering(_ dictionary: DictionaryValue) throws {
    _ = try colorRenderingParameters(dictionary)
  }

  private static func executeColorRenderingName(
    _ procedure: Object,
    operands: [Object] = [],
    context: isolated Context
  ) async throws -> String {
    try procedure.checkProcedure()
    let depth = context.operands.depth
    try await context.execute(proc: procedure, ops: operands)
    guard context.operands.depth == depth + 1 else { throw Error.typeCheck }
    let result = try context.operands.pop()
    if let name = result.value as? NameValue { return name.value }
    let string = try result.value(as: StringValue.self)
    try string.access.check(.read)
    return String(decoding: try string.characters(in: string.range), as: UTF8.self)
  }

  struct ColorRenderingParameters {
    struct RenderTable {
      let lookup: ColorLookupTable
      let transforms: [Object]
    }

    let matrixLMN: [Double]
    let encodeLMN: [Object]
    let rangeLMN: [ColorComponentRange]
    let matrixABC: [Double]
    let encodeABC: [Object]
    let rangeABC: [ColorComponentRange]
    let whitePoint: ColorXYZ
    let blackPoint: ColorXYZ
    let matrixPQR: [Double]
    let transformPQR: [Object]
    let renderTable: RenderTable?
  }

  static func renderCIE(
    _ sourceXYZ: ColorXYZ,
    source: PostScriptColorSpace.CIE,
    context: isolated Context
  ) async throws -> GraphicsColorValue? {
    guard let object = context.graphicsState.colorRenderingSource else { return nil }
    let parameters = try colorRenderingParameters(object.value(as: DictionaryValue.self))
    var xyz = sourceXYZ
    if source.whitePoint != parameters.whitePoint || source.blackPoint != parameters.blackPoint {
      let sourcePQR = postScriptTransform(
        parameters.matrixPQR,
        inputs: [xyz.x, xyz.y, xyz.z],
        outputs: 3
      )
      let sourceWhite = postScriptTransform(
        parameters.matrixPQR,
        inputs: [source.whitePoint.x, source.whitePoint.y, source.whitePoint.z],
        outputs: 3
      )
      let sourceBlack = postScriptTransform(
        parameters.matrixPQR,
        inputs: [source.blackPoint.x, source.blackPoint.y, source.blackPoint.z],
        outputs: 3
      )
      let destinationWhite = postScriptTransform(
        parameters.matrixPQR,
        inputs: [parameters.whitePoint.x, parameters.whitePoint.y, parameters.whitePoint.z],
        outputs: 3
      )
      let destinationBlack = postScriptTransform(
        parameters.matrixPQR,
        inputs: [parameters.blackPoint.x, parameters.blackPoint.y, parameters.blackPoint.z],
        outputs: 3
      )
      let sourceWhiteObject = try pointObject(source.whitePoint, pqr: sourceWhite, context: context)
      let sourceBlackObject = try pointObject(source.blackPoint, pqr: sourceBlack, context: context)
      let destinationWhiteObject = try pointObject(
        parameters.whitePoint,
        pqr: destinationWhite,
        context: context
      )
      let destinationBlackObject = try pointObject(
        parameters.blackPoint,
        pqr: destinationBlack,
        context: context
      )
      var destinationPQR: [Double] = []
      destinationPQR.reserveCapacity(3)
      for index in 0..<3 {
        destinationPQR.append(try await executeProcedure(
          parameters.transformPQR[index],
          inputs: [
            try .real(sourcePQR[index]),
            destinationBlackObject,
            destinationWhiteObject,
            sourceBlackObject,
            sourceWhiteObject,
          ],
          outputs: 1,
          context: context
        )[0])
      }
      guard let inverse = postScriptMatrix(parameters.matrixPQR).inverted else {
        throw Error.undefinedResult
      }
      xyz = inverse.transform(.init(
        x: destinationPQR[0],
        y: destinationPQR[1],
        z: destinationPQR[2]
      ))
    }

    var lmn = postScriptTransform(
      parameters.matrixLMN,
      inputs: [xyz.x, xyz.y, xyz.z],
      outputs: 3
    )
    lmn = try await executeComponentProcedures(parameters.encodeLMN, inputs: lmn, context: context)
    lmn = zip(lmn, parameters.rangeLMN).map { $1.clamp($0) }
    var abc = postScriptTransform(parameters.matrixABC, inputs: lmn, outputs: 3)
    abc = try await executeComponentProcedures(parameters.encodeABC, inputs: abc, context: context)
    abc = zip(abc, parameters.rangeABC).map { $1.clamp($0) }
    guard let table = parameters.renderTable else {
      if context.graphicsDeviceDescriptor.colorDevice.processModel == .gray {
        return .deviceGray(clamped(abc[0]))
      }
      return .deviceRGB(.init(red: clamped(abc[0]), green: clamped(abc[1]), blue: clamped(abc[2])))
    }
    let normalized = zip(abc, parameters.rangeABC).map { component, range in
      range.upperBound == range.lowerBound
        ? 0
        : (component - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
    let encoded: [Double]
    do {
      encoded = try table.lookup.interpolate(normalized)
    } catch {
      throw Error.rangeCheck
    }
    var device: [Double] = []
    for (procedure, component) in zip(table.transforms, encoded) {
      device.append(try await executeTransform(
        procedure,
        inputs: [component],
        outputs: 1,
        context: context
      )[0])
    }
    if device.count == 3 {
      return .deviceRGB(.init(red: clamped(device[0]), green: clamped(device[1]), blue: clamped(device[2])))
    }
    return .deviceCMYK(.init(
      cyan: clamped(device[0]),
      magenta: clamped(device[1]),
      yellow: clamped(device[2]),
      black: clamped(device[3])
    ))
  }

  static func colorRenderingParameters(_ dictionary: DictionaryValue) throws -> ColorRenderingParameters {
    let type = try dictionary.objectValue(forKey: "ColorRenderingType", as: IntegerValue.self).value
    guard type == 1 else { throw Error.rangeCheck }
    let white = try numericArray(dictionary.object(forKey: "WhitePoint"), count: 3)
    guard white[0] > 0, white[1] == 1, white[2] > 0 else { throw Error.rangeCheck }
    let black = try dictionary.object(forKeyIfExists: "BlackPoint").map {
      try numericArray($0, count: 3)
    } ?? [0, 0, 0]
    guard black.allSatisfy({ $0 >= 0 }) else { throw Error.rangeCheck }
    func matrix(_ name: String) throws -> [Double] {
      try dictionary.object(forKeyIfExists: Object.literalName(name)).map {
        try numericArray($0, count: 9)
      } ?? [1, 0, 0, 0, 1, 0, 0, 0, 1]
    }
    func procedures(_ name: String, required: Bool = false) throws -> [Object] {
      guard let object = try dictionary.object(forKeyIfExists: Object.literalName(name)) else {
        if required { throw Error.undefined }
        return []
      }
      return try procedureArray(object, count: 3)
    }
    func ranges(_ name: String) throws -> [ColorComponentRange] {
      try componentRanges(
        dictionary.object(forKeyIfExists: Object.literalName(name)).map {
          try numericArray($0, count: 6)
        } ?? [0, 1, 0, 1, 0, 1]
      )
    }
    let rangeABC = try ranges("RangeABC")
    let renderTable = try dictionary.object(forKeyIfExists: "RenderTable").map(parseRenderTable)
    if renderTable == nil,
      rangeABC.contains(where: { $0.lowerBound < 0 || $0.upperBound > 1 })
    {
      throw Error.rangeCheck
    }
    return .init(
      matrixLMN: try matrix("MatrixLMN"),
      encodeLMN: try procedures("EncodeLMN"),
      rangeLMN: try ranges("RangeLMN"),
      matrixABC: try matrix("MatrixABC"),
      encodeABC: try procedures("EncodeABC"),
      rangeABC: rangeABC,
      whitePoint: .init(x: white[0], y: white[1], z: white[2]),
      blackPoint: .init(x: black[0], y: black[1], z: black[2]),
      matrixPQR: try matrix("MatrixPQR"),
      transformPQR: try procedures("TransformPQR", required: true),
      renderTable: renderTable
    )
  }

  static func parseRenderTable(_ object: Object) throws -> ColorRenderingParameters.RenderTable {
    let elements = try arrayObjects(object)
    guard elements.count >= 8 else { throw Error.rangeCheck }
    let dimensions = try elements.prefix(3).map {
      Int(try $0.value(as: IntegerValue.self).value)
    }
    guard dimensions.allSatisfy({ $0 > 1 }) else { throw Error.rangeCheck }
    let outputCount = Int(try elements[4].value(as: IntegerValue.self).value)
    guard outputCount == 3 || outputCount == 4, elements.count == 5 + outputCount else {
      throw Error.rangeCheck
    }
    let rows = try arrayObjects(elements[3])
    guard rows.count == dimensions[0] else { throw Error.rangeCheck }
    let expected = outputCount * dimensions[1] * dimensions[2]
    var values: [Double] = []
    for object in rows {
      let string = try object.value(as: StringValue.self)
      try string.access.check(.read)
      let data = try string.characters(in: string.range)
      guard data.count == expected else { throw Error.rangeCheck }
      values.append(contentsOf: data.map { Double($0) / 255 })
    }
    let lookup: ColorLookupTable
    do {
      lookup = try .init(dimensions: dimensions, outputComponentCount: outputCount, values: values)
    } catch {
      throw Error.limitCheck
    }
    let transforms = Array(elements.suffix(outputCount))
    try transforms.forEach { try $0.checkProcedure() }
    return .init(lookup: lookup, transforms: transforms)
  }

  static func pointObject(
    _ xyz: ColorXYZ,
    pqr: [Double],
    context: isolated Context
  ) throws -> Object {
    let object = try Object.array(
      [
        try .real(xyz.x), try .real(xyz.y), try .real(xyz.z),
        try .real(pqr[0]), try .real(pqr[1]), try .real(pqr[2]),
      ],
      access: .readOnly,
      vm: context.allocationMode,
      kind: .literal
    )
    try context.preflightAllocation(bytes: context.estimatedAllocationSize(count: 6, objectType: .array))
    try context.adopt(object)
    return object
  }

  static func executeProcedure(
    _ procedure: Object,
    inputs: [Object],
    outputs: Int,
    context: isolated Context
  ) async throws -> [Double] {
    let depth = context.operands.depth
    try await context.execute(proc: procedure, ops: inputs)
    guard context.operands.depth == depth + outputs else { throw Error.typeCheck }
    return try context.operands.pop(count: outputs).reversed().map(numeric)
  }

  static func postScriptMatrix(_ matrix: [Double]) -> ColorMatrix3x3 {
    try! ColorMatrix3x3([
      matrix[0], matrix[3], matrix[6],
      matrix[1], matrix[4], matrix[7],
      matrix[2], matrix[5], matrix[8],
    ])
  }

  static func arrayObjects(_ object: Object) throws -> [Object] {
    if let array = object.value as? ArrayValue {
      return Array(try array.objects(in: array.range, for: .read))
    }
    if let array = object.value as? PackedArrayValue {
      return Array(try array.objects(in: array.range, for: .read))
    }
    throw Error.typeCheck
  }

  static func numericArray(_ object: Object, count: Int) throws -> [Double] {
    let values = try arrayObjects(object)
    guard values.count == count else { throw Error.rangeCheck }
    return try values.map(numeric)
  }

  static func procedureArray(_ object: Object, count: Int) throws -> [Object] {
    let values = try arrayObjects(object)
    guard values.count == count else { throw Error.rangeCheck }
    try values.forEach { try $0.checkProcedure() }
    return values
  }

  static func isRegularBase(_ space: PostScriptColorSpace) -> Bool {
    switch space {
    case .deviceGray, .deviceRGB, .deviceCMYK, .cieA, .cieABC, .cieDEF, .cieDEFG: true
    default: false
    }
  }

  static func isIndexedBase(_ space: PostScriptColorSpace) -> Bool {
    if case .indexed = space { return false }
    return true
  }
}

extension PostScriptColorSpace {
  var isDeviceSpace: Bool {
    switch self {
    case .deviceGray, .deviceRGB, .deviceCMYK: true
    default: false
    }
  }
}
