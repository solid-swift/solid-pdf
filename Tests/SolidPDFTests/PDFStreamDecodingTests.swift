import Foundation
@testable import SolidPDF
import SolidIO
import SolidImageIO
import Testing

@Suite
struct PDFStreamDecodingTests {
  @Test(arguments: [false, true])
  func decodesRawAndFlateStreamsIncrementally(_ compressed: Bool) async throws {
    let expected = Data(repeating: 0x41, count: 256 * 1_024)
    let encoded = try makeDocument(data: expected, compressed: compressed)
    let options = PDFParsingOptions(decodedStreamChunkByteCount: 997)
    let document = try await PDFDocument(
      source: PDFDataInputSource(encoded.data),
      options: options
    )
    let stream = try await contentStream(in: document)
    let decoded = try await document.decodedStream(of: stream)
    var result = Data()
    var chunkCount = 0
    for try await chunk in decoded {
      #expect(!chunk.isEmpty)
      #expect(chunk.count <= 997)
      result.append(chunk)
      chunkCount += 1
    }
    #expect(chunkCount > 1)
    #expect(result == expected)
    #expect(try await document.decodedBytes(of: stream) == expected)
    await document.close()
  }

  @Test
  func rejectsDisabledAliasesAndUnsupportedFiltersWithObjectContext() async throws {
    let stream = PDFStreamObject(
      dictionary: ["Filter": .name("Fl")],
      encodedRange: try PDFSourceRange(offset: 0, length: 0),
      objectReference: PDFObjectReference(objectNumber: 9)
    )
    await #expect(throws: PDFParsingError.self) {
      _ = try await PDFStreamConfiguration.resolve(
        stream: stream,
        options: .init(),
        resolve: { _ in .null }
      )
    }
    let compatible = try await PDFStreamConfiguration.resolve(
      stream: stream,
      options: .init(acceptsStreamFilterAbbreviations: true),
      resolve: { _ in .null }
    )
    #expect(compatible.filters.first?.name == PDFName("FlateDecode"))
  }

  @Test
  func externalStreamsRequireAuthorityAndCloseExactlyOnce() async throws {
    let expected = Data("external stream".utf8)
    let encoded = try makeDocument(
      data: Data("ignored embedded data".utf8),
      compressed: false,
      dictionary: ["F": .string(PDFString("fixture.bin"))]
    )
    let denied = try await PDFDocument(source: PDFDataInputSource(encoded.data))
    let deniedStream = try await contentStream(in: denied)
    await #expect(throws: PDFParsingError.self) {
      _ = try await denied.decodedBytes(of: deniedStream)
    }
    await denied.close()

    let counter = CloseCounter()
    let provider = TestExternalProvider(data: expected, counter: counter)
    let document = try await PDFDocument(
      source: PDFDataInputSource(encoded.data),
      externalStreamProvider: provider
    )
    let stream = try await contentStream(in: document)
    let decoded = try await document.decodedStream(of: stream)
    #expect(try await decoded.next() == expected)
    await decoded.close()
    await decoded.close()
    #expect(await counter.value == 1)
    await document.close()
    #expect(await counter.value == 1)
  }

  @Test
  func enforcesDecodedByteAndScratchLimits() async throws {
    let encoded = try makeDocument(data: Data(repeating: 0, count: 4_096), compressed: true)
    var limits = PDFParsingLimits()
    limits.maximumDecodedStreamBytes = 1_024
    limits.maximumStreamScratchBytes = 1_024
    let document = try await PDFDocument(
      source: PDFDataInputSource(encoded.data),
      options: .init(limits: limits, decodedStreamChunkByteCount: 1_024)
    )
    let stream = try await contentStream(in: document)
    await #expect(throws: PDFParsingError.self) {
      _ = try await document.decodedBytes(of: stream)
    }
    await document.close()
  }

  @Test
  func decodesEveryPortableDataFilterAndMixedChains() async throws {
    let expected = Data((0..<8_192).map { UInt8(truncatingIfNeeded: $0 * 17) })
    let cases: [([PDFName], Data)] = try [
      (["ASCIIHexDecode"], encoded(expected, with: [ASCIIHexEncoder()])),
      (["ASCII85Decode"], encoded(expected, with: [ASCII85Encoder()])),
      (["LZWDecode"], encoded(expected, with: [LZWEncoder()])),
      (["FlateDecode"], encoded(expected, with: [FlateEncoder()])),
      (["RunLengthDecode"], encoded(expected, with: [RunLengthEncoder()])),
      (
        ["ASCII85Decode", "FlateDecode"],
        encoded(expected, with: [FlateEncoder(), ASCII85Encoder()])
      ),
    ]
    for (filters, data) in cases {
      let dictionary: [PDFName: PDFObject] = [
        "Filter": filters.count == 1
          ? .name(filters[0])
          : .array(filters.map { .name($0) })
      ]
      let documentBytes = try makeDocument(
        data: data,
        compressed: false,
        dictionary: dictionary
      ).data
      let document = try await PDFDocument(source: PDFDataInputSource(documentBytes))
      #expect(try await document.decodedBytes(of: contentStream(in: document)) == expected)
      await document.close()
    }
  }

  @Test(arguments: [1, 2, 4, 8, 16])
  func decodesFlatePredictorsAtEveryPDFBitDepth(_ bits: Int) async throws {
    let columns = 17
    let colors = 3
    let rowBytes = (columns * colors * bits + 7) / 8
    let expected = Data((0..<(rowBytes * 5)).map { UInt8(truncatingIfNeeded: $0 * 29) })
    let predictorOptions = try PredictorOptions(
      predictor: bits == 16 ? 12 : 15,
      colors: colors,
      bitsPerComponent: bits,
      columns: columns
    )
    let data = try encoded(
      expected,
      with: [PredictorEncoder(options: predictorOptions), FlateEncoder()]
    )
    let dictionary: [PDFName: PDFObject] = [
      "Filter": .name("FlateDecode"),
      "DecodeParms": .dictionary([
        "Predictor": .integer(bits == 16 ? 12 : 15),
        "Colors": .integer(colors),
        "BitsPerComponent": .integer(bits),
        "Columns": .integer(columns),
      ]),
    ]
    let documentBytes = try makeDocument(
      data: data,
      compressed: false,
      dictionary: dictionary
    ).data
    let document = try await PDFDocument(source: PDFDataInputSource(documentBytes))
    #expect(try await document.decodedBytes(of: contentStream(in: document)) == expected)
    await document.close()
  }

  @Test(arguments: [0, 1])
  func decodesBothLZWEarlyChangeValues(_ earlyChange: Int) async throws {
    let expected = Data(repeating: 0x6C, count: 16_384)
    let options = try LZWOptions(earlyChange: earlyChange)
    let data = try encoded(expected, with: [LZWEncoder(options: options)])
    let dictionary: [PDFName: PDFObject] = [
      "Filter": .name("LZWDecode"),
      "DecodeParms": .dictionary(["EarlyChange": .integer(earlyChange)]),
    ]
    let documentBytes = try makeDocument(
      data: data,
      compressed: false,
      dictionary: dictionary
    ).data
    let document = try await PDFDocument(source: PDFDataInputSource(documentBytes))
    #expect(try await document.decodedBytes(of: contentStream(in: document)) == expected)
    await document.close()
  }

  private func makeDocument(
    data: Data,
    compressed: Bool,
    dictionary: [PDFName: PDFObject] = [:]
  ) throws -> PDFEncodedDocument {
    var writer = try PDFDocumentWriter(
      sink: PDFDataOutputSink(),
      options: .init(version: .v1_7)
    )
    let catalog = try writer.reserveObject()
    let stream = try writer.reserveObject()
    try writer.write(.dictionary(["Type": .name("Catalog"), "Stream": .reference(stream)]), to: catalog)
    try writer.writeStream(
      dictionary: dictionary,
      chunks: [data],
      compressed: compressed,
      to: stream
    )
    return try writer.finish(root: catalog, pageCount: 0)
  }

  private func contentStream<Source: PDFInputSource>(
    in document: PDFDocument<Source>
  ) async throws -> PDFStreamObject {
    let root = try await document.resolve(document.root)
    guard case .value(.dictionary(let dictionary)) = root.value,
      case .reference(let reference) = dictionary["Stream"],
      case .stream(let stream) = try await document.resolve(reference).value
    else {
      throw PDFParsingError.malformed(.init(offset: 0, message: "The fixture stream is absent."))
    }
    return stream
  }

  private func encoded(_ data: Data, with filters: [any IncrementalFilter]) throws -> Data {
    var current = data
    for filter in filters {
      let result = try filter.process(input: current)
      #expect(result.consumedInput == current.count)
      var output = result.output
      output.append(try filter.finish() ?? Data())
      current = output
    }
    return current
  }
}

private actor CloseCounter {
  private(set) var value = 0
  func increment() { value += 1 }
}

private struct TestExternalProvider: PDFExternalStreamProvider {
  let data: Data
  let counter: CloseCounter

  func open(
    _ fileSpecification: PDFObject,
    for stream: PDFStreamObject
  ) async throws -> any PDFInputSourceSession {
    guard case .string(let value) = fileSpecification else {
      Issue.record("Expected a string file specification")
      return TestExternalSession(data: data, counter: counter)
    }
    #expect(value.bytes == Data("fixture.bin".utf8))
    return TestExternalSession(data: data, counter: counter)
  }
}

private actor TestExternalSession: PDFInputSourceSession {
  let data: Data
  let counter: CloseCounter
  var closed = false

  init(data: Data, counter: CloseCounter) {
    self.data = data
    self.counter = counter
  }

  func length() async throws -> Int64 { Int64(data.count) }

  func read(_ range: PDFSourceRange) async throws -> Data {
    let lower = Int(range.offset)
    return data.subdata(in: lower..<(lower + range.length))
  }

  func close() async {
    guard !closed else { return }
    closed = true
    await counter.increment()
  }
}
