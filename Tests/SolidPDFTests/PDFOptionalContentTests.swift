import Foundation
@testable import SolidPDF
import Testing

@Suite
struct PDFOptionalContentTests {
  @Test
  func resolvesConfigurationsAndEvaluatesGroupsAndMembership() async throws {
    let document = try await PDFDocument(source: PDFDataInputSource(fixture()))
    let properties = try #require(try await document.optionalContentProperties())
    #expect(properties.groups.map(\.name) == ["Layer A", "Layer B"])
    #expect(properties.defaultConfiguration.initiallyOff.count == 1)

    let groupA = PDFObject.reference(try reference(3))
    let groupB = PDFObject.reference(try reference(4))
    #expect(try await document.optionalContentVisibility(of: groupA).isVisible)
    #expect(try await !document.optionalContentVisibility(of: groupB).isVisible)

    let membership = PDFObject.dictionary([
      "Type": .name("OCMD"),
      "OCGs": .array([groupA, groupB]),
      "P": .name("AllOn"),
    ])
    #expect(try await !document.optionalContentVisibility(of: membership).isVisible)

    let expression = PDFObject.dictionary([
      "Type": .name("OCMD"),
      "VE": .array([.name("Or"), groupB, .array([.name("Not"), groupA])]),
    ])
    #expect(try await !document.optionalContentVisibility(of: expression).isVisible)
    await document.close()
  }

  @Test
  func customSelectionOverridesConfiguredState() async throws {
    let document = try await PDFDocument(source: PDFDataInputSource(fixture()))
    let identifier = PDFOptionalContentGroupIdentifier(reference: try reference(4))
    let visibility = try await document.optionalContentVisibility(
      of: .reference(try reference(4)),
      selection: .custom(base: .defaultConfiguration, overrides: [identifier: .on])
    )
    #expect(visibility.isVisible)
    #expect(visibility.controllingGroups == [identifier])
    await document.close()
  }

  private func fixture() -> Data {
    makePDF(objects: [
      "<< /Type /Catalog /Pages 2 0 R /OCProperties << /OCGs [3 0 R 4 0 R] /D << /Name (Default) /BaseState /ON /OFF [4 0 R] /Locked [3 0 R] >> /Configs [<< /Name (Print) /BaseState /OFF /ON [4 0 R] >>] >> >>",
      "<< /Type /Pages /Kids [] /Count 0 >>",
      "<< /Type /OCG /Name (Layer A) /Intent [/View /Design] >>",
      "<< /Type /OCG /Name (Layer B) >>",
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

  private func reference(_ objectNumber: Int) throws -> PDFObjectReference {
    try PDFObjectReference(objectNumber: objectNumber, generationNumber: 0)
  }
}
