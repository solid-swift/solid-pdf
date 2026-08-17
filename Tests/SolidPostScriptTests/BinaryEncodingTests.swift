import Foundation
import SolidIO
@testable import SolidPostScript
import Testing

@Suite
struct BinaryEncodingTests {
  @Test
  func objectFormatDefaultsValidatesAndRestores() async throws {
    let initial: IntegerValue = try await Interpreter.result(content: "currentobjectformat")
    #expect(initial.value == 0)

    let restored: IntegerValue = try await Interpreter.result(
      content: "1 setobjectformat save 2 setobjectformat restore currentobjectformat"
    )
    #expect(restored.value == 1)

    for invalid in [-1, 5] {
      await #expect(throws: Error.rangeCheck) {
        try await Interpreter.execute(content: "\(invalid) setobjectformat")
      }
    }

    let registered: [BooleanValue] = try await Interpreter.result(
      content:
        "systemdict /setobjectformat known systemdict /currentobjectformat known "
        + "systemdict /printobject known systemdict /writeobject known",
      count: 4
    )
    for value in registered {
      #expect(value.value)
    }
  }

  @Test
  func binaryIntegerRealBooleanAndStringTokens() async throws {
    var data = enabledPrefix
    data.append(contentsOf: [132, 0, 0, 0, 42])
    data.append(contentsOf: [135, 0xFE, 0xFF])
    data.append(contentsOf: [136, 0x80])
    data.append(138)
    var real = BinaryDataWriter()
    real.appendUInt32(Float(1.5).bitPattern, order: .bigEndian)
    data.append(real.data)
    data.append(contentsOf: [141, 1, 142, 3, 65, 66, 67])

    let results = try await execute(data)
    #expect(try results[0].value(as: StringValue.self).string == "ABC")
    #expect(try results[1].value(as: BooleanValue.self).value)
    #expect(try results[2].value(as: RealValue.self).value == 1.5)
    #expect(try results[3].value(as: IntegerValue.self).value == -128)
    #expect(try results[4].value(as: IntegerValue.self).value == -2)
    #expect(try results[5].value(as: IntegerValue.self).value == 42)
  }

  @Test
  func fixedPointAndHomogeneousArrayTokens() async throws {
    var data = enabledPrefix
    data.append(contentsOf: [137, 33, 0x01, 0x01])
    data.append(contentsOf: [149, 32, 0, 2, 0xFF, 0xFF, 0x01, 0x02])

    let results = try await execute(data)
    let array = try results[0].value(as: ArrayValue.self)
    #expect(try array.object(at: 0).value(as: IntegerValue.self).value == -1)
    #expect(try array.object(at: 1).value(as: IntegerValue.self).value == 258)
    #expect(try results[1].value(as: RealValue.self).value == 128.5)
  }

  @Test
  func encodedSystemNamesUseAppendixFAndReportGaps() async throws {
    #expect(SystemNameTable.count == 451)
    #expect(SystemNameTable.name(at: 0) == "abs")
    #expect(SystemNameTable.name(at: 225) == "setpattern")
    #expect(SystemNameTable.name(at: 226) == nil)
    #expect(SystemNameTable.name(at: 255) == nil)
    #expect(SystemNameTable.name(at: 256) == "=")
    #expect(SystemNameTable.name(at: 480) == "DeviceN")

    var executable = Data("2 3 1 setobjectformat ".utf8)
    executable.append(contentsOf: [146, 1])
    let sum = try await execute(executable)
    #expect(try sum[0].value(as: IntegerValue.self).value == 5)

    var undefined = Data("errordict /undefined { 1 array astore /captured exch def } put 1 setobjectformat ".utf8)
    undefined.append(contentsOf: [145, 226])
    undefined.append(Data(" captured 0 get".utf8))
    let undefinedResults = try await execute(undefined)
    let command = try #require(undefinedResults.first)
    #expect(try command.value(as: NameValue.self).value == "system226")
    #expect(command.kind == .executable)
  }

  @Test
  func encodedCompatibilityNamesResolveToGlobalVMFacilities() async throws {
    var input = Data("true 1 setobjectformat ".utf8)
    input.append(contentsOf: [146, 158])
    input.append(contentsOf: [146, 42])
    input.append(contentsOf: [146, 159])
    input.append(Data(" gcheck 7 ".utf8))
    input.append(immediateSystemNameSequence(index: 336))

    let checks = try await execute(input)
    #expect(checks.count == 3)
    for check in checks {
      #expect(try check.value(as: BooleanValue.self).value)
    }
  }

  @Test
  func disabledBinaryBytesRemainAsciiNameCharacters() throws {
    let scanner = try Scanner(content: Data([132, 65]))
    #expect(try scanner.nextToken() == .name("\u{84}A", kind: .executable))
  }

  @Test
  func malformedBinaryTokensUseDescriptiveErrorCommands() async throws {
    var data = Data("errordict /syntaxerror { /captured exch def } put 1 setobjectformat ".utf8)
    data.append(150)
    data.append(Data(" captured".utf8))

    let command = try await execute(data)[0]
    #expect(try command.value(as: StringValue.self).string == "bin token, type=150")
  }

  @Test
  func binaryObjectSequencesExecuteImmediately() async throws {
    var data = enabledPrefix
    data.append(contentsOf: integerSequence(42))

    let results = try await execute(data)
    #expect(try results[0].value(as: IntegerValue.self).value == 42)
  }

  @Test
  func binaryObjectSequencesRemainArraysWhenDeferredOrTokenized() async throws {
    var deferred = Data("1 setobjectformat {".utf8)
    deferred.append(contentsOf: integerSequence(42))
    deferred.append(Data("} 0 get type".utf8))
    let type = try await execute(deferred)[0]
    #expect(try type.value(as: NameValue.self).value == "arraytype")

    let sequence = Data(integerSequence(42))
    let hex = sequence.map { String(format: "%02x", $0) }.joined()
    let tokenized = try await Interpreter.results(content: "1 setobjectformat <\(hex)> token")
    #expect(try tokenized[0].value(as: BooleanValue.self).value)
    #expect(tokenized[1].type == .array)
    #expect(tokenized[1].kind == .executable)
  }

  @Test
  func objectSequenceImmediateNamesAndRecursiveArrays() async throws {
    var immediate = Data("2 3 1 setobjectformat ".utf8)
    immediate.append(contentsOf: immediateSystemNameSequence(index: 1))
    let sum = try await execute(immediate)
    #expect(try sum[0].value(as: IntegerValue.self).value == 5)

    var recursive = enabledPrefix
    recursive.append(contentsOf: recursiveArraySequence())
    let arrayObject = try await execute(recursive)[0]
    let array = try arrayObject.value(as: ArrayValue.self)
    #expect(try array.object(at: 0) == arrayObject)
  }

  @Test
  func writeObjectProducesAllFormatsAndRoundTripsValues() async throws {
    for format in ObjectFormat.allEnabled {
      let file = DataFile(data: Data(), mode: .readWrite)
      let context = Context()
      try await context.writeObjectForTest(.integer(42), tag: 0, format: format, file: file)
      try file.setOffset(0)
      let size = try file.size
      let output = try file.read(max: size)
      let encoded = try #require(output)
      #expect(encoded.first == format.sequenceToken)

      var input = Data("\(format.rawValue) setobjectformat ".utf8)
      input.append(encoded)
      let decoded = try await execute(input)
      #expect(try decoded[0].value(as: IntegerValue.self).value == 42)
    }
  }

  @Test
  func structuredOutputRoundTripsEverySupportedObjectType() async throws {
    let nested = try Object.array([.integer(9)], access: .unlimited, vm: .local, kind: .literal)
    let value = try Object.array(
      [
        .null,
        .integer(-42),
        try .real(1.25),
        .name("value", kind: .executable),
        .boolean(true),
        .string("text", access: .unlimited, vm: .local, kind: .executable),
        nested,
        .mark,
      ],
      access: .unlimited,
      vm: .local,
      kind: .literal
    )
    let file = DataFile(data: Data(), mode: .readWrite)
    try await Context().writeObjectForTest(value, tag: 0, format: .ieeeLittleEndian, file: file)
    try file.setOffset(0)
    let size = try file.size
    let output = try file.read(max: size)
    let data = try #require(output)
    var input = Data("2 setobjectformat ".utf8)
    input.append(data)
    let decoded = try await execute(input)[0].value(as: ArrayValue.self)

    #expect(decoded.count == 8)
    #expect(try decoded.object(at: 0).type == .null)
    #expect(try decoded.object(at: 1).value(as: IntegerValue.self).value == -42)
    #expect(try decoded.object(at: 2).value(as: RealValue.self).value == 1.25)
    #expect(try decoded.object(at: 3).value(as: NameValue.self).value == "value")
    #expect(try decoded.object(at: 3).kind == .executable)
    #expect(try decoded.object(at: 4).value(as: BooleanValue.self).value)
    #expect(try decoded.object(at: 5).value(as: StringValue.self).string == "text")
    #expect(try decoded.object(at: 5).kind == .executable)
    #expect(try decoded.object(at: 6).type == .array)
    #expect(try decoded.object(at: 7).type == .mark)
  }

  @Test
  func writeObjectTagsTypesAndCyclesAreValidated() async throws {
    let taggedFile = DataFile(data: Data(), mode: .readWrite)
    let context = Context()
    try await context.writeObjectForTest(.literalName("value"), tag: 255, format: .ieeeBigEndian, file: taggedFile)
    try taggedFile.setOffset(0)
    let size = try taggedFile.size
    let output = try taggedFile.read(max: size)
    let tagged = try #require(output)
    #expect(tagged[5] == 255)

    await #expect(throws: Error.typeCheck) {
      let file = DataFile(data: Data(), mode: .readWrite)
      try await Context().writeObjectForTest(
        .packedArray([.integer(1)], vm: .local, kind: .literal),
        tag: 0,
        format: .ieeeBigEndian,
        file: file
      )
    }

    let array = try ArrayValue(elements: [.null], access: .unlimited, vm: .local)
    try array.updateObject(Object(value: array, kind: .literal), at: 0)
    await #expect(throws: Error.limitCheck) {
      let file = DataFile(data: Data(), mode: .readWrite)
      try await Context().writeObjectForTest(
        Object(value: array, kind: .literal),
        tag: 0,
        format: .ieeeBigEndian,
        file: file
      )
    }
  }

  @Test
  func encodedNumberStringsAreDecodedWithoutChangingStringObjects() throws {
    let data = Data([149, 160, 2, 0, 0xFF, 0xFF, 0x02, 0x01])
    let values = try EncodedNumberString.decode(data)
    #expect(try values[0].value(as: IntegerValue.self).value == -1)
    #expect(try values[1].value(as: IntegerValue.self).value == 258)

    let string = Object.string(data, access: .unlimited, vm: .local, kind: .literal)
    #expect(string.type == .string)
  }

  @Test
  func everyHomogeneousNumberRepresentationIsAccepted() throws {
    let representations: [UInt8] = [0, 31, 32, 47, 48, 49, 128, 159, 160, 175, 176, 177]
    for representation in representations {
      var data = Data([149, representation])
      let order: ObjectFormat.ByteOrder = representation < 128 ? .bigEndian : .littleEndian
      var header = BinaryDataWriter()
      header.appendUInt16(1, order: order)
      data.append(header.data)

      switch representation {
      case 32...47, 160...175:
        data.append(contentsOf: [0, 0])
      case 49, 177:
        var native = Float(0)
        data.append(withUnsafeBytes(of: &native) { Data($0) })
      default:
        data.append(contentsOf: [0, 0, 0, 0])
      }

      let values = try EncodedNumberString.decode(data)
      #expect(values.count == 1)
    }
  }

  @Test
  func malformedAndTruncatedBinaryInputProducesSyntaxError() async throws {
    let malformedNullRecord = Data([128, 1, 0, 12, 0, 0, 0, 1, 0, 0, 0, 0])
    let invalidArrayOffset = Data([128, 1, 0, 12, 9, 0, 0, 1, 0, 0, 0, 1])
    let trailingByte = Data([128, 1, 0, 13, 0, 0, 0, 0, 0, 0, 0, 0, 255])
    let malformedUnreferencedRecord = Data([
      128, 1, 0, 20,
      0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 1, 0, 0, 0, 0,
    ])
    for suffix in [
      Data([147]),
      Data([148]),
      Data([159]),
      Data([132, 0]),
      Data([141, 2]),
      Data([137, 64]),
      malformedNullRecord,
      invalidArrayOffset,
      trailingByte,
      malformedUnreferencedRecord,
    ] {
      var data = enabledPrefix
      data.append(suffix)
      do {
        _ = try await execute(data)
        Issue.record("Expected syntaxerror for \(Array(suffix))")
      } catch let error as Error {
        #expect(error == .syntaxError)
      }
    }
  }

  @Test
  func binaryCompositesUseTheCurrentAllocationMode() async throws {
    var stringInput = Data("true setglobal 1 setobjectformat ".utf8)
    stringInput.append(contentsOf: [142, 1, 65])
    stringInput.append(Data(" gcheck".utf8))
    #expect(try await execute(stringInput)[0].value(as: BooleanValue.self).value)

    var sequenceInput = Data("true setglobal 1 setobjectformat ".utf8)
    sequenceInput.append(contentsOf: stringSequence("A"))
    sequenceInput.append(Data(" gcheck".utf8))
    #expect(try await execute(sequenceInput)[0].value(as: BooleanValue.self).value)
  }

  @Test
  func structuredOutputUsesExtendedHeadersAndPreservesSharing() async throws {
    let largeString = Object.string(
      Data(repeating: 65, count: Int(UInt16.max)),
      access: .unlimited,
      vm: .local,
      kind: .literal
    )
    let largeFile = DataFile(data: Data(), mode: .readWrite)
    try await Context().writeObjectForTest(
      largeString,
      tag: 0,
      format: .ieeeBigEndian,
      file: largeFile
    )
    try largeFile.setOffset(0)
    let largeSize = try largeFile.size
    let largeData = try largeFile.read(max: largeSize)
    let largeOutput = try #require(largeData)
    #expect(largeOutput[1] == 0)

    let shared = try Object.array([.integer(7)], access: .unlimited, vm: .local, kind: .literal)
    let outer = try Object.array([shared, shared], access: .unlimited, vm: .local, kind: .literal)
    let sharedFile = DataFile(data: Data(), mode: .readWrite)
    try await Context().writeObjectForTest(outer, tag: 0, format: .ieeeBigEndian, file: sharedFile)
    try sharedFile.setOffset(0)
    let sharedSize = try sharedFile.size
    let sharedData = try sharedFile.read(max: sharedSize)
    let output = try #require(sharedData)
    var input = enabledPrefix
    input.append(output)
    let decoded = try await execute(input)[0].value(as: ArrayValue.self)
    #expect(try decoded.object(at: 0) == decoded.object(at: 1))
  }

  @Test
  func binaryHandleErrorIsOptInAndUsesTag250() async throws {
    let silentOutput = DataSink()
    let silentContext = Context(environment: InterpreterEnvironment(standardOutput: silentOutput))
    try await silentContext.executeForTest("1 setobjectformat {doesnotexist} stopped pop errordict /handleerror get exec")
    #expect(silentOutput.data.isEmpty)

    let binaryOutput = DataSink()
    let binaryContext = Context(environment: InterpreterEnvironment(standardOutput: binaryOutput))
    try await binaryContext.executeForTest(
      "1 setobjectformat $error /binary true put {doesnotexist} stopped pop errordict /handleerror get exec"
    )
    let bytes = binaryOutput.data
    #expect(bytes[0] == 128)
    #expect(bytes[5] == 250)

    var decodable = bytes
    decodable[5] = 0
    var input = enabledPrefix
    input.append(decodable)
    let report = try await execute(input)[0].value(as: ArrayValue.self)
    #expect(try report.object(at: 0).value(as: NameValue.self).value == "Error")
    #expect(try report.object(at: 1).value(as: NameValue.self).value == "undefined")
    #expect(try report.object(at: 2).value(as: NameValue.self).value == "doesnotexist")
    #expect(try !report.object(at: 3).value(as: BooleanValue.self).value)

    let state = try await binaryContext.errorStateForTest()
    #expect(try !state.objectValue(forKey: "newerror", as: BooleanValue.self).value)
    #expect(try state.object(forKey: "errorinfo").type == .null)
    #expect(try state.objectValue(forKey: "binary", as: BooleanValue.self).value)
  }

  @Test
  func printObjectUsesStandardOutputAndStructuredOutputValidatesOperands() async throws {
    let output = DataSink()
    let context = Context(environment: InterpreterEnvironment(standardOutput: output))
    try await context.executeForTest("1 setobjectformat 42 7 printobject")
    let data = output.data
    #expect(data[5] == 7)

    await #expect(throws: Error.rangeCheck) {
      try await Context().writeObjectForTest(
        .integer(1),
        rawTag: -1,
        format: .ieeeBigEndian,
        file: DataFile(data: Data(), mode: .readWrite)
      )
    }
    await #expect(throws: Error.invalidAccess) {
      try await Context().writeObjectForTest(
        .integer(1),
        rawTag: 0,
        format: .ieeeBigEndian,
        file: DataFile(data: Data(), mode: .readWrite),
        access: .readOnly
      )
    }
    await #expect(throws: Error.undefined) {
      try await Context().writeObjectForTest(
        .integer(1),
        rawTag: 0,
        format: .disabled,
        file: DataFile(data: Data(), mode: .readWrite)
      )
    }
  }

  @Test
  func objectFormatIsIsolatedAcrossConcurrentContexts() async throws {
    try await withThrowingTaskGroup(of: Int32.self) { group in
      for value in 0...4 {
        group.addTask {
          let result: IntegerValue = try await Interpreter.result(
            content: "\(value) setobjectformat currentobjectformat"
          )
          return result.value
        }
      }

      var values: [Int32] = []
      for try await value in group {
        values.append(value)
      }
      #expect(values.sorted() == [0, 1, 2, 3, 4])
    }
  }

  private var enabledPrefix: Data { Data("1 setobjectformat ".utf8) }

  private func execute(_ data: Data) async throws -> [Object] {
    let context = try await Interpreter.execute(file: DataFile(data: data, mode: .read))
    return try await context.results()
  }

  private func integerSequence(_ value: Int32) -> Data {
    var writer = BinaryDataWriter()
    writer.append(128)
    writer.append(1)
    writer.appendUInt16(12, order: .bigEndian)
    writer.append(1)
    writer.append(0)
    writer.appendUInt16(0, order: .bigEndian)
    writer.appendInt32(value, order: .bigEndian)
    return writer.data
  }

  private func immediateSystemNameSequence(index: UInt32) -> Data {
    var writer = BinaryDataWriter()
    writer.append(128)
    writer.append(1)
    writer.appendUInt16(12, order: .bigEndian)
    writer.append(6)
    writer.append(0)
    writer.appendInt16(-1, order: .bigEndian)
    writer.appendUInt32(index, order: .bigEndian)
    return writer.data
  }

  private func stringSequence(_ value: String) -> Data {
    let bytes = Data(value.utf8)
    var writer = BinaryDataWriter()
    writer.append(128)
    writer.append(1)
    writer.appendUInt16(UInt16(12 + bytes.count), order: .bigEndian)
    writer.append(5)
    writer.append(0)
    writer.appendUInt16(UInt16(bytes.count), order: .bigEndian)
    writer.appendUInt32(8, order: .bigEndian)
    writer.append(bytes)
    return writer.data
  }

  private func recursiveArraySequence() -> Data {
    var writer = BinaryDataWriter()
    writer.append(128)
    writer.append(1)
    writer.appendUInt16(20, order: .bigEndian)
    for _ in 0..<2 {
      writer.append(9)
      writer.append(0)
      writer.appendUInt16(1, order: .bigEndian)
      writer.appendUInt32(8, order: .bigEndian)
    }
    return writer.data
  }
}

