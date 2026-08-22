import Foundation
@testable import SolidPDF
import Testing

@Suite
struct PDFAnnotationTests {
  @Test
  func resolvesAnnotationsAppearancesDestinationsAndInertActions() async throws {
    let document = try await PDFDocument(source: PDFDataInputSource(fixture()))
    let page = try await document.page(at: 0)
    let annotations = try await document.annotations(on: page)
    #expect(annotations.count == 2)
    let link = annotations[0]
    #expect(link.subtype == .link)
    #expect(link.rectangle == (try PDFRectangle(x1: 10, y1: 20, x2: 40, y2: 50)))
    #expect(link.flags.contains(.print))
    guard case .stream(let appearance)? = link.appearances.normal else {
      Issue.record("Expected a normal appearance stream")
      return
    }
    #expect(appearance.objectReference?.objectNumber == 6)
    guard case .link(let details) = link.details,
      case .uri(let uri, let isMap)? = details.action?.kind
    else {
      Issue.record("Expected an inert URI action")
      return
    }
    #expect(uri.bytes == Data("https://example.test".utf8))
    #expect(!isMap)
    #expect(details.action?.next.count == 1)
    guard case .javaScript? = details.action?.next.first?.kind else {
      Issue.record("Expected an inert JavaScript action")
      return
    }
    #expect(annotations[1].contents == "Review note")
    #expect(try await document.annotation(link.identifier) == link)

    let direct = try await document.destination(named: .name("Direct"))
    guard case .explicit(_, .fit)? = direct else {
      Issue.record("Expected the legacy named destination")
      return
    }
    let named = try await document.destination(named: .string("Named"))
    guard case .explicit(_, .xyz(nil, nil, 2))? = named else {
      Issue.record("Expected the name-tree destination")
      return
    }
    try await document.validateAnnotations()
    await document.close()
  }

  @Test
  func rejectsDirectAndDuplicatePageAnnotations() async {
    await #expect(throws: PDFParsingError.self) {
      let document = try await PDFDocument(source: PDFDataInputSource(fixture(annots: "[4 0 R 4 0 R]")))
      try await document.validateAnnotations()
    }
    await #expect(throws: PDFParsingError.self) {
      let document = try await PDFDocument(source: PDFDataInputSource(fixture(annots: "[<< /Subtype /Text /Rect [0 0 1 1] >>]")))
      try await document.validateAnnotations()
    }
  }

  private func fixture(annots: String = "[4 0 R 5 0 R]") -> Data {
    makePDF(objects: [
      "<< /Type /Catalog /Pages 2 0 R /Dests << /Direct [3 0 R /Fit] >> /Names << /Dests 7 0 R >> >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Resources <<>> /Annots \(annots) >>",
      "<< /Type /Annot /Subtype /Link /P 3 0 R /Rect [10 20 40 50] /F 4 /A << /S /URI /URI (https://example.test) /Next << /S /JavaScript /JS (app.alert\\(1\\)) >> >> /AP << /N 6 0 R >> >>",
      "<< /Type /Annot /Subtype /Text /P 3 0 R /Rect [1 2 3 4] /Contents (Review note) >>",
      "<< /Type /XObject /Subtype /Form /BBox [0 0 30 30] /Length 0 >>\nstream\n\nendstream",
      "<< /Names [(Named) [3 0 R /XYZ null null 2]] >>",
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
    for offset in offsets { data.append(Data(String(format: "%010d 00000 n \n", offset).utf8)) }
    data.append(Data("trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
    return data
  }
}
