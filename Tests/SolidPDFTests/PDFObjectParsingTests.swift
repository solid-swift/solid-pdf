import Foundation
@testable import SolidPDF
import Testing

@Suite
struct PDFObjectParsingTests {
  @Test
  func parsesHeaderAndEveryDirectObjectKindAcrossSmallWindows() async throws {
    let data = Data(
      "%PDF-2.0\n[null true false 42 -3.5 /A#20Name (a\\n(b)c) <4142F> << /Ref 7 2 R >>]"
        .utf8
    )
    let (reader, session) = try await makeReader(data, windowByteCount: 7)
    defer { Task { await reader.close() } }
    var parser = PDFObjectParser(reader: reader, limits: .init())
    #expect(try await parser.parseHeader() == .v2_0)
    let value = try await parser.parseObject()
    let reference = try PDFObjectReference(objectNumber: 7, generationNumber: 2)
    #expect(
      value == .array([
        .null,
        .boolean(true),
        .boolean(false),
        .number(.integer(42)),
        .number(.real(-3.5)),
        .name(PDFName("A Name")),
        .string(PDFString(bytes: Data("a\n(b)c".utf8), representation: .literal)),
        .string(PDFString(bytes: Data([0x41, 0x42, 0xF0]), representation: .hexadecimal)),
        .dictionary(["Ref": .reference(reference)]),
      ])
    )
    _ = session
  }

  @Test
  func literalStringsNormalizeLinesAndPreserveEscapes() async throws {
    let data = Data("(one\r\ntwo\\\r\nthree\\053)".utf8)
    let (reader, _) = try await makeReader(data, windowByteCount: 2)
    defer { Task { await reader.close() } }
    var parser = PDFObjectParser(reader: reader, limits: .init())
    #expect(
      try await parser.parseObject()
        == .string(PDFString(bytes: Data("one\ntwothree+".utf8), representation: .literal))
    )
  }

  @Test
  func parserSpanRollsBackFailedAtomicReads() throws {
    var span = PDFParserSpan(Data([0x01, 0x02, 0x03]))
    #expect(throws: PDFParsingError.self) {
      try span.atomically { candidate in
        _ = try candidate.readBigEndianInteger(byteCount: 2)
        _ = try candidate.readBigEndianInteger(byteCount: 2)
      }
    }
    #expect(span.position == 0)
    #expect(try span.readBigEndianInteger(byteCount: 3) == 0x01_02_03)
  }

  @Test
  func detectsTruncationInvalidEscapesAndConfiguredLimits() async throws {
    let malformed = ["(unterminated", "/Bad#0Z", "<GG>"]
    for source in malformed {
      let (reader, _) = try await makeReader(Data(source.utf8), windowByteCount: 3)
      var parser = PDFObjectParser(reader: reader, limits: .init())
      await #expect(throws: PDFParsingError.self) {
        _ = try await parser.parseObject()
      }
      await reader.close()
    }

    let limits = PDFParsingLimits(maximumTokenBytes: 3)
    let (reader, _) = try await makeReader(Data("/abcd".utf8), limits: limits)
    var parser = PDFObjectParser(reader: reader, limits: limits)
    await #expect(throws: PDFParsingError.self) {
      _ = try await parser.parseObject()
    }
    await reader.close()
  }

  @Test
  func fileAndDataSourcesReturnExactRanges() async throws {
    let data = Data("0123456789".utf8)
    let dataSession = try await PDFDataInputSource(data).makeSession()
    #expect(try await dataSession.read(PDFSourceRange(offset: 2, length: 4)) == Data("2345".utf8))

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("input.pdf")
    try data.write(to: url)
    let fileSession = try await PDFFileInputSource(url: url).makeSession()
    #expect(try await fileSession.read(PDFSourceRange(offset: 6, length: 3)) == Data("678".utf8))
    await fileSession.close()
  }

  private func makeReader(
    _ data: Data,
    windowByteCount: Int = 64 * 1_024,
    limits: PDFParsingLimits = .init()
  ) async throws -> (PDFSourceReader<PDFDataInputSourceSession>, PDFDataInputSourceSession) {
    let session = try await PDFDataInputSource(data).makeSession()
    let reader = try await PDFSourceReader(
      session: session,
      options: PDFParsingOptions(limits: limits, sourceWindowByteCount: windowByteCount)
    )
    return (reader, session)
  }
}
