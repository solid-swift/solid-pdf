//
//  FilteredFileTests.swift
//  SolidPostScriptTests
//
//  Created by Codex on 8/15/26.
//

import Foundation
@testable import SolidPostScript
import SolidIO
import Testing

@Suite
struct FilteredFileTests {

  @Test
  func registersFilterAndAllStandardResources() async throws {
    let systemDictionary: DictionaryValue = try await Interpreter.result(content: "systemdict")
    #expect(try systemDictionary.object(forKey: "filter").value is Operators.Filter)

    for name in [
      "ASCIIHexEncode", "ASCIIHexDecode", "ASCII85Encode", "ASCII85Decode",
      "LZWEncode", "LZWDecode", "FlateEncode", "FlateDecode",
      "RunLengthEncode", "RunLengthDecode", "CCITTFaxEncode", "CCITTFaxDecode",
      "DCTEncode", "DCTDecode", "NullEncode", "SubFileDecode", "ReusableStreamDecode",
    ] {
      do {
        let result: NameValue = try await Interpreter.result(
          content: "/\(name) /Filter findresource"
        )
        #expect(result.value == name)
      } catch {
        Issue.record("Failed Filter resource \(name): \(error)")
      }
    }
  }

  @Test
  func asciiHexStringSourceAndTarget() async throws {
    let decoded: StringValue = try await Interpreter.result(
      content: "(48656c6c6f>) /ASCIIHexDecode filter 5 string readstring pop"
    )
    #expect(decoded.string == "Hello")

    let encoded: StringValue = try await Interpreter.result(
      content: """
        /output 20 string def
        output /ASCIIHexEncode filter dup (Hi) writestring closefile
        output 0 5 getinterval
        """
    )
    #expect(encoded.string == "4869>")
  }

  @Test
  func ascii85ProcedureSource() async throws {
    let decoded: StringValue = try await Interpreter.result(
      content: """
        /first true def
        { first { /first false def (87cURD]j7BEbo80~>) } { () } ifelse }
        /ASCII85Decode filter 12 string readstring pop
        """
    )
    #expect(decoded.string == "Hello world!")
  }

  @Test
  func decodingFilterConstructionIsLazy() async throws {
    let calls: IntegerValue = try await Interpreter.result(
      content: """
        /calls 0 def
        /source { /calls calls 1 add def (61>) } def
        /decoded /source load /ASCIIHexDecode filter def
        calls
        """
    )
    #expect(calls.value == 0)
  }

  @Test
  func procedureTargetUsesBufferExchangeAndFinalFalseCallback() async throws {
    let results = try await Interpreter.results(
      content: """
        /chunks 2 array def
        /index 0 def
        /target {
          /more exch def
          /data exch def
          data length 0 gt {
            chunks index data put
            /index index 1 add def
          } if
          4 string
        } def
        /target load /ASCIIHexEncode filter dup (Hi) writestring closefile
        chunks 0 get chunks 1 get
        """
    )
    let strings = results.compactMap { $0.value as? StringValue }
    #expect(strings.map(\.string) == [">", "4869"])
  }

  @Test
  func executableSequentialFilterDoesNotRequireSeeking() async throws {
    let result: IntegerValue = try await Interpreter.result(
      content: "(32203320616464>) /ASCIIHexDecode filter cvx exec"
    )
    #expect(result.value == 5)
  }

  @Test
  func executableProcedureBackedFilterUsesContextualScanner() async throws {
    let result: IntegerValue = try await Interpreter.result(
      content: """
        /first true def
        { first { /first false def (32203320616464>) } { () } ifelse }
        /ASCIIHexDecode filter cvx exec
        """
    )
    #expect(result.value == 5)
  }

  @Test
  func flateFileRoundTripAndDirectionChecks() async throws {
    let encodedURL = temporaryURL()
    defer { try? FileManager.default.removeItem(at: encodedURL) }

    _ = try await Interpreter.execute(
      content: """
        (\(encodedURL.path)) (w) file /FlateEncode filter
        dup (filtered data) writestring closefile
        """
    )

    let result: StringValue = try await Interpreter.result(
      content: """
        (\(encodedURL.path)) (r) file /FlateDecode filter
        13 string readstring pop
        """
    )
    #expect(result.string == "filtered data")

    let checks = try await Interpreter.results(
      content: "(\(encodedURL.path)) (r) file /FlateDecode filter dup rcheck exch wcheck"
    )
    let booleans = checks.compactMap { ($0.value as? BooleanValue)?.value }
    #expect(booleans == [false, true])
  }

