import Foundation
import SolidPDF
@testable import SolidPDFGraphics
import Testing

@Suite
struct PDFContentParserTests {
  @Test
  func parsesDirectObjectsAndTokensAcrossContentStreams() async throws {
    let document = try await PDFDocument(
      source: PDFDataInputSource(fixture(contents: ["1", "0 20 m /A#20 [true null (x\\n)] BMC"]))
    )
    let page = try await document.page(at: 0)
    let parser = PDFContentParser(
      input: PDFContentInput(
        streams: page.contentStreams,
        open: { try await document.decodedStream(of: $0) }
      ),
      revision: document.latestRevision.identifier,
      page: page,
      maximumScratchBytes: 1_024 * 1_024
    )

    let tokens = try await collect(parser)
    #expect(tokens.count == 6)
    #expect(tokens[0].object == .integer(10))
    #expect(tokens[1].object == .integer(20))
    #expect(tokens[2].keyword == "m")
    #expect(tokens[3].object == .name(PDFName("A ")))
    #expect(tokens[4].object == .array([.boolean(true), .null, .string(PDFString(bytes: Data([0x78, 0x0A]), representation: .literal))]))
    #expect(tokens[5].keyword == "BMC")
    #expect(tokens[0].location.segments.count == 2)
    await parser.close()
    await document.close()
  }

  @Test
  func rejectsOperatorsNestedInsideDirectObjects() async throws {
    let document = try await PDFDocument(
      source: PDFDataInputSource(fixture(contents: ["[1 madeup] q"]))
    )
    let page = try await document.page(at: 0)
    let parser = PDFContentParser(
      input: PDFContentInput(
        streams: page.contentStreams,
        open: { try await document.decodedStream(of: $0) }
      ),
      revision: document.latestRevision.identifier,
      page: page,
      maximumScratchBytes: 1_024
    )

    await #expect(throws: PDFGraphicsError.self) { _ = try await parser.next() }
    await parser.close()
    await document.close()
  }

  private func collect(_ parser: PDFContentParser) async throws -> [ObservedToken] {
    var result: [ObservedToken] = []
    while let token = try await parser.next() {
      switch token.value {
      case .object(let object): result.append(ObservedToken(object: object, location: token.location))
      case .keyword(let keyword): result.append(ObservedToken(keyword: keyword, location: token.location))
      }
    }
    return result
  }

  private func fixture(contents: [String]) -> Data {
    var objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Resources << >> /Contents [CONTENTS] >>",
    ]
    var references: [String] = []
    for content in contents {
      let objectNumber = objects.count + 1
      references.append("\(objectNumber) 0 R")
      objects.append("<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream")
    }
    objects[2] = objects[2].replacingOccurrences(of: "CONTENTS", with: references.joined(separator: " "))
    var data = Data("%PDF-1.7\n".utf8)
    var offsets = [0]
    for (index, object) in objects.enumerated() {
      offsets.append(data.count)
      data.append(Data("\(index + 1) 0 obj\n\(object)\nendobj\n".utf8))
    }
    let xref = data.count
    data.append(Data("xref\n0 \(objects.count + 1)\n0000000000 65535 f \n".utf8))
    for offset in offsets.dropFirst() {
      data.append(Data(String(format: "%010d 00000 n \n", offset).utf8))
    }
    data.append(Data("trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
    return data
  }
}

private struct ObservedToken {
  let object: PDFObject?
  let keyword: String?
  let location: PDFContentLocation

  init(object: PDFObject, location: PDFContentLocation) {
    self.object = object
    keyword = nil
    self.location = location
  }

  init(keyword: String, location: PDFContentLocation) {
    object = nil
    self.keyword = keyword
    self.location = location
  }
}
