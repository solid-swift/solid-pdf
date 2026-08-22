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
  func resolvesIndirectFilterConfigurationAndRejectsCyclesAndMismatchedArrays() async throws {
    let filterReference = PDFObjectReference(objectNumber: 20)
    let parametersReference = PDFObjectReference(objectNumber: 21)
    let stream = PDFStreamObject(
      dictionary: [
        "Filter": .reference(filterReference),
        "DecodeParms": .reference(parametersReference),
      ],
      encodedRange: try PDFSourceRange(offset: 100, length: 20),
      objectReference: PDFObjectReference(objectNumber: 19)
    )
    let configuration = try await PDFStreamConfiguration.resolve(
      stream: stream,
      options: .init(),
      resolve: { reference in
        switch reference {
        case filterReference: .name("LZWDecode")
        case parametersReference: .dictionary(["EarlyChange": .integer(0)])
        default: .null
        }
      }
    )
    #expect(configuration.filters.count == 1)
    #expect(configuration.filters[0].name == PDFName("LZWDecode"))
    #expect(configuration.filters[0].parameters?["EarlyChange"] == .integer(0))

    let mismatched = PDFStreamObject(
      dictionary: [
        "Filter": .array([.name("FlateDecode"), .name("ASCII85Decode")]),
        "DecodeParms": .array([.null]),
      ],
      encodedRange: try PDFSourceRange(offset: 0, length: 0)
    )
    await #expect(throws: PDFParsingError.self) {
      _ = try await PDFStreamConfiguration.resolve(
        stream: mismatched,
        options: .init(),
        resolve: { _ in .null }
      )
    }

    let cycle = PDFStreamObject(
      dictionary: ["Filter": .reference(filterReference)],
      encodedRange: try PDFSourceRange(offset: 0, length: 0)
    )
    await #expect(throws: PDFParsingError.self) {
      _ = try await PDFStreamConfiguration.resolve(
        stream: cycle,
        options: .init(),
        resolve: { _ in .reference(filterReference) }
      )
    }
  }

  @Test
  func decodesOneByteSourceWindowsAndNullParameterEntries() async throws {
    let expected = Data((0..<257).map(UInt8.init(truncatingIfNeeded:)))
    let data = try encoded(expected, with: [FlateEncoder(), ASCII85Encoder()])
    let dictionary: [PDFName: PDFObject] = [
      "Filter": .array([.name("ASCII85Decode"), .name("FlateDecode")]),
      "DecodeParms": .array([.null, .null]),
    ]
    let documentBytes = try makeDocument(
      data: data,
      compressed: false,
      dictionary: dictionary
    ).data
    let document = try await PDFDocument(
      source: PDFDataInputSource(documentBytes),
      options: .init(sourceWindowByteCount: 1, decodedStreamChunkByteCount: 1)
    )
    let stream = try await contentStream(in: document)
    #expect(try await document.decodedBytes(of: stream) == expected)
    await document.close()
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

  @Test(arguments: [-1, 0, 2])
  func decodesCCITTFaxParameterModes(_ k: Int) async throws {
    let columns = 32
    let rows = 12
    let expected = Data((0..<(rows * columns / 8)).map { index in
      index.isMultiple(of: 3) ? 0xAA : UInt8(truncatingIfNeeded: index * 31)
    })
    let options = try CCITTFaxOptions(
      k: k,
      endOfLine: k >= 0,
      encodedByteAlign: k == 0,
      columns: columns,
      rows: rows,
      endOfBlock: true,
      blackIs1: true,
      damagedRowsBeforeError: 0
    )
    let data = try encoded(expected, with: [CCITTFaxEncoder(options: options)])
    let dictionary: [PDFName: PDFObject] = [
      "Filter": .name("CCITTFaxDecode"),
      "DecodeParms": .dictionary([
        "K": .integer(k),
        "EndOfLine": .boolean(k >= 0),
        "EncodedByteAlign": .boolean(k == 0),
        "Columns": .integer(columns),
        "Rows": .integer(rows),
        "EndOfBlock": .boolean(true),
        "BlackIs1": .boolean(true),
        "DamagedRowsBeforeError": .integer(0),
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
  func decodesBaselineDCTWithColorTransform(_ colorTransform: Int) async throws {
    let width = 16
    let height = 16
    let colors = colorTransform == 0 ? 1 : 3
    let samples = Data((0..<(width * height * colors)).map {
      UInt8(truncatingIfNeeded: ($0 * 7) + ($0 / max(colors, 1)) * 3)
    })
    let data = try encoded(
      samples,
      with: [
        DCTEncoder(
          options: try DCTEncodeOptions(
            columns: width,
            rows: height,
            colors: colors,
            colorTransform: colorTransform
          )
        )
      ]
    )
    let dictionary: [PDFName: PDFObject] = [
      "Filter": .name("DCTDecode"),
      "DecodeParms": .dictionary(["ColorTransform": .integer(colorTransform)]),
    ]
    let documentBytes = try makeDocument(
      data: data,
      compressed: false,
      dictionary: dictionary
    ).data
    let document = try await PDFDocument(source: PDFDataInputSource(documentBytes))
    let decoded = try await document.decodedBytes(of: contentStream(in: document))
    #expect(decoded.count == samples.count)
    await document.close()
  }

  @Test
  func rejectsUnavailableImageFiltersPrecisely() async throws {
    let filters: [(PDFName, PDFUnsupportedFeature)] = [
      ("JPXDecode", .jpxDecode),
      ("JBIG2Decode", .jbig2Decode),
      ("Unknown", .streamFilter("Unknown")),
    ]
    for (name, feature) in filters {
      let encoded = try makeDocument(
        data: Data(),
        compressed: false,
        dictionary: ["Filter": .name(name)]
      )
      let document = try await PDFDocument(source: PDFDataInputSource(encoded.data))
      let stream = try await contentStream(in: document)
      do {
        _ = try await document.decodedBytes(of: stream)
        Issue.record("Expected \(name) to be rejected")
      } catch let PDFParsingError.unsupported(actual, diagnostic) {
        #expect(actual == feature)
        #expect(diagnostic.object == stream.objectReference)
      }
      await document.close()
    }
  }

  @Test
  func treatsAnUnnamedCryptFilterAsIdentity() async throws {
    let expected = Data("unencrypted explicit Crypt data".utf8)
    let encoded = try makeDocument(
      data: expected,
      compressed: false,
      dictionary: ["Filter": .name("Crypt")]
    )
    let document = try await PDFDocument(source: PDFDataInputSource(encoded.data))
    let stream = try await contentStream(in: document)
    #expect(try await document.decodedBytes(of: stream) == expected)
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