private extension ObjectFormat {
  static let allEnabled: [Self] = [
    .ieeeBigEndian,
    .ieeeLittleEndian,
    .nativeBigEndian,
    .nativeLittleEndian,
  ]
}

private extension Context {
  func writeObjectForTest(
    _ object: Object,
    tag: UInt8,
    format: ObjectFormat,
    file: DataFile
  ) async throws {
    try await writeObjectForTest(object, rawTag: Int32(tag), format: format, file: file)
  }

  func writeObjectForTest(
    _ object: Object,
    rawTag: Int32,
    format: ObjectFormat,
    file: DataFile,
    access: ObjectAccess = .unlimited
  ) async throws {
    objectFormat = format
    operands.push(contentsOf: [
      .integer(rawTag),
      object,
      .file(file, access: access, vm: .local, kind: .literal),
    ])
    try await Operators.WriteObject.instance.execute(context: self)
  }

  func executeForTest(_ content: String) async throws {
    let source = Object.file(
      DataFile(data: Data(content.utf8), mode: .read),
      access: .readOnly,
      vm: .local,
      kind: .executable
    )
    try await pushAndRun(source: source)
  }

  func errorStateForTest() throws -> DictionaryValue {
    try dictionaries.systemDictionary().objectValue(forKey: "$error", as: DictionaryValue.self)
  }
}