  @Test(arguments: ["LZW", "RunLength"])
  func binaryCodecRoundTrip(codec: String) async throws {
    let encodedURL = temporaryURL()
    defer { try? FileManager.default.removeItem(at: encodedURL) }
    let encoder = codec == "RunLength"
      ? "0 /RunLengthEncode filter"
      : "/LZWEncode filter"

    _ = try await Interpreter.execute(
      content: """
        (\(encodedURL.path)) (w) file \(encoder)
        dup (filtered data) writestring closefile
        """
    )

    let result: StringValue = try await Interpreter.result(
      content: """
        (\(encodedURL.path)) (r) file /\(codec)Decode filter
        13 string readstring pop
        """
    )
    #expect(result.string == "filtered data")
  }

  @Test
  func nullEncodeCopiesBytes() async throws {
    let encodedURL = temporaryURL()
    defer { try? FileManager.default.removeItem(at: encodedURL) }

    _ = try await Interpreter.execute(
      content: """
        (\(encodedURL.path)) (w) file /NullEncode filter
        dup (unchanged) writestring closefile
        """
    )

    #expect(try Data(contentsOf: encodedURL) == Data("unchanged".utf8))
  }

  @Test
  func closeSourceAndCloseTargetPropagateToFiles() async throws {
    let sourceURL = temporaryURL()
    let targetURL = temporaryURL()
    defer {
      try? FileManager.default.removeItem(at: sourceURL)
      try? FileManager.default.removeItem(at: targetURL)
    }
    try Data("61>".utf8).write(to: sourceURL)

    let source: FileValue = try await Interpreter.result(
      content: """
        /source (\(sourceURL.path)) (r) file def
        source << /CloseSource true >> /ASCIIHexDecode filter pop
        source
        """
    )
    #expect(source.file.isClosed)

    let target: FileValue = try await Interpreter.result(
      content: """
        /target (\(targetURL.path)) (w) file def
        target << /CloseTarget true >> /ASCIIHexEncode filter closefile
        target
        """
    )
    #expect(target.file.isClosed)
  }

  @Test
  func closeSourceWaitsUntilDecodedEOD() async throws {
    let sourceURL = temporaryURL()
    defer { try? FileManager.default.removeItem(at: sourceURL) }
    try Data("61>tail".utf8).write(to: sourceURL)

    let results = try await Interpreter.results(
      content: """
        /source (\(sourceURL.path)) (r) file def
        /decoded source << /CloseSource true >> /ASCIIHexDecode filter def
        source status
        decoded read pop pop
        decoded read pop
        source status
        """
    )
    let booleans = results.compactMap { ($0.value as? BooleanValue)?.value }
    #expect(booleans == [false, true])
  }

  @Test
  func ordinaryAndReusablePositioning() async throws {
    await #expect(throws: Error.ioError) {
      try await Interpreter.execute(
        content: "(4869>) /ASCIIHexDecode filter fileposition"
      )
    }

    let result: StringValue = try await Interpreter.result(
      content: """
        (abcdef) /ReusableStreamDecode filter
        dup 3 setfileposition dup 0 setfileposition
        6 string readstring pop
        """
    )
    #expect(result.string == "abcdef")

