import Foundation
@testable import SolidPDF
import Testing

@Suite
struct PDFDocumentAssetsTests {
  @Test
  func parsesPDFDatePrecisionAndTimeZone() throws {
    let complete = try PDFDate("D:20240822153045-07'30'")
    #expect(complete.precision == .second)
    #expect(complete.timeZone == .offset(minutes: -450))
    #expect(complete.instant != nil)

    let partial = try PDFDate("202408")
    #expect(partial.precision == .month)
    #expect(partial.timeZone == .unspecified)
    #expect(partial.instant == nil)

    #expect(throws: PDFParsingError.self) { try PDFDate("D:202413") }
  }

  @Test
  func reconcilesInfoAndXMPWithoutDiscardingSources() async throws {
    let xmp = """
      <?xpacket begin="﻿"?>
      <x:xmpmeta xmlns:x="adobe:ns:meta/">
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:xmp="http://ns.adobe.com/xap/1.0/">
            <dc:title><rdf:Alt><rdf:li xml:lang="x-default">XMP title</rdf:li></rdf:Alt></dc:title>
            <xmp:CreatorTool>XMP creator</xmp:CreatorTool>
            <xmp:ModifyDate>2024-08-22T15:30:45Z</xmp:ModifyDate>
          </rdf:Description>
        </rdf:RDF>
      </x:xmpmeta>
      <?xpacket end="w"?>
      """
    let document = try await PDFDocument(
      source: PDFDataInputSource(fixture(xmp: Data(xmp.utf8)))
    )
    let metadata = try await document.metadata()
    #expect(metadata.fields.title?.value == "XMP title")
    #expect(metadata.fields.title?.source == .xmp)
    #expect(metadata.fields.author?.value == "Info author")
    #expect(metadata.fields.author?.source == .informationDictionary)
    #expect(metadata.fields.creator?.value == "XMP creator")
    #expect(metadata.customInformation["Custom"]?.bytes == Data("opaque".utf8))
    #expect(metadata.xmp?.bytes == Data(xmp.utf8))
    #expect(metadata.informationRevision == document.latestRevision.identifier)
    await document.close()
  }

  @Test
  func rejectsXMPEntitiesAndKeepsFileSpecificationsInert() async throws {
    let xmp = Data("<!DOCTYPE x [<!ENTITY e SYSTEM 'file:///etc/passwd'>]><x>&e;</x>".utf8)
    let document = try await PDFDocument(source: PDFDataInputSource(fixture(xmp: xmp)))
    await #expect(throws: PDFParsingError.self) {
      _ = try await document.metadata()
    }

    let specification = try await document.fileSpecification(.dictionary([
      "Type": .name("Filespec"),
      "FS": .name("URL"),
      "F": .string("../../outside"),
      "UF": .string("display name.txt"),
      "Desc": .string("An inert attachment"),
      "V": .boolean(true),
      "EF": .dictionary(["F": .reference(try .init(objectNumber: 4, generationNumber: 0))]),
    ]))
    #expect(specification.filename?.bytes == Data("../../outside".utf8))
    #expect(specification.unicodeFilename == "display name.txt")
    #expect(specification.fileSystem == "URL")
    #expect(specification.isVolatile)
    #expect(specification.embeddedFileEntries["F"] != nil)
    await document.close()
  }

  private func fixture(xmp: Data) -> Data {
    let metadataHeader = Data(
      "<< /Type /Metadata /Subtype /XML /Length \(xmp.count) >>\nstream\n".utf8
    )
    var metadata = metadataHeader
    metadata.append(xmp)
    metadata.append(Data("\nendstream".utf8))
    return makePDF(objects: [
      Data("<< /Type /Catalog /Pages 2 0 R /Metadata 4 0 R >>".utf8),
      Data("<< /Type /Pages /Kids [] /Count 0 >>".utf8),
      Data("<< /Title (Info title) /Author (Info author) /Creator (Info creator) /ModDate (D:20240821153045Z) /Custom (opaque) >>".utf8),
      metadata,
    ], trailer: "/Info 3 0 R")
  }

  private func makePDF(objects: [Data], trailer: String = "") -> Data {
    var data = Data("%PDF-2.0\n".utf8)
    var offsets = [Int]()
    for (index, object) in objects.enumerated() {
      offsets.append(data.count)
      data.append(Data("\(index + 1) 0 obj\n".utf8))
      data.append(object)
      data.append(Data("\nendobj\n".utf8))
    }
    let xref = data.count
    data.append(Data("xref\n0 \(objects.count + 1)\n0000000000 65535 f \n".utf8))
    for offset in offsets { data.append(Data(String(format: "%010d 00000 n \n", offset).utf8)) }
    data.append(Data("trailer\n<< /Size \(objects.count + 1) /Root 1 0 R \(trailer) >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
    return data
  }
}
