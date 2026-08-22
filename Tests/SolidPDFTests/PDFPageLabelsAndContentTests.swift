import Foundation
@testable import SolidPDF
import Testing

@Suite
struct PDFPageLabelsAndContentTests {
  @Test
  func resolvesLabelRangesAndEffectiveLabels() async throws {
    let document = try await PDFDocument(source: PDFDataInputSource(fixture()))
    let ranges = try #require(try await document.pageLabelRanges())
    #expect(ranges.count == 2)
    #expect((try await document.page(at: 0)).label?.text == "Front-i")
    #expect((try await document.page(at: 1)).label?.text == "Front-ii")
    #expect((try await document.page(at: 2)).label?.text == "Body-3")
    await document.close()
  }

  @Test
  func concatenatesDecodedContentWithoutSeparators() async throws {
    let document = try await PDFDocument(source: PDFDataInputSource(fixture()))
    let page = try await document.page(at: 0)
    #expect(page.contentStreams.count == 2)
    let content = document.decodedContent(of: page)
    var bytes = Data()
    for try await chunk in content { bytes.append(chunk) }
    #expect(bytes == Data("qQ".utf8))
    await document.close()
  }

  @Test
  func absentLabelsReturnNil() async throws {
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(labels: false)))
    #expect(try await document.pageLabelRanges() == nil)
    #expect((try await document.page(at: 0)).label == nil)
    await document.close()
  }

  private func fixture(labels: Bool = true) -> Data {
    let labelEntry = labels ? " /PageLabels 8 0 R" : ""
    let objects = [
      "<< /Type /Catalog /Pages 2 0 R\(labelEntry) >>",
      "<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 /MediaBox [0 0 100 100] /Resources << >> >>",
      "<< /Type /Page /Parent 2 0 R /Contents [6 0 R 7 0 R] >>",
      "<< /Type /Page /Parent 2 0 R >>",
      "<< /Type /Page /Parent 2 0 R >>",
      "<< /Length 1 >>\nstream\nq\nendstream",
      "<< /Length 1 >>\nstream\nQ\nendstream",
      "<< /Nums [0 << /S /r /P (Front-) >> 2 << /S /D /P (Body-) /St 3 >>] >>",
    ]
    return makePDF(objects: objects)
  }

  private func makePDF(objects: [String]) -> Data {
    var data = Data("%PDF-2.0\n".utf8)
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
}
