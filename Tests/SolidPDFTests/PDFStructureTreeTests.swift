import Foundation
@testable import SolidPDF
import Testing

@Suite
struct PDFStructureTreeTests {
  @Test
  func resolvesLogicalOrderParentTreeIDTreeAndReplacementText() async throws {
    let document = try await PDFDocument(source: PDFDataInputSource(fixture()))
    let tree = try #require(try await document.structureTree())
    #expect(tree.reference.objectNumber == 5)
    #expect(tree.roleMap["Custom"] == PDFName("P"))
    guard case .element(let documentID)? = tree.children.first else {
      Issue.record("Expected a root structure element")
      return
    }
    let documentElement = try await document.structureElement(documentID)
    #expect(documentElement.structureType == PDFName("Document"))
    guard case .element(let paragraphID)? = documentElement.children.first else {
      Issue.record("Expected a paragraph structure element")
      return
    }
    let paragraph = try await document.structureElement(paragraphID)
    #expect(paragraph.structureType == PDFName("Custom"))
    #expect(paragraph.replacementText == "Logical")
    #expect(paragraph.identifierBytes == Data("p1".utf8))
    guard case .markedContent(let reference)? = paragraph.children.first else {
      Issue.record("Expected an MCR child")
      return
    }
    #expect(reference.markedContentIdentifier == 0)
    #expect(reference.page?.objectNumber == 3)
    try await document.validateStructureTree()
    await document.close()
  }

  @Test
  func rejectsIncorrectParentsAndRoleMapCycles() async {
    await #expect(throws: PDFParsingError.self) {
      let document = try await PDFDocument(source: PDFDataInputSource(fixture(parent: 1)))
      try await document.validateStructureTree()
    }
    await #expect(throws: PDFParsingError.self) {
      let document = try await PDFDocument(source: PDFDataInputSource(fixture(roleMap: "/A /B /B /A")))
      _ = try await document.structureTree()
    }
  }

  private func fixture(parent: Int = 6, roleMap: String = "/Custom /P") -> Data {
    makePDF(objects: [
      "<< /Type /Catalog /Pages 2 0 R /StructTreeRoot 5 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /StructParents 0 /Contents 4 0 R >>",
      "<< /Length 23 >>\nstream\n/P <</MCID 0>> BDC EMC\nendstream",
      "<< /Type /StructTreeRoot /K [6 0 R] /RoleMap << \(roleMap) >> /ParentTree 8 0 R /IDTree 9 0 R /ParentTreeNextKey 1 >>",
      "<< /Type /StructElem /S /Document /P 5 0 R /K [7 0 R] >>",
      "<< /Type /StructElem /S /Custom /P \(parent) 0 R /Pg 3 0 R /ID (p1) /ActualText (Logical) /K [<< /Type /MCR /MCID 0 /Pg 3 0 R >>] >>",
      "<< /Nums [0 [7 0 R]] >>",
      "<< /Names [(p1) 7 0 R] >>",
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
