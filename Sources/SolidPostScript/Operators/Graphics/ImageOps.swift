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
      let specification: ImageSpecification
      if let dictionary = try? context.operands.peek().value(as: DictionaryValue.self) {
        _ = try context.operands.pop()
        specification = try imageDictionary(dictionary, mask: false, context: context)
      } else {
        specification = try separateImageOperands(context: context)
      }
      try await paintImage(specification, context: context)
    }
  }

  enum PaintImageMask: OperatorValue {
    case instance
    static let systemDictionaryNames: [Object] = ["imagemask"]

    func execute(context: isolated Context) async throws {
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
      try await paintImage(
        ImageSpecification(
          width: width,
          height: height,
          bitsPerComponent: bits,
          imageMatrix: matrix,
          kind: .color(colorSpace),
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
    let decode: [Double]
    let interpolate: Bool
    var sources: [ImageDataSource]
    let multipleDataSources: Bool

    init(
      width: Int,
      height: Int,
      bitsPerComponent: Int,
      imageMatrix: GraphicsMatrix,
      kind: GraphicsImageKind,
      decode: [Double],
      interpolate: Bool,
      sources: [ImageDataSource],
      multipleDataSources: Bool
    ) throws {
      guard width >= 0, height >= 0 else { throw Error.rangeCheck }
      guard [1, 2, 4, 8, 12].contains(bitsPerComponent) else { throw Error.rangeCheck }
      guard imageMatrix.inverted != nil else { throw Error.undefinedResult }
      guard decode.count == kind.componentCount * 2 else { throw Error.rangeCheck }
      guard sources.count == (multipleDataSources ? kind.componentCount : 1) else { throw Error.rangeCheck }
      let (samplesPerRow, samplesOverflow) = width.multipliedReportingOverflow(by: kind.componentCount)
      let (bitsPerRow, bitsOverflow) = samplesPerRow.multipliedReportingOverflow(by: bitsPerComponent)
      guard !samplesOverflow, !bitsOverflow, bitsPerRow <= LanguageLimits.maximumImageRowBytes * 8 else {
        throw Error.limitCheck
      }
      self.width = width
      self.height = height
      self.bitsPerComponent = bitsPerComponent
      self.imageMatrix = imageMatrix
      self.kind = kind
      self.decode = decode
      self.interpolate = interpolate
      self.sources = sources
      self.multipleDataSources = multipleDataSources
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
        try await context.execute(proc: object)
        guard context.operands.depth == originalDepth + 1 else { throw Error.typeCheck }
        let string: StringValue = try context.operands.popAs()
        try string.access.check(.read)
        return try string.characters(in: string.range)
      }
    }
  }

  static func separateImageOperands(context: isolated Context) throws -> ImageSpecification {
    let source = try ImageDataSource(context.operands.pop())
    let matrix = try readMatrix(context.operands.pop())
    let bits = Int(try context.operands.pop().value(as: IntegerValue.self).value)
    let height = Int(try context.operands.pop().value(as: IntegerValue.self).value)
    let width = Int(try context.operands.pop().value(as: IntegerValue.self).value)
    return try ImageSpecification(
      width: width,
      height: height,
      bitsPerComponent: bits,
      imageMatrix: matrix,
      kind: .color(.deviceGray),
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
    guard type == 1 else { throw Error.rangeCheck }
    let width = Int(try dictionary.objectValue(forKey: "Width", as: IntegerValue.self).value)
    let height = Int(try dictionary.objectValue(forKey: "Height", as: IntegerValue.self).value)
    let bits = Int(try dictionary.objectValue(forKey: "BitsPerComponent", as: IntegerValue.self).value)
    let matrix = try readMatrix(dictionary.object(forKey: "ImageMatrix"))
    let multiple = try dictionary.objectValue(forKeyIfExists: "MultipleDataSources", as: BooleanValue.self)?.value
      ?? false
    let interpolate = try dictionary.objectValue(forKeyIfExists: "Interpolate", as: BooleanValue.self)?.value
      ?? false
    let kind: GraphicsImageKind
    switch context.graphicsState.paint {
    case .deviceGray:
      kind = mask ? .mask(context.graphicsState.paint) : .color(.deviceGray)
    case .deviceRGB:
      kind = mask ? .mask(context.graphicsState.paint) : .color(.deviceRGB)
    case .deviceCMYK:
      kind = mask ? .mask(context.graphicsState.paint) : .color(.deviceCMYK)
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
      decode: decode,
      interpolate: interpolate,
      sources: sources,
      multipleDataSources: multiple
    )
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
        ObjectIdentifier(try source.object.value(as: FileValue.self).file)
      }
      guard Set(identities).count == identities.count else { throw Error.rangeCheck }
    }
  }

  static func paintImage(
    _ initial: ImageSpecification,
    context: isolated Context
  ) async throws {
    var specification = initial
    guard let imageToUser = specification.imageMatrix.inverted else { throw Error.undefinedResult }
    let descriptor = GraphicsImageDescriptor(
      width: specification.width,
      height: specification.height,
      kind: specification.kind,
      imageToDevice: imageToUser.concatenated(with: context.graphicsState.matrix),
      interpolate: specification.interpolate
    )
    do {
      try context.beginGraphicsImage(descriptor)
      guard specification.width > 0, specification.height > 0 else {
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
        var completedRows = 0
        for _ in 0..<rowCount {
          guard let row = try await readImageRow(&specification, context: context) else { break }
          components.append(contentsOf: row)
          completedRows += 1
        }
        guard completedRows > 0 else { break }
        try context.writeGraphicsImageRows(
          GraphicsImageRows(startRow: startRow, rowCount: completedRows, components: components)
        )
        startRow += completedRows
        if completedRows < rowCount { break }
      }
      try context.endGraphicsImage()
    } catch {
      context.abortGraphicsImage()
      throw error
    }
  }

  static func readImageRow(
    _ specification: inout ImageSpecification,
    context: isolated Context
  ) async throws -> [Float]? {
    let componentCount = specification.kind.componentCount
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
      var planes: [[Float]] = []
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
      return (0..<specification.width).flatMap { sample in
        (0..<componentCount).map { planes[$0][sample] }
      }
    }

    let sampleCount = specification.width * componentCount
    let bytesPerRow = (sampleCount * specification.bitsPerComponent + 7) / 8
    guard let data = try await specification.sources[0].read(count: bytesPerRow, context: context) else { return nil }
    return decodeSamples(
      data,
      count: sampleCount,
      bits: specification.bitsPerComponent,
      decode: specification.decode
    )
  }

  static func decodeSamples(
    _ data: Data,
    count: Int,
    bits: Int,
    decode: [Double]
  ) -> [Float] {
    let maximum = Double((1 << bits) - 1)
    let componentCount = decode.count / 2
    var result: [Float] = []
    result.reserveCapacity(count)
    var bitOffset = 0
    for sampleIndex in 0..<count {
      var raw = 0
      for _ in 0..<bits {
        let byte = data[bitOffset / 8]
        raw = raw << 1 | Int((byte >> UInt8(7 - bitOffset % 8)) & 1)
        bitOffset += 1
      }
      let component = sampleIndex % componentCount
      let lower = decode[component * 2]
      let upper = decode[component * 2 + 1]
      let decoded = lower + Double(raw) / maximum * (upper - lower)
      result.append(Float(min(1, max(0, decoded))))
    }
    return result
  }
}
