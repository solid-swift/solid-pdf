//
//  FilterOps.swift
//  SolidPostScript
//
//  Created by Codex on 8/15/26.
//

import Foundation
import SolidImageIO
import SolidIO
import Synchronization

extension Operators {

  static let filterOps: [OperatorValue] = [Filter.instance]

  /// Implements the PostScript `filter` operator.
  public enum Filter: OperatorValue {
    case instance

    /// The names that register this operator in the system dictionary.
    public static let systemDictionaryNames: [Object] = ["filter"]

    static let standardNames: [String] = [
      "ASCIIHexEncode",
      "ASCIIHexDecode",
      "ASCII85Encode",
      "ASCII85Decode",
      "LZWEncode",
      "LZWDecode",
      "FlateEncode",
      "FlateDecode",
      "RunLengthEncode",
      "RunLengthDecode",
      "CCITTFaxEncode",
      "CCITTFaxDecode",
      "DCTEncode",
      "DCTDecode",
      "NullEncode",
      "SubFileDecode",
      "ReusableStreamDecode",
    ]

    static let availableNames = standardNames

    /// Executes this value in the supplied interpreter context.
    public func execute(context: isolated Context) async throws {
      let nameObject = try context.operands.pop()
      let name = try nameObject.value(as: NameValue.self).value
      guard Self.availableNames.contains(name) else { throw Error.undefined }

      switch name {
      case "RunLengthEncode":
        try makeRunLengthEncoder(context: context)
      case "SubFileDecode":
        try await makeSubFileDecoder(context: context)
      case "DCTEncode":
        try makeDCTEncoder(context: context)
      case "ReusableStreamDecode":
        try await makeReusableStream(context: context)
      default:
        let dictionary = try popOptionalDictionary(context: context)
        let source = try context.operands.pop()
        if name.hasSuffix("Encode") {
          let closeTarget = try dictionary.boolean("CloseTarget", default: false)
          let codec = try encoder(named: name, dictionary: dictionary)
          let target = try FilterTarget(destination: source, closeTarget: closeTarget)
          let file = EncodingFilterFile(name: name, codec: codec, target: target)
          let vm = retainedVM([source] + retainedDictionary(name: name, dictionary: dictionary))
          let allocation = try context.register(file: file, vm: vm)
          context.operands.push(.file(file, access: .unlimited, vm: vm, allocation: allocation, kind: .literal))
        } else {
          let closeSource = try dictionary.boolean("CloseSource", default: false)
          let vm = retainedVM([source] + retainedDictionary(name: name, dictionary: dictionary))
          let codec = try decoder(
            named: name,
            dictionary: dictionary,
            maximumDecodedBytes: context.remainingVMCapacity(in: vm)
          )
          let file = try DecodingFilterFile(
            name: name,
            codec: codec,
            source: source,
            closeSource: closeSource
          )
          let allocation = try context.register(file: file, vm: vm)
          context.operands.push(.file(file, access: .readOnly, vm: vm, allocation: allocation, kind: .literal))
        }
      }
    }

    private func makeRunLengthEncoder(context: isolated Context) throws {
      let recordSize: IntegerValue = try context.operands.popAs()
      guard recordSize.value >= 0 else { throw Error.rangeCheck }
      let dictionary = try popOptionalDictionary(context: context)
      let source = try context.operands.pop()
      let closeTarget = try dictionary.boolean("CloseTarget", default: false)
      let codec = try translateCodecOption {
        try RunLengthEncoder(recordSize: Int(recordSize.value))
      }
      let target = try FilterTarget(destination: source, closeTarget: closeTarget)
      let file = EncodingFilterFile(name: "RunLengthEncode", codec: codec, target: target)
      let vm = retainedVM([source])
      let allocation = try context.register(file: file, vm: vm)
      context.operands.push(.file(file, access: .unlimited, vm: vm, allocation: allocation, kind: .literal))
    }