    let nested: StringValue = try await Interpreter.result(
      content: """
        (343836393e>) << /Filter /ASCIIHexDecode /AsyncRead true >>
        /ReusableStreamDecode filter 5 string readstring pop
        """
    )
    #expect(nested.string == "4869>")
  }

  @Test
  func subFileOverlapAndCount() async throws {
    let result: StringValue = try await Interpreter.result(
      content: """
        (xxabababtail) 2 (abab) /SubFileDecode filter
        10 string readstring pop
        """
    )
    #expect(result.string == "xxab")
  }

  @Test
  func malformedCodecDataUsesErrorLifecycle() async throws {
    let results = try await Interpreter.results(
      content: """
        { (!!!!) /FlateDecode filter 1 string readstring } stopped
        $error /errorname get
        """
    )
    #expect(results.contains { ($0.value as? BooleanValue)?.value == true })
    #expect(results.contains { ($0.value as? NameValue)?.value == "ioerror" })
  }

  @Test
  func progressiveDCTFailureIsLazyAndUsesErrorLifecycle() async throws {
    let results = try await Interpreter.results(
      content: """
        /decoder <FFD8FFC20002> /DCTDecode filter def
        { decoder read } stopped
        $error /errorname get
        """
    )
    #expect(results.contains { ($0.value as? BooleanValue)?.value == true })
    #expect(results.contains { ($0.value as? NameValue)?.value == "ioerror" })
  }

  @Test
  func dctDecodeBudgetUsesRetainedVMDomain() async throws {
    let encodedURL = temporaryURL()
    defer { try? FileManager.default.removeItem(at: encodedURL) }

    let codec = DCTEncoder(
      options: try DCTEncodeOptions(columns: 1_024, rows: 1_024, colors: 1, colorTransform: 0)
    )
    let result = try codec.process(input: Data(repeating: 127, count: 1_024 * 1_024))
    var encoded = result.output
    encoded.append(try codec.finish() ?? Data())
    try encoded.write(to: encodedURL)

    let results = try await Interpreter.results(
      content: """
        << /MaxLocalVM 200000 >> setuserparams
        { (\(encodedURL.path)) (r) file /DCTDecode filter read } stopped
        $error /errorname get
        """
    )
    #expect(results.contains { ($0.value as? BooleanValue)?.value == true })
    #expect(results.contains { ($0.value as? NameValue)?.value == "limitcheck" })
  }

  @Test
  func codecLimitErrorsTranslateToLimitcheck() {
    #expect(throws: Error.limitCheck) {
      try translateCodecError { () throws -> Void in
        throw StreamCodecError.limitExceeded
      }
    }
  }

  @Test
  func parameterErrorsUseLanguageErrors() async throws {
    await #expect(throws: Error.rangeCheck) {
      try await Interpreter.execute(
        content: "(data) << /EarlyChange 2 >> /LZWDecode filter"
      )
    }
    await #expect(throws: Error.typeCheck) {
      try await Interpreter.execute(
        content: "(data) << /CloseSource 1 >> /ASCIIHexDecode filter"
      )
    }
    await #expect(throws: Error.invalidAccess) {
      try await Interpreter.execute(
        content: "(data) noaccess /ASCIIHexDecode filter"
      )
    }
  }

  @Test
  func dctParametersAcceptEveryPLRMSequenceRepresentation() async throws {
    let stopped: BooleanValue = try await Interpreter.result(
      content: """
        /samples 1 string def samples 0 1 put
        /quant 64 string def quant 0 2 put
        /huff 17 string def huff 0 1 put
        {
          128 string <<
            /Columns 1 /Rows 1 /Colors 1
            /HSamples samples /VSamples [1]
            /QuantTables [quant]
            /HuffTables [huff]
            /QFactor 0 /ColorTransform 0
          >> /DCTEncode filter pop
        } stopped
        """
    )
    #expect(stopped.value == false)

    let decodeStopped: BooleanValue = try await Interpreter.result(
      content: """
        /samples 1 string def samples 0 1 put
        /quant 64 string def quant 0 2 put
        /huff 17 string def huff 0 1 put
        {
          () <<
            /Colors 1 /HSamples [1] /VSamples samples
            /QuantTables [quant] /HuffTables [huff]
          >> /DCTDecode filter pop
        } stopped
        """
    )
    #expect(decodeStopped.value == false)
  }

  @Test
  func dctEncoderClosesAtDeclaredSampleCount() async throws {
    let results = try await Interpreter.results(
      content: """
        /target 1024 string def
        /encoded target << /Columns 1 /Rows 1 /Colors 1 >> /DCTEncode filter def
        encoded 0 write
        encoded
        { encoded 0 write } stopped
        """
    )
    let stopped = try #require(results.first?.value as? BooleanValue)
    let encoded = try #require(results.compactMap { $0.value as? FileValue }.first)
    #expect(stopped.value == true)
    #expect(encoded.file.isClosed)
  }

  @Test
  func restoreClosesNewLocalFilteredFiles() async throws {
    let context = Context()
    let snapshot = try await context.snapshot()
    let file = MaterializedFilterFile(
      data: Data("data".utf8),
      name: "test",
      positionable: false,
      closeAtEnd: true
    )
    await context.register(file: file, vm: .local)

    try await snapshot.restore(to: context)

    #expect(file.isClosed)
  }

  @Test
  func filterVMFollowsRetainedCompositeObjects() async throws {
    let results = try await Interpreter.results(
      content: """
        false setglobal (61>) /ASCIIHexDecode filter gcheck
        true setglobal (61>) /ASCIIHexDecode filter gcheck
        """
    )
    let booleans = results.compactMap { ($0.value as? BooleanValue)?.value }
    #expect(booleans == [true, false])
  }

  private func temporaryURL() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "SolidPostScript-filter-\(UUID().uuidString).bin")
  }

}
