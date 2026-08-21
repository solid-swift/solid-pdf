import Foundation

extension Operators {

  static let imageOps: [OperatorValue] = [
    PaintImage.instance,
    PaintImageMask.instance,
    PaintColorImage.instance,
  ]

  enum PaintImage: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["image"]

    func execute(context: isolated Context) async throws {
      guard context.uncoloredPatternExecutionDepth == 0,
        context.imageDataSourceCallbackDepth == 0,
        context.activeGlyphBuild?.metricsMode != .cacheDevice
      else { throw Error.undefined }
      let specification: ImageSpecification
      if let dictionary = try? context.operands.peek().value(as: DictionaryValue.self) {
        _ = try context.operands.pop()
        specification = try imageDictionary(dictionary, mask: false, context: context)
      } else {
        specification = try await separateImageOperands(context: context)
      }
      try await paintImage(specification, context: context)
    }
  }

  enum PaintImageMask: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["imagemask"]

    func execute(context: isolated Context) async throws {
      guard context.imageDataSourceCallbackDepth == 0 else { throw Error.undefined }
      let specification: ImageSpecification
      if let dictionary = try? context.operands.peek().value(as: DictionaryValue.self) {
        _ = try context.operands.pop()
        specification = try imageDictionary(dictionary, mask: true, context: context)
      } else {
        let operands = try context.operands.pop(count: 5)
        let source = try ImageDataSource(operands[0])
        let matrix = try readMatrix(operands[1])
        let polarity = try operands[2].value(as: BooleanValue.self).value
        let height = Int(try operands[3].value(as: IntegerValue.self).value)
        let width = Int(try operands[4].value(as: IntegerValue.self).value)
        specification = try ImageSpecification(
          width: width,
          height: height,
          bitsPerComponent: 1,
          imageMatrix: matrix,
          kind: .mask(context.graphicsState.paint),
          decode: polarity ? [0, 1] : [1, 0],
          interpolate: false,
          sources: [source],
          multipleDataSources: false
        )
      }
      try await paintImage(specification, context: context)
    }
  }

  enum PaintColorImage: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["colorimage"]

    func execute(context: isolated Context) async throws {
      guard context.uncoloredPatternExecutionDepth == 0,
        context.imageDataSourceCallbackDepth == 0,
        context.activeGlyphBuild?.metricsMode != .cacheDevice
      else { throw Error.undefined }
      let componentCount = Int(try context.operands.pop().value(as: IntegerValue.self).value)
      guard let colorSpace = GraphicsImageColorSpace(rawValue: componentCount) else { throw Error.rangeCheck }
      let multiple = try context.operands.pop().value(as: BooleanValue.self).value
      let sourceCount = multiple ? componentCount : 1
      let sources = try context.operands.pop(count: sourceCount).reversed().map(ImageDataSource.init)
      let matrix = try readMatrix(context.operands.pop())
      let bits = Int(try context.operands.pop().value(as: IntegerValue.self).value)
      let height = Int(try context.operands.pop().value(as: IntegerValue.self).value)
      let width = Int(try context.operands.pop().value(as: IntegerValue.self).value)
      try validateSameSourceTypes(sources)
      let decode = Array(repeating: [0.0, 1.0], count: componentCount).flatMap { $0 }
      let sourceColorSpace: PostScriptColorSpace = switch colorSpace {
      case .deviceGray: .deviceGray(nil)
      case .deviceRGB: .deviceRGB(nil)
      case .deviceCMYK: .deviceCMYK(nil)
      }
      let selection = try await selectColorSpace(sourceColorSpace, context: context)
      try await paintImage(
        ImageSpecification(
          width: width,
          height: height,
          bitsPerComponent: bits,
          imageMatrix: matrix,
          kind: selection.hasIdentityDeviceRoute ? .color(colorSpace) : .color(.deviceRGB),
          sourceColorSpace: sourceColorSpace,
          colorSelection: selection.hasIdentityDeviceRoute ? nil : selection,
          decode: decode,
          interpolate: false,
          sources: sources,
          multipleDataSources: multiple
        ),
        context: context
      )
    }
  }

  struct ImageSpecification {
    let width: Int
    let height: Int
    let bitsPerComponent: Int
    let imageMatrix: GraphicsMatrix
    let kind: GraphicsImageKind
    let sourceColorSpace: PostScriptColorSpace?
    let colorSelection: PostScriptColorSelection?
    let decode: [Double]
    let interpolate: Bool
    var sources: [ImageDataSource]
    let multipleDataSources: Bool
    let dictionaries: [DictionaryValue]
    var mask: ImageMaskSpecification?

    init(
      width: Int,
      height: Int,
      bitsPerComponent: Int,
      imageMatrix: GraphicsMatrix,
      kind: GraphicsImageKind,
      sourceColorSpace: PostScriptColorSpace? = nil,
      colorSelection: PostScriptColorSelection? = nil,
      decode: [Double],
      interpolate: Bool,
      sources: [ImageDataSource],
      multipleDataSources: Bool,
      dictionaries: [DictionaryValue] = [],
      mask: ImageMaskSpecification? = nil
    ) throws {
      guard width >= 0, height >= 0 else { throw Error.rangeCheck }
      guard [1, 2, 4, 8, 12].contains(bitsPerComponent) else { throw Error.rangeCheck }
      guard imageMatrix.inverted != nil else { throw Error.undefinedResult }
      let sourceComponentCount = sourceColorSpace?.componentCount ?? kind.componentCount
      guard decode.count == sourceComponentCount * 2 else { throw Error.rangeCheck }
      guard sources.count == (multipleDataSources ? sourceComponentCount : 1) else { throw Error.rangeCheck }
      let (samplesPerRow, samplesOverflow) = width.multipliedReportingOverflow(by: sourceComponentCount)
      let (bitsPerRow, bitsOverflow) = samplesPerRow.multipliedReportingOverflow(by: bitsPerComponent)
      guard !samplesOverflow, !bitsOverflow, bitsPerRow <= LanguageLimits.maximumImageRowBytes * 8 else {
        throw Error.limitCheck
      }
      self.width = width
      self.height = height
      self.bitsPerComponent = bitsPerComponent
      self.imageMatrix = imageMatrix
      self.kind = kind
      self.sourceColorSpace = sourceColorSpace
      self.colorSelection = colorSelection
      self.decode = decode
      self.interpolate = interpolate
      self.sources = sources
      self.multipleDataSources = multipleDataSources
      self.dictionaries = dictionaries
      self.mask = mask
    }

    var sourceComponentCount: Int { sourceColorSpace?.componentCount ?? kind.componentCount }
  }

  enum ImageMaskSpecification {
    case explicit(ExplicitImageMaskSpecification)
    case colorKey([GraphicsImageSampleRange])

    var sourceType: GraphicsImageSourceType {
      switch self {
      case .explicit: .explicitMask
      case .colorKey: .colorKeyMask
      }
    }

    func descriptor(imageToDevice _: GraphicsMatrix) -> GraphicsImageMaskDescriptor {
      switch self {
      case .explicit(let mask):
        return .explicit(
          width: mask.width,
          height: mask.height,
          maskToDevice: mask.maskToDevice,
          interpolate: mask.interpolate
        )
      case .colorKey(let ranges):
        return .colorKey(ranges: ranges)
      }
    }
  }

  final class ExplicitImageMaskSpecification {
    let width: Int
    let height: Int
    let bitsPerComponent: Int
    let imageMatrix: GraphicsMatrix
    let maskToDevice: GraphicsMatrix
    let decode: [Double]
    let interpolate: Bool
    var sources: [ImageDataSource]
    let interleaveType: Int

    init(
      width: Int,
      height: Int,
      bitsPerComponent: Int,
      imageMatrix: GraphicsMatrix,
      maskToDevice: GraphicsMatrix,
      decode: [Double],
      interpolate: Bool,
      sources: [ImageDataSource],
      interleaveType: Int
    ) {
      self.width = width
      self.height = height
      self.bitsPerComponent = bitsPerComponent
      self.imageMatrix = imageMatrix
      self.maskToDevice = maskToDevice
      self.decode = decode
      self.interpolate = interpolate
      self.sources = sources
      self.interleaveType = interleaveType
    }
  }

  struct ImageDataSource {
    enum Kind: Equatable {
      case string
      case file
      case procedure
    }

    let object: Object
    let kind: Kind
    var buffered = Data()

    init(_ object: Object) throws {
      self.object = object
      switch object.value {
      case let string as StringValue:
        try string.access.check(.read)
        self.kind = .string
      case let file as FileValue:
        try file.checkReadable()
        self.kind = .file
      default:
        try object.checkProcedure()
        self.kind = .procedure
      }
    }

    mutating func read(count: Int, context: isolated Context) async throws -> Data? {
      while buffered.count < count {
        guard try await appendNext(max: count - buffered.count, context: context) != nil else {
          return nil
        }
      }
      return consume(count: count)
    }

    mutating func appendNext(max: Int, context: isolated Context) async throws -> Int? {
      guard let chunk = try await nextChunk(max: max, context: context), !chunk.isEmpty else { return nil }
      buffered.append(chunk)
      return chunk.count
    }

    mutating func consume(count: Int) -> Data {
      let result = Data(buffered.prefix(count))
      buffered.removeFirst(count)
      return result
    }

    private mutating func nextChunk(max: Int, context: isolated Context) async throws -> Data? {
      switch kind {
      case .string:
        let string = try object.value(as: StringValue.self)
        return try string.characters(in: string.range)
      case .file:
        let file = try object.value(as: FileValue.self)
        return try await context.read(max: max, from: file.file)
      case .procedure:
        let originalDepth = context.operands.depth
        try await context.executeImageDataSource(object)
        guard context.operands.depth == originalDepth + 1 else { throw Error.typeCheck }
        let string: StringValue = try context.operands.popAs()
        try string.access.check(.read)
        return try string.characters(in: string.range)
      }
    }
  }

  static func separateImageOperands(context: isolated Context) async throws -> ImageSpecification {
    let source = try ImageDataSource(context.operands.pop())
    let matrix = try readMatrix(context.operands.pop())
    let bits = Int(try context.operands.pop().value(as: IntegerValue.self).value)
    let height = Int(try context.operands.pop().value(as: IntegerValue.self).value)
    let width = Int(try context.operands.pop().value(as: IntegerValue.self).value)
    let sourceColorSpace = PostScriptColorSpace.deviceGray(nil)
    let selection = try await selectColorSpace(sourceColorSpace, context: context)
    return try ImageSpecification(
      width: width,
      height: height,
      bitsPerComponent: bits,
      imageMatrix: matrix,
      kind: selection.hasIdentityDeviceRoute ? .color(.deviceGray) : .color(.deviceRGB),
      sourceColorSpace: sourceColorSpace,
      colorSelection: selection.hasIdentityDeviceRoute ? nil : selection,
      decode: [0, 1],
      interpolate: false,
      sources: [source],
      multipleDataSources: false
    )
  }

  static func imageDictionary(
    _ dictionary: DictionaryValue,
    mask: Bool,
    context: isolated Context
  ) throws -> ImageSpecification {
    let type = try dictionary.objectValue(forKey: "ImageType", as: IntegerValue.self).value
    switch type {
    case 1:
      return try imageTypeOneDictionary(dictionary, mask: mask, context: context)
    case 3:
      guard !mask else { throw Error.rangeCheck }
      return try imageTypeThreeDictionary(dictionary, context: context)
    case 4:
      guard !mask else { throw Error.rangeCheck }
      return try imageTypeFourDictionary(dictionary, context: context)
    default:
      throw Error.rangeCheck
    }
  }

  static func imageTypeOneDictionary(
    _ dictionary: DictionaryValue,
    mask: Bool,
    declaredType: Int32 = 1,
    dictionaries: [DictionaryValue]? = nil,
    context: isolated Context
  ) throws -> ImageSpecification {
    let type = try dictionary.objectValue(forKey: "ImageType", as: IntegerValue.self).value
    guard type == declaredType else { throw Error.rangeCheck }
    let width = Int(try dictionary.objectValue(forKey: "Width", as: IntegerValue.self).value)
    let height = Int(try dictionary.objectValue(forKey: "Height", as: IntegerValue.self).value)
    let bits = Int(try dictionary.objectValue(forKey: "BitsPerComponent", as: IntegerValue.self).value)
    let matrix = try readMatrix(dictionary.object(forKey: "ImageMatrix"))
    let multiple = try dictionary.objectValue(forKeyIfExists: "MultipleDataSources", as: BooleanValue.self)?.value
      ?? false
    let interpolate = try dictionary.objectValue(forKeyIfExists: "Interpolate", as: BooleanValue.self)?.value
      ?? false
    let kind: GraphicsImageKind
    let sourceColorSpace: PostScriptColorSpace?
    let colorSelection: PostScriptColorSelection?
    if mask {
      kind = .mask(context.graphicsState.paint)
      sourceColorSpace = nil
      colorSelection = nil
    } else {
      if case .pattern = context.graphicsState.colorSpace { throw Error.undefined }
      let selection = context.graphicsState.colorSelection
      sourceColorSpace = selection.source
      colorSelection = selection.hasIdentityDeviceRoute ? nil : selection
      switch selection.source {
      case .deviceGray:
        kind = selection.hasIdentityDeviceRoute ? .color(.deviceGray) : .color(.deviceRGB)
      case .deviceRGB:
        kind = .color(.deviceRGB)
      case .deviceCMYK:
        kind = selection.hasIdentityDeviceRoute ? .color(.deviceCMYK) : .color(.deviceRGB)
      default:
        kind = .color(.deviceRGB)
      }
    }
    guard !mask || (!multiple && bits == 1) else { throw Error.rangeCheck }
    let decodeArray = try dictionary.object(forKey: "Decode").value(as: ArrayValue.self)
    let decode = try decodeArray.objects(in: decodeArray.range).map(numeric)
    if mask, decode != [0, 1], decode != [1, 0] { throw Error.rangeCheck }

    let sourceObject = try dictionary.object(forKey: "DataSource")
    let sources: [ImageDataSource]
    if multiple {
      let array = try sourceObject.value(as: ArrayValue.self)
      sources = try array.objects(in: array.range).map(ImageDataSource.init)
      try validateSameSourceTypes(sources)
    } else {
      sources = [try ImageDataSource(sourceObject)]
    }
    return try ImageSpecification(
      width: width,
      height: height,
      bitsPerComponent: bits,
      imageMatrix: matrix,
      kind: kind,
      sourceColorSpace: sourceColorSpace,
      colorSelection: colorSelection,
      decode: decode,
      interpolate: interpolate,
      sources: sources,
      multipleDataSources: multiple,
      dictionaries: dictionaries ?? [dictionary]
    )
  }

  static func imageTypeFourDictionary(
    _ dictionary: DictionaryValue,
    context: isolated Context
  ) throws -> ImageSpecification {
    var specification = try imageTypeOneDictionary(
      dictionary,
      mask: false,
      declaredType: 4,
      context: context
    )
    let array = try dictionary.object(forKey: "MaskColor").value(as: ArrayValue.self)
    let values = try array.objects(in: array.range).map { object -> Int in
      Int(try object.value(as: IntegerValue.self).value)
    }
    let componentCount = specification.sourceComponentCount
    guard values.count == componentCount || values.count == componentCount * 2 else {
      throw Error.rangeCheck
    }
    let maximum = (1 << specification.bitsPerComponent) - 1
    var ranges: [GraphicsImageSampleRange] = []
    ranges.reserveCapacity(componentCount)
    if values.count == componentCount {
      for value in values {
        guard value >= 0, value <= maximum else { throw Error.rangeCheck }
        ranges.append(.init(lowerBound: UInt16(value), upperBound: UInt16(value)))
      }
    } else {
      for component in 0..<componentCount {
        let lower = values[component * 2]
        let upper = values[component * 2 + 1]
        guard lower >= 0, lower <= upper, upper <= maximum else { throw Error.rangeCheck }
        ranges.append(.init(lowerBound: UInt16(lower), upperBound: UInt16(upper)))
      }
    }
    specification.mask = .colorKey(ranges)
    return specification
  }

  static func imageTypeThreeDictionary(
    _ dictionary: DictionaryValue,
    context: isolated Context
  ) throws -> ImageSpecification {
    let dataDictionary = try dictionary.object(forKey: "DataDict").value(as: DictionaryValue.self)
    let maskDictionary = try dictionary.object(forKey: "MaskDict").value(as: DictionaryValue.self)
    let interleaveType = Int(try dictionary.objectValue(forKey: "InterleaveType", as: IntegerValue.self).value)
    guard (1...3).contains(interleaveType) else { throw Error.rangeCheck }
    var specification = try imageTypeOneDictionary(
      dataDictionary,
      mask: false,
      dictionaries: [dictionary, dataDictionary, maskDictionary],
      context: context
    )
    guard interleaveType == 3 || !specification.multipleDataSources else { throw Error.typeCheck }

    let width = Int(try maskDictionary.objectValue(forKey: "Width", as: IntegerValue.self).value)
    let height = Int(try maskDictionary.objectValue(forKey: "Height", as: IntegerValue.self).value)
    let bits = Int(try maskDictionary.objectValue(forKey: "BitsPerComponent", as: IntegerValue.self).value)
    let matrix = try readMatrix(maskDictionary.object(forKey: "ImageMatrix"))
    let multiple = try maskDictionary.objectValue(
      forKeyIfExists: "MultipleDataSources",
      as: BooleanValue.self
    )?.value ?? false
    guard !multiple, width >= 0, height >= 0, [1, 2, 4, 8, 12].contains(bits), matrix.inverted != nil else {
      throw Error.typeCheck
    }
    let decodeArray = try maskDictionary.object(forKey: "Decode").value(as: ArrayValue.self)
    let decode = try decodeArray.objects(in: decodeArray.range).map(numeric)
    guard decode.count == 2 else { throw Error.rangeCheck }
    let interpolate = try maskDictionary.objectValue(
      forKeyIfExists: "Interpolate",
      as: BooleanValue.self
    )?.value ?? false

    let sources: [ImageDataSource]
    if interleaveType == 3 {
      sources = [try ImageDataSource(maskDictionary.object(forKey: "DataSource"))]
    } else {
      guard try maskDictionary.object(forKeyIfExists: "DataSource") == nil else { throw Error.typeCheck }
      sources = []
    }
    guard try maskDictionary.objectValue(forKey: "ImageType", as: IntegerValue.self).value == 1 else {
      throw Error.typeCheck
    }
    switch interleaveType {
    case 1:
      guard width == specification.width,
        height == specification.height,
        bits == specification.bitsPerComponent
      else { throw Error.typeCheck }
    case 2:
      guard bits == 1,
        width > 0,
        height > 0,
        specification.height > 0,
        height.isMultiple(of: specification.height) || specification.height.isMultiple(of: height)
      else { throw Error.typeCheck }
    case 3:
      guard bits == 1 else { throw Error.typeCheck }
    default:
      throw Error.rangeCheck
    }
    try validateAlignedImageCorners(
      imageWidth: specification.width,
      imageHeight: specification.height,
      imageMatrix: specification.imageMatrix,
      maskWidth: width,
      maskHeight: height,
      maskMatrix: matrix
    )
    guard let maskToUser = matrix.inverted else { throw Error.undefinedResult }
    specification.mask = .explicit(ExplicitImageMaskSpecification(
      width: width,
      height: height,
      bitsPerComponent: bits,
      imageMatrix: matrix,
      maskToDevice: maskToUser.concatenated(with: context.graphicsState.matrix),
      decode: decode,
      interpolate: interpolate,
      sources: sources,
      interleaveType: interleaveType
    ))
    return specification
  }

  static func validateAlignedImageCorners(
    imageWidth: Int,
    imageHeight: Int,
    imageMatrix: GraphicsMatrix,
    maskWidth: Int,
    maskHeight: Int,
    maskMatrix: GraphicsMatrix
  ) throws {
    guard let imageToUser = imageMatrix.inverted, let maskToUser = maskMatrix.inverted else {
      throw Error.undefinedResult
    }
    let imageCorners = [
      GraphicsPoint(x: 0, y: 0),
      GraphicsPoint(x: Double(imageWidth), y: 0),
      GraphicsPoint(x: Double(imageWidth), y: Double(imageHeight)),
      GraphicsPoint(x: 0, y: Double(imageHeight)),
    ].map(imageToUser.transform)
    let maskCorners = [
      GraphicsPoint(x: 0, y: 0),
      GraphicsPoint(x: Double(maskWidth), y: 0),
      GraphicsPoint(x: Double(maskWidth), y: Double(maskHeight)),
      GraphicsPoint(x: 0, y: Double(maskHeight)),
    ].map(maskToUser.transform)
    guard zip(imageCorners, maskCorners).allSatisfy({ image, mask in
      let scale = max(1, abs(image.x), abs(image.y), abs(mask.x), abs(mask.y))
      return abs(image.x - mask.x) <= scale * 1e-9 && abs(image.y - mask.y) <= scale * 1e-9
    }) else { throw Error.typeCheck }
  }

  static func validateSameSourceTypes(_ sources: [ImageDataSource]) throws {
    guard let first = sources.first else { throw Error.rangeCheck }
    guard sources.allSatisfy({ $0.kind == first.kind }) else { throw Error.typeCheck }
    if first.kind == .string {
      let lengths = try sources.map { source in
        let string = try source.object.value(as: StringValue.self)
        return string.count
      }
      guard lengths.allSatisfy({ $0 == lengths[0] }) else { throw Error.rangeCheck }
    }
    if first.kind == .file {
      let identities = try sources.map { source in
        try source.object.value(as: FileValue.self).file.ultimateSourceIdentity
      }
      guard Set(identities).count == identities.count else { throw Error.rangeCheck }
    }
  }

  static func paintImage(
    _ initial: ImageSpecification,
    context: isolated Context
  ) async throws {
    var specification = initial
    let previousDictionaries = context.activeImageDictionaries
    context.activeImageDictionaries = specification.dictionaries.map { ($0, $0.revision) }
    defer { context.activeImageDictionaries = previousDictionaries }
    guard let imageToUser = specification.imageMatrix.inverted else { throw Error.undefinedResult }
    let descriptor = GraphicsImageDescriptor(
      width: specification.width,
      height: specification.height,
      kind: specification.kind,
      sourceType: specification.mask?.sourceType ?? .sampled,
      sourceColorSpace: specification.sourceColorSpace?.description,
      sourceBitsPerComponent: specification.bitsPerComponent,
      sourceComponentCount: specification.sourceComponentCount,
      decode: specification.decode,
      imageToDevice: imageToUser.concatenated(with: context.graphicsState.matrix),
      interpolate: specification.interpolate,
      mask: specification.mask?.descriptor(
        imageToDevice: imageToUser.concatenated(with: context.graphicsState.matrix)
      ),
      resourceIdentifier: context.environment.graphicsResourceIdentities.next()
    )
    do {
      try context.beginGraphicsImage(descriptor)
      guard specification.width > 0, specification.height > 0 else {
        try context.endGraphicsImage()
        return
      }

      if case .explicit(let mask) = specification.mask {
        try await paintExplicitImage(&specification, mask: mask, context: context)
        try context.endGraphicsImage()
        return
      }

      let componentCount = specification.kind.componentCount
      let rowsPerTransfer = max(1, min(32, 65_536 / max(1, specification.width * componentCount)))
      var startRow = 0
      while startRow < specification.height {
        let rowCount = min(rowsPerTransfer, specification.height - startRow)
        var components: [Float] = []
        components.reserveCapacity(rowCount * specification.width * componentCount)
        var sourceComponents: [Float] = []
        sourceComponents.reserveCapacity(
          rowCount * specification.width * specification.sourceComponentCount
        )
        var completedRows = 0
        var rawComponents: [UInt16] = []
        rawComponents.reserveCapacity(
          rowCount * specification.width * specification.sourceComponentCount
        )
        var maskOpacities: [Float] = []
        for _ in 0..<rowCount {
          guard let row = try await readImageRow(&specification, context: context) else { break }
          components.append(contentsOf: row.components)
          sourceComponents.append(contentsOf: row.sourceComponents ?? [])
          rawComponents.append(contentsOf: row.rawComponents)
          if case .colorKey(let ranges) = specification.mask {
            maskOpacities.append(contentsOf: colorKeyOpacities(
              rawComponents: row.rawComponents,
              componentCount: specification.sourceComponentCount,
              ranges: ranges
            ))
          }
          completedRows += 1
        }
        guard completedRows > 0 else { break }
        try context.writeGraphicsImageRows(GraphicsImageRows(
          startRow: startRow,
          rowCount: completedRows,
          components: components,
          sourceComponents: sourceComponents.isEmpty ? nil : sourceComponents,
          rawSamples: rawSampleData(rawComponents)
        ))
        if !maskOpacities.isEmpty {
          try context.writeGraphicsImageMaskRows(GraphicsImageMaskRows(
            startRow: startRow,
            rowCount: completedRows,
            opacities: maskOpacities
          ))
        }
        startRow += completedRows
        if completedRows < rowCount { break }
      }
      try context.endGraphicsImage()
    } catch {
      context.abortGraphicsImage()
      throw error
    }
  }

  static func colorKeyOpacities(
    rawComponents: [UInt16],
    componentCount: Int,
    ranges: [GraphicsImageSampleRange]
  ) -> [Float] {
    stride(from: 0, to: rawComponents.count, by: componentCount).map { offset in
      let matches = (0..<componentCount).allSatisfy { component in
        ranges[component].contains(rawComponents[offset + component])
      }
      return matches ? 0 : 1
    }
  }

  static func paintExplicitImage(
    _ specification: inout ImageSpecification,
    mask: ExplicitImageMaskSpecification,
    context: isolated Context
  ) async throws {
    switch mask.interleaveType {
    case 1:
      try await paintSampleInterleavedImage(&specification, mask: mask, context: context)
    case 2:
      try await paintRowInterleavedImage(&specification, mask: mask, context: context)
    case 3:
      try await paintSeparateMaskedImage(&specification, mask: mask, context: context)
    default:
      throw Error.rangeCheck
    }
  }

  static func paintSampleInterleavedImage(
    _ specification: inout ImageSpecification,
    mask: ExplicitImageMaskSpecification,
    context: isolated Context
  ) async throws {
    let sourceComponentCount = specification.sourceComponentCount
    let samplesPerRow = specification.width * (sourceComponentCount + 1)
    let bytesPerRow = (samplesPerRow * specification.bitsPerComponent + 7) / 8
    let maximum = UInt16((1 << specification.bitsPerComponent) - 1)
    for rowIndex in 0..<specification.height {
      guard let data = try await specification.sources[0].read(count: bytesPerRow, context: context) else {
        return
      }
      let samples = rawSamples(data, count: samplesPerRow, bits: specification.bitsPerComponent)
      var imageRaw: [UInt16] = []
      var opacities: [Float] = []
      imageRaw.reserveCapacity(specification.width * sourceComponentCount)
      opacities.reserveCapacity(specification.width)
      for pixel in 0..<specification.width {
        let offset = pixel * (sourceComponentCount + 1)
        let maskRaw = samples[offset]
        let effectiveMask = maskRaw == 0 ? UInt16(0) : maximum
        opacities.append(maskOpacity(raw: effectiveMask, maximum: maximum, decode: mask.decode))
        imageRaw.append(contentsOf: samples[(offset + 1)..<(offset + 1 + sourceComponentCount)])
      }
      let decoded = decodeRawSamples(
        imageRaw,
        maximum: Double(maximum),
        decode: specification.decode
      )
      let image = try await resolveImageRow(
        decoded,
        rawComponents: imageRaw,
        specification: specification,
        context: context
      )
      try writeImageRow(image, row: rowIndex, maskOpacities: opacities, context: context)
    }
  }

  static func paintRowInterleavedImage(
    _ specification: inout ImageSpecification,
    mask: ExplicitImageMaskSpecification,
    context: isolated Context
  ) async throws {
    let imageRowsPerBlock = max(1, specification.height / mask.height)
    let maskRowsPerBlock = max(1, mask.height / specification.height)
    var imageRow = 0
    var maskRow = 0
    while imageRow < specification.height, maskRow < mask.height {
      for _ in 0..<maskRowsPerBlock where maskRow < mask.height {
        guard let opacities = try await readSharedMaskRow(
          source: &specification.sources[0],
          mask: mask,
          context: context
        ) else { return }
        try context.writeGraphicsImageMaskRows(.init(
          startRow: maskRow,
          rowCount: 1,
          opacities: opacities
        ))
        maskRow += 1
      }
      for _ in 0..<imageRowsPerBlock where imageRow < specification.height {
        guard let row = try await readImageRow(&specification, context: context) else { return }
        try writeImageRow(row, row: imageRow, maskOpacities: nil, context: context)
        imageRow += 1
      }
    }
  }

  static func paintSeparateMaskedImage(
    _ specification: inout ImageSpecification,
    mask: ExplicitImageMaskSpecification,
    context: isolated Context
  ) async throws {
    var imageRow = 0
    var maskRow = 0
    while imageRow < specification.height || maskRow < mask.height {
      let maskBoundary = (imageRow + 1) * mask.height
      while maskRow < mask.height,
        (imageRow >= specification.height || maskRow * specification.height < maskBoundary)
      {
        guard let opacities = try await readSeparateMaskRow(mask, context: context) else { return }
        try context.writeGraphicsImageMaskRows(.init(
          startRow: maskRow,
          rowCount: 1,
          opacities: opacities
        ))
        maskRow += 1
      }
      guard imageRow < specification.height else { continue }
      guard let row = try await readImageRow(&specification, context: context) else { return }
      try writeImageRow(row, row: imageRow, maskOpacities: nil, context: context)
      imageRow += 1
    }
  }

  static func readSharedMaskRow(
    source: inout ImageDataSource,
    mask: ExplicitImageMaskSpecification,
    context: isolated Context
  ) async throws -> [Float]? {
    let bytesPerRow = (mask.width + 7) / 8
    guard let data = try await source.read(count: bytesPerRow, context: context) else { return nil }
    return maskOpacities(data, mask: mask)
  }

  static func readSeparateMaskRow(
    _ mask: ExplicitImageMaskSpecification,
    context: isolated Context
  ) async throws -> [Float]? {
    let bytesPerRow = (mask.width * mask.bitsPerComponent + 7) / 8
    guard let data = try await mask.sources[0].read(count: bytesPerRow, context: context) else { return nil }
    return maskOpacities(data, mask: mask)
  }

  static func maskOpacities(_ data: Data, mask: ExplicitImageMaskSpecification) -> [Float] {
    let maximum = UInt16((1 << mask.bitsPerComponent) - 1)
    return rawSamples(data, count: mask.width, bits: mask.bitsPerComponent).map {
      maskOpacity(raw: $0, maximum: maximum, decode: mask.decode)
    }
  }

  static func maskOpacity(raw: UInt16, maximum: UInt16, decode: [Double]) -> Float {
    let decoded = decode[0] + Double(raw) / Double(maximum) * (decode[1] - decode[0])
    return Float(1 - min(1, max(0, decoded)))
  }

  static func writeImageRow(
    _ row: ImageRow,
    row rowIndex: Int,
    maskOpacities: [Float]?,
    context: isolated Context
  ) throws {
    try context.writeGraphicsImageRows(.init(
      startRow: rowIndex,
      rowCount: 1,
      components: row.components,
      sourceComponents: row.sourceComponents,
      rawSamples: rawSampleData(row.rawComponents)
    ))
    if let maskOpacities {
      try context.writeGraphicsImageMaskRows(.init(
        startRow: rowIndex,
        rowCount: 1,
        opacities: maskOpacities
      ))
    }
  }

  static func readImageRow(
    _ specification: inout ImageSpecification,
    context: isolated Context
  ) async throws -> ImageRow? {
    let componentCount = specification.sourceComponentCount
    if specification.multipleDataSources {
      let bitsPerPlane = specification.width * specification.bitsPerComponent
      let bytesPerPlane = (bitsPerPlane + 7) / 8
      if specification.sources.first?.kind == .procedure {
        while specification.sources.contains(where: { $0.buffered.count < bytesPerPlane }) {
          var lengths: [Int] = []
          for index in specification.sources.indices {
            guard let length = try await specification.sources[index].appendNext(
              max: bytesPerPlane,
              context: context
            ) else {
              return nil
            }
            lengths.append(length)
          }
          guard lengths.allSatisfy({ $0 == lengths[0] }) else { throw Error.rangeCheck }
        }
      }
      var planes: [DecodedSamples] = []
      planes.reserveCapacity(componentCount)
      for index in 0..<componentCount {
        let data: Data
        if specification.sources[index].kind == .procedure {
          data = specification.sources[index].consume(count: bytesPerPlane)
        } else {
          guard let sourceData = try await specification.sources[index].read(
            count: bytesPerPlane,
            context: context
          ) else { return nil }
          data = sourceData
        }
        planes.append(decodeSamples(
          data,
          count: specification.width,
          bits: specification.bitsPerComponent,
          decode: Array(specification.decode[(index * 2)..<(index * 2 + 2)])
        ))
      }
      let decoded = (0..<specification.width).flatMap { sample in
        (0..<componentCount).map { planes[$0].decoded[sample] }
      }
      let raw = (0..<specification.width).flatMap { sample in
        (0..<componentCount).map { planes[$0].raw[sample] }
      }
      return try await resolveImageRow(
        decoded,
        rawComponents: raw,
        specification: specification,
        context: context
      )
    }

    let sampleCount = specification.width * componentCount
    let bytesPerRow = (sampleCount * specification.bitsPerComponent + 7) / 8
    guard let data = try await specification.sources[0].read(count: bytesPerRow, context: context) else { return nil }
    let samples = decodeSamples(
      data,
      count: sampleCount,
      bits: specification.bitsPerComponent,
      decode: specification.decode
    )
    return try await resolveImageRow(
      samples.decoded,
      rawComponents: samples.raw,
      specification: specification,
      context: context
    )
  }

  struct ImageRow {
    let components: [Float]
    let sourceComponents: [Float]?
    let rawComponents: [UInt16]
  }

  static func resolveImageRow(
    _ components: [Float],
    rawComponents: [UInt16],
    specification: ImageSpecification,
    context: isolated Context
  ) async throws -> ImageRow {
    guard let selection = specification.colorSelection else {
      return ImageRow(components: components, sourceComponents: nil, rawComponents: rawComponents)
    }
    var alternative: [Float] = []
    alternative.reserveCapacity(specification.width * 3)
    for offset in stride(from: 0, to: components.count, by: selection.source.componentCount) {
      let source = components[offset..<(offset + selection.source.componentCount)].map(Double.init)
      let resolved = try await resolveColor(source, in: selection, context: context)
      let rgb = resolved.rgb
      alternative.append(Float(rgb.red))
      alternative.append(Float(rgb.green))
      alternative.append(Float(rgb.blue))
    }
    return ImageRow(components: alternative, sourceComponents: components, rawComponents: rawComponents)
  }

  struct DecodedSamples {
    let decoded: [Float]
    let raw: [UInt16]
  }

  static func decodeSamples(
    _ data: Data,
    count: Int,
    bits: Int,
    decode: [Double]
  ) -> DecodedSamples {
    let raw = rawSamples(data, count: count, bits: bits)
    return DecodedSamples(
      decoded: decodeRawSamples(raw, maximum: Double((1 << bits) - 1), decode: decode),
      raw: raw
    )
  }

  static func rawSamples(_ data: Data, count: Int, bits: Int) -> [UInt16] {
    var samples: [UInt16] = []
    samples.reserveCapacity(count)
    var bitOffset = 0
    for _ in 0..<count {
      var raw = 0
      for _ in 0..<bits {
        let byte = data[bitOffset / 8]
        raw = raw << 1 | Int((byte >> UInt8(7 - bitOffset % 8)) & 1)
        bitOffset += 1
      }
      samples.append(UInt16(raw))
    }
    return samples
  }

  static func rawSampleData(_ samples: [UInt16]) -> Data {
    var data = Data(capacity: samples.count * MemoryLayout<UInt16>.size)
    for sample in samples {
      var bigEndian = sample.bigEndian
      withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }
    return data
  }

  static func decodeRawSamples(
    _ rawSamples: [UInt16],
    maximum: Double,
    decode: [Double]
  ) -> [Float] {
    let componentCount = decode.count / 2
    return rawSamples.enumerated().map { sampleIndex, raw in
      let component = sampleIndex % componentCount
      let lower = decode[component * 2]
      let upper = decode[component * 2 + 1]
      let decoded = lower + Double(raw) / maximum * (upper - lower)
      return Float(min(1, max(0, decoded)))
    }
  }
}