    private func makeSubFileDecoder(context: isolated Context) async throws {
      let dictionary: FilterDictionary
      let source: Object
      let count: Int
      let marker: Data

      if let dict = try context.operands.peek().value as? DictionaryValue {
        _ = try context.operands.pop()
        dictionary = FilterDictionary(dict)
        source = try context.operands.pop()
        count = try dictionary.integer("EODCount", default: 0)
        marker = try dictionary.string("EODString", default: Data())
      } else {
        let markerValue: StringValue = try context.operands.popAs()
        try markerValue.access.check(.read)
        let countValue: IntegerValue = try context.operands.popAs()
        dictionary = try popOptionalDictionary(context: context)
        source = try context.operands.pop()
        count = Int(countValue.value)
        marker = try markerValue.characters(in: markerValue.range)
      }

      guard count >= 0 else { throw Error.rangeCheck }
      guard count == 0 || !marker.isEmpty else { throw Error.rangeCheck }
      let closeSource = try dictionary.boolean("CloseSource", default: false)
      let codec = try SubFileDecoder(eodCount: count, eodString: marker)
      let markerObject = Object.string(marker, access: .readOnly, vm: source.vmIfComposite, kind: .literal)
      let vm = retainedVM([source, markerObject])
      let file = try DecodingFilterFile(
        name: "SubFileDecode",
        codec: codec,
        source: source,
        closeSource: closeSource
      )
      let allocation = try context.register(file: file, vm: vm)
      context.operands.push(.file(file, access: .readOnly, vm: vm, allocation: allocation, kind: .literal))
    }

    private func makeDCTEncoder(context: isolated Context) throws {
      let dictionaryValue: DictionaryValue = try context.operands.popAs()
      let dictionary = FilterDictionary(dictionaryValue)
      let source = try context.operands.pop()
      let closeTarget = try dictionary.boolean("CloseTarget", default: false)
      let codec = try encoder(named: "DCTEncode", dictionary: dictionary)
      let target = try FilterTarget(destination: source, closeTarget: closeTarget)
      let file = EncodingFilterFile(name: "DCTEncode", codec: codec, target: target)
      let dictObject = Object.dictionary(sharing: dictionaryValue, kind: .literal)
      let vm = retainedVM([source, dictObject])
      let allocation = try context.register(file: file, vm: vm)
      context.operands.push(.file(file, access: .unlimited, vm: vm, allocation: allocation, kind: .literal))
    }

    private func makeReusableStream(context: isolated Context) async throws {
      let dictionary = try popOptionalDictionary(context: context)
      let source = try context.operands.pop()
      var data = try await readAll(source: source, context: context)
      let vm = retainedVM([source])

      if let filterObject = try dictionary.object("Filter") {
        let filters = try filterNames(filterObject)
        let decodeParms = try decodeParameters(dictionary: dictionary, count: filters.count)
        for (index, name) in filters.enumerated() {
          let codec = try decoder(
            named: name,
            dictionary: decodeParms[index],
            maximumDecodedBytes: context.remainingVMCapacity(in: vm)
          )
          data = try decode(codec: codec, data: data)
        }
      }

      let file = MaterializedFilterFile(
        data: data,
        name: "ReusableStreamDecode",
        positionable: true,
        closeAtEnd: false
      )
      let allocation = try context.register(file: file, vm: vm)
      context.operands.push(.file(file, access: .readOnly, vm: vm, allocation: allocation, kind: .literal))
    }

    private func popOptionalDictionary(context: isolated Context) throws -> FilterDictionary {
      guard context.operands.depth > 0,
            let dictionary = try context.operands.peek().value as? DictionaryValue
      else {
        return FilterDictionary(nil)
      }
      _ = try context.operands.pop()
      return FilterDictionary(dictionary)
    }

    private func encoder(named name: String, dictionary: FilterDictionary) throws -> any IncrementalFilter {
      switch name {
      case "ASCIIHexEncode":
        ASCIIHexEncoder()
      case "ASCII85Encode":
        ASCII85Encoder()
      case "LZWEncode":
        try makeLZWEncoder(dictionary: dictionary)
      case "FlateEncode":
        try makeFlateEncoder(dictionary: dictionary)
      case "CCITTFaxEncode":
        CCITTFaxEncoder(options: try ccittOptions(dictionary: dictionary))
      case "DCTEncode":
        DCTEncoder(options: try dctEncodeOptions(dictionary: dictionary))
      case "NullEncode":
        NullEncoder()
      default:
        throw Error.undefined
      }
    }

