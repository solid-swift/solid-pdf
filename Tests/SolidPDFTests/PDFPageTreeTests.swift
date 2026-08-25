import Foundation
@testable import SolidPDF
import Testing

@Suite
struct PDFPageTreeTests {
  @Test
  func resolvesInheritedGeometryResourcesAndProvenance() async throws {
    let document = try await PDFDocument(source: PDFDataInputSource(fixture()))
    #expect(try await document.pageCount() == 2)
    let page = try await document.page(at: 0)
    #expect(page.index == 0)
    #expect(page.ancestorReferences.map(\.objectNumber) == [2, 3])
    #expect(page.resources.origin == .ancestor(try reference(3)))
    #expect(page.geometry.mediaBox.declared.origin == .ancestor(try reference(2)))
    #expect(page.geometry.cropBox.effective.maximumX == 200)
    #expect(page.geometry.bleedBox.declared.origin == .defaulted)
    #expect(page.geometry.rotation.value == .degrees270)
    #expect(page.geometry.userUnit.value == 2)
    await document.close()
  }

  @Test
  func enumeratesPagesAndRejectsOutOfRangeIndexes() async throws {
    let document = try await PDFDocument(source: PDFDataInputSource(fixture()))
    let pages = try await document.pages()
    var indexes = [Int]()
    for try await page in pages { indexes.append(page.index) }
    #expect(indexes == [0, 1])
    await #expect(throws: PDFParsingError.pageIndexOutOfRange(2)) {
      _ = try await document.page(at: 2)
    }
    await document.close()
  }

  @Test
  func fullValidationDetectsBadCountsAndParents() async {
    await #expect(throws: PDFParsingError.self) {
      let document = try await PDFDocument(
        source: PDFDataInputSource(fixture(rootCount: 3))
      )
      _ = try await document.pageCount()
    }
    await #expect(throws: PDFParsingError.self) {
      let document = try await PDFDocument(
        source: PDFDataInputSource(fixture(secondPageParent: 2))
      )
      _ = try await document.pageCount()
    }
  }

  private func fixture(rootCount: Int = 2, secondPageParent: Int = 3) -> Data {
    let objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count \(rootCount) /MediaBox [300 400 0 0] /Rotate -90 >>",
      "<< /Type /Pages /Parent 2 0 R /Kids [4 0 R 5 0 R] /Count 2 /Resources << /Font << >> >> >>",
      "<< /Type /Page /Parent 3 0 R /CropBox [-10 -20 200 250] /UserUnit 2 >>",
      "<< /Type /Page /Parent \(secondPageParent) 0 R >>",
    ]
    return makePDF(objects: objects)
  }

  private func makePDF(objects: [String]) -> Data {
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
    data.append(
      Data("trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8)
    )
    return data
  }

  private func reference(_ objectNumber: Int) throws -> PDFObjectReference {
    try PDFObjectReference(objectNumber: objectNumber, generationNumber: 0)
  }
}
