import Foundation
@testable import SolidPDF
import Testing

@Suite
struct PDFFormIncrementalUpdateTests {
  @Test
  func updatesTextValueInOneIncrementalRevision() async throws {
    let original = fixture()
    let document = try await PDFDocument(source: PDFDataInputSource(original))
    let field = try #require(try await document.formFields().first)
    let result = try await document.incrementallyUpdatedData(.init(updates: [
      .init(field: field.identifier, value: .text("Renée"))
    ]))

    #expect(result.output.data.prefix(original.count) == original)
    #expect(result.appendedRevision.ordinal == 1)
    #expect(result.changedReferences == [field.identifier.reference])

    let updated = try await PDFDocument(source: PDFDataInputSource(result.output.data))
    let current = try await updated.formField(field.identifier)
    guard case .string(let currentValue)? = current.value else {
      Issue.record("Expected an updated text value")
      return
    }
    #expect(try PDFTextStringDecoder.decode(currentValue, allowsUTF8: true) == "Renée")
    let historical = try await updated.formField(field.identifier, in: updated.revisions[0].identifier)
    guard case .string(let historicalValue)? = historical.value else {
      Issue.record("Expected the historical text value")
      return
    }
    #expect(historicalValue.bytes == Data("Alice".utf8))
    await updated.close()
    await document.close()
  }

  @Test
  func rejectsDuplicateReadOnlyAndOversizedUpdates() async throws {
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(flags: 1, maximumLength: 3)))
    let field = try #require(try await document.formFields().first)
    await #expect(throws: PDFIncrementalUpdateError.permissionDenied) {
      try await document.incrementallyUpdatedData(.init(updates: [
        .init(field: field.identifier, value: .text("Bob"))
      ]))
    }
    await #expect(throws: PDFIncrementalUpdateError.self) {
      try await document.incrementallyUpdatedData(.init(updates: [
        .init(field: field.identifier, value: .text("Bob")),
        .init(field: field.identifier, value: .text("Eve")),
      ]))
    }
    await document.close()

    let writable = try await PDFDocument(source: PDFDataInputSource(fixture(maximumLength: 3)))
    let writableField = try #require(try await writable.formFields().first)
    await #expect(throws: PDFIncrementalUpdateError.self) {
      try await writable.incrementallyUpdatedData(.init(updates: [
        .init(field: writableField.identifier, value: .text("Four"))
      ]))
    }
    await writable.close()
  }

  private func fixture(flags: Int = 0, maximumLength: Int = 64) -> Data {
    makePDF(objects: [
      "<< /Type /Catalog /Pages 2 0 R /AcroForm 5 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Resources <<>> /Annots [4 0 R] >>",
      "<< /Type /Annot /Subtype /Widget /Parent 6 0 R /P 3 0 R /Rect [10 10 90 30] >>",
      "<< /Fields [6 0 R] /DR <<>> /DA (/Helv 10 Tf 0 g) /NeedAppearances true >>",
      "<< /T (Name) /FT /Tx /Ff \(flags) /MaxLen \(maximumLength) /V (Alice) /Kids [4 0 R] >>",
    ])
  }

  private func makePDF(objects: [String]) -> Data {
    var data = Data("%PDF-1.7\n".utf8)
    var offsets = [Int]()
    for (index, object) in objects.enumerated() {
      offsets.append(data.count)
      data.append(Data("\(index + 1) 0 obj\n\(object)\nendobj\n".utf8))
    }
    let xref = data.count
    data.append(Data("xref\n0 \(objects.count + 1)\n0000000000 65535 f \n".utf8))
    for offset in offsets {
      data.append(Data(String(format: "%010d 00000 n \n", offset).utf8))
    }
    data.append(Data("trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
    return data
  }
}