    private func decoder(
      named name: String,
      dictionary: FilterDictionary,
      maximumDecodedBytes: Int
    ) throws -> any IncrementalFilter {
      switch name {
      case "ASCIIHexDecode":
        ASCIIHexDecoder()
      case "ASCII85Decode":
        ASCII85Decoder()
      case "LZWDecode":
        try makeLZWDecoder(dictionary: dictionary)
      case "FlateDecode":
        try makeFlateDecoder(dictionary: dictionary)
      case "RunLengthDecode":
        RunLengthDecoder()
      case "CCITTFaxDecode":
        CCITTFaxDecoder(options: try ccittOptions(dictionary: dictionary))
      case "DCTDecode":
        DCTDecoder(
          options: try dctDecodeOptions(
            dictionary: dictionary,
            maximumDecodedBytes: maximumDecodedBytes
          )
        )
      default:
        throw Error.undefined
      }
    }

    private func makeLZWEncoder(dictionary: FilterDictionary) throws -> any IncrementalFilter {
      let earlyChange = try dictionary.integer("EarlyChange", default: 1)
      let options = try translateCodecOption { try LZWOptions(earlyChange: earlyChange) }
      let codec = LZWEncoder(options: options)
      let predictor = try predictorOptions(dictionary: dictionary)
      return predictor.predictor == 1 ? codec : PredictingEncoder(codec: codec, options: predictor)
    }

    private func makeLZWDecoder(dictionary: FilterDictionary) throws -> any IncrementalFilter {
      let earlyChange = try dictionary.integer("EarlyChange", default: 1)
      let unitLength = try dictionary.integer("UnitLength", default: 8)
      let lowBitFirst = try dictionary.boolean("LowBitFirst", default: false)
      let options = try translateCodecOption {
        try LZWOptions(earlyChange: earlyChange, unitLength: unitLength, lowBitFirst: lowBitFirst)
      }
      let codec = LZWDecoder(options: options)
      let predictor = try predictorOptions(dictionary: dictionary)
      return predictor.predictor == 1 ? codec : PredictingDecoder(codec: codec, options: predictor)
    }

    private func makeFlateEncoder(dictionary: FilterDictionary) throws -> any IncrementalFilter {
      let effort = try dictionary.integer("Effort", default: -1)
      let codec = try translateCodecOption { FlateEncoder(options: try FlateOptions(effort: effort)) }
      let predictor = try predictorOptions(dictionary: dictionary)
      return predictor.predictor == 1 ? codec : PredictingEncoder(codec: codec, options: predictor)
    }

    private func makeFlateDecoder(dictionary: FilterDictionary) throws -> any IncrementalFilter {
      let codec = FlateDecoder()
      let predictor = try predictorOptions(dictionary: dictionary)
      return predictor.predictor == 1 ? codec : PredictingDecoder(codec: codec, options: predictor)
    }

    private func predictorOptions(dictionary: FilterDictionary) throws -> PredictorOptions {
      try translateCodecOption {
        try PredictorOptions(
          predictor: dictionary.integer("Predictor", default: 1),
          colors: dictionary.integer("Colors", default: 1),
          bitsPerComponent: dictionary.integer("BitsPerComponent", default: 8),
          columns: dictionary.integer("Columns", default: 1)
        )
      }
    }

    private func ccittOptions(dictionary: FilterDictionary) throws -> CCITTFaxOptions {
      try translateCodecOption {
        try CCITTFaxOptions(
          uncompressed: dictionary.boolean("Uncompressed", default: false),
          k: dictionary.integer("K", default: 0),
          endOfLine: dictionary.boolean("EndOfLine", default: false),
          encodedByteAlign: dictionary.boolean("EncodedByteAlign", default: false),
          columns: dictionary.integer("Columns", default: 1728),
          rows: dictionary.integer("Rows", default: 0),
          endOfBlock: dictionary.boolean("EndOfBlock", default: true),
          blackIs1: dictionary.boolean("BlackIs1", default: false),
          damagedRowsBeforeError: dictionary.integer("DamagedRowsBeforeError", default: 0)
        )
      }
    }

