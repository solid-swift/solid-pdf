import Foundation
@testable import SolidPDF
import Testing

@Suite
struct PDFAcroFormTests {
  @Test
  func resolvesInheritedFieldsWidgetsAndStructuralSignatures() async throws {
    let document = try await PDFDocument(source: PDFDataInputSource(fixture()))
    let form = try #require(try await document.acroForm())
    #expect(form.fields.count == 2)
    #expect(form.defaultAppearance?.bytes == Data("/Helv 10 Tf 0 g".utf8))
    #expect(form.calculationOrder.map(\.reference.objectNumber) == [7])
    #expect(form.needsAppearances)

    let fields = try await document.formFields()
    #expect(fields.count == 3)
    let name = try #require(fields.first { $0.fullyQualifiedName == "Person.Name" })
    #expect(name.type == .text)
    #expect(name.widgets.count == 1)
    #expect(name.widgets[0].pageReference.objectNumber == 3)
    guard case .string(let value)? = name.value else {
      Issue.record("Expected the inherited text field value")
      return
    }
    #expect(value.bytes == Data("Alice".utf8))

    let signatureField = try #require(fields.first { $0.type == .signature })
    let signature = try #require(signatureField.signature)
    #expect(signature.byteRanges == [
      try PDFSourceRange(offset: 0, length: 20),
      try PDFSourceRange(offset: 40, length: 10),
    ])
    #expect(signature.contents == Data([0x01, 0x02]))
    #expect(signature.reason == "Approved")
    try await document.validateAcroForm()
    await document.close()
  }

  @Test
  func rejectsWidgetMembershipAndFieldCycles() async {
    await #expect(throws: PDFParsingError.self) {
      let document = try await PDFDocument(source: PDFDataInputSource(fixture(annots: "[5 0 R]")))
      try await document.validateAcroForm()
    }
    await #expect(throws: PDFParsingError.self) {
      let document = try await PDFDocument(source: PDFDataInputSource(fixture(fieldKids: "[6 0 R]")))
      try await document.validateAcroForm()
    }
  }

  private func fixture(
    annots: String = "[4 0 R 5 0 R]",
    fieldKids: String = "[7 0 R]"
  ) -> Data {
    makePDF(objects: [
      "<< /Type /Catalog /Pages 2 0 R /AcroForm 8 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Resources <<>> /Annots \(annots) >>",
      "<< /Type /Annot /Subtype /Widget /Parent 7 0 R /P 3 0 R /Rect [10 10 80 30] >>",
      "<< /Type /Annot /Subtype /Widget /Parent 9 0 R /P 3 0 R /Rect [10 40 80 60] >>",
      "<< /T (Person) /FT /Tx /Kids \(fieldKids) >>",
      "<< /Parent 6 0 R /T (Name) /V (Alice) /Kids [4 0 R] >>",
      "<< /Fields [6 0 R 9 0 R] /DR <<>> /DA (/Helv 10 Tf 0 g) /Q 1 /CO [7 0 R] /NeedAppearances true /SigFlags 3 >>",
      "<< /T (Approval) /FT /Sig /V 10 0 R /Kids [5 0 R] >>",
      "<< /Type /Sig /Filter /Adobe.PPKLite /SubFilter /adbe.pkcs7.detached /ByteRange [0 20 40 10] /Contents <0102> /Reason (Approved) /M (D:20260822090000-07'00') >>",
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
