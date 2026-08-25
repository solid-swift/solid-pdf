import Foundation
import SolidPDF
@testable import SolidPDFGraphics
import Testing

@Suite
struct PDFContentExecutorTests {
  @Test
  func ignoresUnknownOperatorsOnlyInsideCompatibilitySections() async throws {
    let (document, page, contentParser) = try await parser(for: "BX 1 2 vendorOp EX q Q")
    let handler = RecordingInstructionHandler()
    try await PDFContentExecutor(parser: contentParser, handler: handler, maximumOperators: 10).execute()
    #expect(handler.names == ["q", "Q"])
    await document.close()

    let (strictDocument, _, strictParser) = try await parser(for: "1 vendorOp")
    await #expect(throws: PDFGraphicsError.self) {
      try await PDFContentExecutor(
        parser: strictParser,
        handler: RecordingInstructionHandler(),
        maximumOperators: 10
      ).execute()
    }
    await strictDocument.close()
    _ = page
  }

  @Test
  func validatesTextAndMarkedContentState() async throws {
    let (document, _, contentParser) = try await parser(for: "BT /F1 12 Tf ET /Span BMC EMC")
    let handler = RecordingInstructionHandler()
    try await PDFContentExecutor(parser: contentParser, handler: handler, maximumOperators: 10).execute()
    #expect(handler.names == ["BT", "Tf", "ET", "BMC", "EMC"])
    await document.close()

    let (invalidDocument, _, invalidParser) = try await parser(for: "(text) Tj")
    await #expect(throws: PDFGraphicsError.self) {
      try await PDFContentExecutor(
        parser: invalidParser,
        handler: RecordingInstructionHandler(),
        maximumOperators: 10
      ).execute()
    }
    await invalidDocument.close()
  }

  @Test
  func rejectsIndirectReferencesAndOperatorLimitGrowth() async throws {
    let (referenceDocument, _, referenceParser) = try await parser(for: "1 0 R")
    await #expect(throws: PDFGraphicsError.self) {
      try await PDFContentExecutor(
        parser: referenceParser,
        handler: RecordingInstructionHandler(),
        maximumOperators: 10
      ).execute()
    }
    await referenceDocument.close()

    let (limitDocument, _, limitParser) = try await parser(for: "q Q")
    await #expect(throws: PDFGraphicsError.self) {
      try await PDFContentExecutor(
        parser: limitParser,
        handler: RecordingInstructionHandler(),
        maximumOperators: 1
      ).execute()
    }
    await limitDocument.close()
  }

  private func parser(
    for content: String
  ) async throws -> (PDFDocument<PDFDataInputSource>, PDFPage, PDFContentParser) {
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(content)))
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
    return (document, page, parser)
  }

  private func fixture(_ content: String) -> Data {
    let objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Resources << >> /Contents 4 0 R >>",
      "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream",
    ]
    var data = Data("%PDF-1.7\n".utf8)
    var offsets = [0]
    for (index, object) in objects.enumerated() {
      offsets.append(data.count)
      data.append(Data("\(index + 1) 0 obj\n\(object)\nendobj\n".utf8))
    }
    let xref = data.count
    data.append(Data("xref\n0 5\n0000000000 65535 f \n".utf8))
    for offset in offsets.dropFirst() {
      data.append(Data(String(format: "%010d 00000 n \n", offset).utf8))
    }
    data.append(Data("trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
    return data
  }
}

private final class RecordingInstructionHandler: PDFContentInstructionHandler {
  var names: [String] = []

  func execute(_ instruction: PDFContentInstruction) async throws {
    names.append(instruction.name)
  }

  func finish(at location: PDFContentLocation?) async throws {}
}