    private func dctEncodeOptions(dictionary: FilterDictionary) throws -> DCTEncodeOptions {
      let colors = try dictionary.requiredInteger("Colors")
      return try translateCodecOption {
        try DCTEncodeOptions(
          columns: dictionary.requiredInteger("Columns"),
          rows: dictionary.requiredInteger("Rows"),
          colors: colors,
          horizontalSamples: dictionary.integerArray("HSamples", default: []),
          verticalSamples: dictionary.integerArray("VSamples", default: []),
          quantizationTables: dictionary.dataArray("QuantTables", default: []),
          quantizationFactor: dictionary.number("QFactor", default: 1),
          huffmanTables: dictionary.huffmanTables("HuffTables", default: []),
          colorTransform: dictionary.integer("ColorTransform", default: colors == 3 ? 1 : 0)
        )
      }
    }

    private func dctDecodeOptions(
      dictionary: FilterDictionary,
      maximumDecodedBytes: Int
    ) throws -> DCTDecodeOptions {
      try translateCodecOption {
        try DCTDecodeOptions(
          columns: dictionary.integer("Columns", default: 0),
          rows: dictionary.integer("Rows", default: 0),
          colors: dictionary.integer("Colors", default: 0),
          colorTransform: dictionary.optionalInteger("ColorTransform"),
          horizontalSamples: dictionary.integerArray("HSamples", default: []),
          verticalSamples: dictionary.integerArray("VSamples", default: []),
          quantizationTables: dictionary.dataArray("QuantTables", default: []),
          huffmanTables: dictionary.huffmanTables("HuffTables", default: []),
          maximumDecodedBytes: maximumDecodedBytes
        )
      }
    }

    private func retainedDictionary(name: String, dictionary: FilterDictionary) -> [Object] {
      guard name == "DCTEncode" || name == "DCTDecode", let value = dictionary.value else { return [] }
      return [.dictionary(sharing: value, kind: .literal)]
    }

    private func retainedVM(_ objects: [Object]) -> VM {
      objects.allSatisfy { object in
        guard let composite = object.value as? any CompositeValue else { return true }
        return composite.vm == .global
      } ? .global : .local
    }

    private func decode(codec: any IncrementalFilter, data: Data) throws -> Data {
      let result = try translateCodecError { try codec.process(input: data) }
      if result.progress == .finished { return result.output }
      return result.output + (try translateCodecError { try codec.finish() ?? Data() })
    }

    private func readAll(source: Object, context: isolated Context) async throws -> Data {
      var provider = try FilterSource(object: source)
      var output = Data()
      while let chunk = try await provider.next(context: context) { output.append(chunk) }
      return output
    }

    private func filterNames(_ object: Object) throws -> [String] {
      if let name = object.value as? NameValue { return [name.value] }
      if let array = object.value as? ArrayValue {
        return try array.objects(in: array.range, for: .read).map {
          try $0.value(as: NameValue.self).value
        }
      }
      if let array = object.value as? PackedArrayValue {
        return try array.objects(in: array.range, for: .read).map {
          try $0.value(as: NameValue.self).value
        }
      }
      throw Error.typeCheck
    }

    private func decodeParameters(dictionary: FilterDictionary, count: Int) throws -> [FilterDictionary] {
      guard let object = try dictionary.object("DecodeParms") else {
        return Array(repeating: FilterDictionary(nil), count: count)
      }
      if let value = object.value as? DictionaryValue {
        guard count == 1 else { throw Error.typeCheck }
        return [FilterDictionary(value)]
      }
      let objects: [Object]
      if let array = object.value as? ArrayValue {
        objects = Array(try array.objects(in: array.range, for: .read))
      } else if let array = object.value as? PackedArrayValue {
        objects = Array(try array.objects(in: array.range, for: .read))
      } else {
        throw Error.typeCheck
      }
      guard objects.count == count else { throw Error.rangeCheck }
      return try objects.map { object in
        if object.type == .null { return FilterDictionary(nil) }
        return FilterDictionary(try object.value(as: DictionaryValue.self))
      }
    }
  }

}

private struct FilterDictionary: Sendable {

  let value: DictionaryValue?

  init(_ value: DictionaryValue?) {
    self.value = value
  }

  func object(_ key: Object) throws -> Object? {
    try value?.object(forKeyIfExists: key)
  }

  func boolean(_ key: Object, default defaultValue: Bool) throws -> Bool {
    guard let object = try object(key) else { return defaultValue }
    return try object.value(as: BooleanValue.self).value
  }

  func integer(_ key: Object, default defaultValue: Int) throws -> Int {
    guard let object = try object(key) else { return defaultValue }
    return Int(try object.value(as: IntegerValue.self).value)
  }

