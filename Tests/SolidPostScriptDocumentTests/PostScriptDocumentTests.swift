import Foundation
import SolidPostScriptDocument
import Testing

@Suite
struct PostScriptDocumentTests {
  @Test
  func parsesStrictEPSMetadataAndAtEndBounds() throws {
    let source = Data("""
      %!PS-Adobe-3.0 EPSF-3.0\r
      %%BoundingBox: (atend)\r
      %%Title: Example\r
      %%EndComments\r
      0 0 moveto\r
      %%Trailer\r
      %%BoundingBox: -1.5 2.25 20.5 40.75\r
      %%EOF\r
      """.utf8)
    let document = try PostScriptDocument(data: source)
    #expect(document.metadata.kind == .encapsulatedPostScript)
    #expect(document.metadata.title == "Example")
    #expect(document.metadata.bounds?.lowerX == -1.5)
    #expect(document.metadata.bounds?.upperY == 40.75)
    #expect(document.programData == source)
  }

  @Test
  func nestedDocumentAndBinaryPayloadDoNotLeakMetadata() throws {
    let payload = "%%BoundingBox: 9 9 9 9"
    let source = Data("""
      %!PS-Adobe-3.0
      %%BoundingBox: 0 0 100 200
      %%BeginDocument: nested.eps
      %%BoundingBox: 1 1 2 2
      %%EndDocument
      %%BeginBinary: \(payload.utf8.count)
      \(payload)%%Pages: 2
      %%Page: first 1
      showpage
      %%Page: second 2
      showpage
      """.utf8)
    let document = try PostScriptDocument(data: source)
    #expect(document.metadata.bounds?.upperX == 100)
    #expect(document.metadata.pages.map(\.ordinal) == [1, 2])
  }

  @Test
  func strictEPSRequiresIdentificationAndBounds() {
    #expect(throws: PostScriptDocumentError.missingEPSHeader) {
      try PostScriptDocument(
        data: Data("%!PS\n".utf8),
        options: .init(assumedKind: .encapsulatedPostScript)
      )
    }
    #expect(throws: PostScriptDocumentError.missingEPSBoundingBox) {
      try PostScriptDocument(data: Data("%!PS-Adobe-3.0 EPSF-3.0\n".utf8))
    }
  }

  @Test
  func extractsDOSWrappedProgram() throws {
    let program = Data("%!PS-Adobe-3.0 EPSF-3.0\n%%BoundingBox: 0 0 1 1\n".utf8)
    var source = Data([0xC5, 0xD0, 0xD3, 0xC6])
    source.append(contentsOf: [12, 0, 0, 0])
    source.append(contentsOf: [UInt8(program.count), 0, 0, 0])
    source.append(program)
    let document = try PostScriptDocument(data: source)
    #expect(document.programData == program)
  }
}
