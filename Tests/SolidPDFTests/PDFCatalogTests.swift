import Foundation
@testable import SolidPDF
import Testing

@Suite
struct PDFCatalogTests {
  @Test
  func validatesCatalogAndPageRootDuringOpen() async throws {
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(version: "2.0")))
    #expect(document.version == .v1_4)
    #expect(document.effectiveVersion == .v2_0)
    #expect(document.catalog.declaredPageCount == 0)
    #expect(document.catalog.pageTreeRoot.objectNumber == 2)
    await document.close()
  }

  @Test
  func rejectsMalformedCatalogAndPageRootDuringOpen() async {
    await #expect(throws: PDFParsingError.self) {
      _ = try await PDFDocument(
        source: PDFDataInputSource(fixture(catalog: "<< /Type /Catalog >>"))
      )
    }
    await #expect(throws: PDFParsingError.self) {
      _ = try await PDFDocument(
        source: PDFDataInputSource(fixture(pages: "<< /Type /Pages /Kids [] /Count -1 >>"))
      )
    }
  }

  @Test
  func rejectsMalformedCatalogVersion() async {
    await #expect(throws: PDFParsingError.self) {
      _ = try await PDFDocument(source: PDFDataInputSource(fixture(version: "9.9")))
    }
  }

  private func fixture(
    version: String? = nil,
    catalog: String? = nil,
    pages: String = "<< /Type /Pages /Kids [] /Count 0 >>"
  ) -> Data {
    var data = Data("%PDF-1.4\n".utf8)
    let catalogOffset = data.count
    let catalogBody = catalog
      ?? "<< /Type /Catalog /Pages 2 0 R\(version.map { " /Version /\($0)" } ?? "") >>"
    data.append(Data("1 0 obj\n\(catalogBody)\nendobj\n".utf8))
    let pagesOffset = data.count
    data.append(Data("2 0 obj\n\(pages)\nendobj\n".utf8))
    let xref = data.count
    data.append(Data("xref\n0 3\n0000000000 65535 f \n".utf8))
    data.append(Data(String(format: "%010d 00000 n \n", catalogOffset).utf8))
    data.append(Data(String(format: "%010d 00000 n \n", pagesOffset).utf8))
    data.append(Data("trailer\n<< /Size 3 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
    return data
  }
}