  func requiredInteger(_ key: Object) throws -> Int {
    guard let object = try object(key) else { throw Error.undefined }
    return Int(try object.value(as: IntegerValue.self).value)
  }

  func optionalInteger(_ key: Object) throws -> Int? {
    guard let object = try object(key) else { return nil }
    return Int(try object.value(as: IntegerValue.self).value)
  }

  func number(_ key: Object, default defaultValue: Double) throws -> Double {
    guard let object = try object(key) else { return defaultValue }
    return try object.value(as: NumericConvertible.self).real
  }

  func string(_ key: Object, default defaultValue: Data) throws -> Data {
    guard let object = try object(key) else { return defaultValue }
    let string = try object.value(as: StringValue.self)
    return try string.characters(in: string.range)
  }

  func integerArray(_ key: Object, default defaultValue: [Int]) throws -> [Int] {
    guard let object = try object(key) else { return defaultValue }
    if let string = object.value as? StringValue {
      try string.access.check(.read)
      return try string.characters(in: string.range).map(Int.init)
    }
    let values = try objects(in: object)
    return try values.map { Int(try $0.value(as: IntegerValue.self).value) }
  }

  func dataArray(_ key: Object, default defaultValue: [Data]) throws -> [Data] {
    guard let object = try object(key) else { return defaultValue }
    return try objects(in: object).map(byteSequence)
  }

  func huffmanTables(_ key: Object, default defaultValue: [DCTHuffmanTable]) throws
    -> [DCTHuffmanTable]
  {
    guard let object = try object(key) else { return defaultValue }
    return try objects(in: object).map { table in
      let bytes = try byteSequence(table)
      guard bytes.count >= 16 else { throw Error.rangeCheck }
      let counts = Data(bytes.prefix(16))
      let symbols = Data(bytes.dropFirst(16))
      return try translateCodecOption {
        try DCTHuffmanTable(codeCounts: counts, symbols: symbols)
      }
    }
  }

  private func objects(in object: Object) throws -> [Object] {
    if let array = object.value as? ArrayValue {
      return Array(try array.objects(in: array.range, for: .read))
    }
    if let array = object.value as? PackedArrayValue {
      return Array(try array.objects(in: array.range, for: .read))
    }
    throw Error.typeCheck
  }

  private func byteSequence(_ object: Object) throws -> Data {
    if let string = object.value as? StringValue {
      try string.access.check(.read)
      return try string.characters(in: string.range)
    }
    let values = try objects(in: object)
    return try Data(values.map { value in
      let number = try value.value(as: NumericConvertible.self).real
      guard number.isFinite, (0...255).contains(number) else { throw Error.rangeCheck }
      return UInt8(number.rounded())
    })
  }

}

private struct FilterSource {

  private enum Source {
    case file(FileValue)
    case string(StringValue, consumed: Bool)
    case procedure(Object)
  }

  private var source: Source

  init(object: Object) throws {
    switch object.value {
    case let file as FileValue:
      try file.checkReadable()
      source = .file(file)
    case let string as StringValue:
      try string.access.check(.read)
      source = .string(string, consumed: false)
    default:
      try object.checkProcedure()
      source = .procedure(object)
    }
  }

  mutating func next(context: isolated Context) async throws -> Data? {
    switch source {
    case .file(let file):
      return try await file.file.read(max: 1, context: context)
    case .string(let string, let consumed):
      guard !consumed else { return nil }
      source = .string(string, consumed: true)
      return try string.characters(in: string.range)
    case .procedure(let procedure):
      let originalDepth = context.operands.depth
      try await context.execute(proc: procedure)
      guard context.operands.depth == originalDepth + 1 else { throw Error.typeCheck }
      let string: StringValue = try context.operands.popAs()
      try string.access.check(.read)
      let data = try string.characters(in: string.range)
      return data.isEmpty ? nil : data
    }
  }

  func close(context: isolated Context) async throws {
    if case .file(let file) = source {
      try await file.file.close(context: context)
    }
  }

}

private final class NullEncoder: IncrementalFilter {

  private let finished = Mutex(false)

  func process(input: Data) throws -> IncrementalFilterResult {
    guard !finished.withLock({ $0 }) else { throw StreamCodecError.invalidData }
    return IncrementalFilterResult(output: input, consumedInput: input.count, progress: .needsInput)
  }

  func finish() throws -> Data? {
    finished.withLock { finished in
      guard !finished else { return nil }
      finished = true
      return Data()
    }
  }

}

private final class SubFileDecoder: IncrementalFilter {

  private struct State: Sendable {
    var input = Data()
    var finished = false
  }

  private let eodCount: Int
  private let eodString: Data
  private let state = Mutex(State())

  init(eodCount: Int, eodString: Data) throws {
    guard eodCount >= 0 else { throw StreamCodecError.invalidOption("EODCount") }
    guard eodCount == 0 || !eodString.isEmpty else {
      throw StreamCodecError.invalidOption("EODString")
    }
    self.eodCount = eodCount
    self.eodString = eodString
  }

  func process(input: Data) throws -> IncrementalFilterResult {
    state.withLock { state in
      guard !state.finished else {
        return IncrementalFilterResult(output: Data(), consumedInput: 0, progress: .finished)
      }
      let previousCount = state.input.count
      state.input.append(input)
      guard eodCount > 0,
            let end = Self.endOffset(in: state.input, marker: eodString, count: eodCount)
      else {
        return IncrementalFilterResult(
          output: Data(),
          consumedInput: input.count,
          progress: .needsInput
        )
      }
      let output = Data(state.input.prefix(end.outputEnd))
      state.finished = true
      return IncrementalFilterResult(
        output: output,
        consumedInput: max(0, end.consumedEnd - previousCount),
        progress: .finished
      )
    }
  }

  func finish() throws -> Data? {
    state.withLock { state in
      guard !state.finished else { return nil }
      state.finished = true
      return state.input
    }
  }

  private static func endOffset(
    in data: Data,
    marker: Data,
    count: Int
  ) -> (outputEnd: Int, consumedEnd: Int)? {
    guard data.count >= marker.count else { return nil }
    var matches = 0
    var index = 0
    while index + marker.count <= data.count {
      if data[index..<(index + marker.count)].elementsEqual(marker) {
        matches += 1
        if matches == count { return (index, index + marker.count) }
      }
      index += 1
    }
    return nil
  }

}

private final class PredictingEncoder: IncrementalFilter {

  private let codec: any IncrementalFilter
  private let predictor: PredictorEncoder

  init(codec: any IncrementalFilter, options: PredictorOptions) {
    self.codec = codec
    predictor = PredictorEncoder(options: options)
  }

  func process(input: Data) throws -> IncrementalFilterResult {
    let predicted = try predictor.process(input: input)
    let result = try codec.process(input: predicted.output)
    guard result.consumedInput == predicted.output.count else { throw StreamCodecError.invalidData }
    return IncrementalFilterResult(
      output: result.output,
      consumedInput: input.count,
      progress: .needsInput
    )
  }

  func flush() throws -> Data {
    try codec.flush()
  }

  func finish() throws -> Data? {
    let predicted = try predictor.finish() ?? Data()
    let result = try codec.process(input: predicted)
    guard result.consumedInput == predicted.count else { throw StreamCodecError.invalidData }
    return result.output + (try codec.finish() ?? Data())
  }

}

private final class PredictingDecoder: IncrementalFilter {

  private let codec: any IncrementalFilter
  private let predictor: PredictorDecoder

  init(codec: any IncrementalFilter, options: PredictorOptions) {
    self.codec = codec
    predictor = PredictorDecoder(options: options)
  }

  func process(input: Data) throws -> IncrementalFilterResult {
    let result = try codec.process(input: input)
    let predicted = try predictor.process(input: result.output)
    var output = predicted.output
    if result.progress == .finished {
      output.append(try predictor.finish() ?? Data())
    }
    return IncrementalFilterResult(
      output: output,
      consumedInput: result.consumedInput,
      progress: result.progress
    )
  }

  func flush() throws -> Data {
    let output = try codec.flush()
    return try predictor.process(input: output).output
  }

  func finish() throws -> Data? {
    guard let output = try codec.finish() else { return nil }
    var decoded = try predictor.process(input: output).output
    decoded.append(try predictor.finish() ?? Data())
    return decoded
  }

}

private extension Object {

  var vmIfComposite: VM {
    (value as? any CompositeValue)?.vm ?? .global
  }

}
