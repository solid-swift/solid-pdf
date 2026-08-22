import Foundation
import SolidPDF

/// Deterministic PDF fixtures shared by parser benchmarks and interoperability checks.
public enum PDFParsingBenchmarkFixtures {
  /// Creates a valid one-page document with additional independently resolvable objects.
  public static func document(version: PDFVersion, additionalObjectCount: Int = 0) throws -> Data {
    precondition(additionalObjectCount >= 0)
    var writer = try PDFDocumentWriter(
      sink: PDFDataOutputSink(),
      options: .init(version: version, compressionLevel: 0)
    )
    let catalog = try writer.reserveObject()
    let pages = try writer.reserveObject()
    let page = try writer.reserveObject()
    let contents = try writer.reserveObject()
    var additional = [PDFObjectReference]()
    additional.reserveCapacity(additionalObjectCount)
    for _ in 0..<additionalObjectCount {
      additional.append(try writer.reserveObject())
    }

    try writer.write(
      .dictionary(["Type": .name("Catalog"), "Pages": .reference(pages)]),
      to: catalog
    )
    try writer.write(
      .dictionary([
        "Type": .name("Pages"),
        "Count": .integer(1),
        "Kids": .array([.reference(page)]),
      ]),
      to: pages
    )
    try writer.write(
      .dictionary([
        "Type": .name("Page"),
        "Parent": .reference(pages),
        "MediaBox": .array([.integer(0), .integer(0), .integer(72), .integer(72)]),
        "Resources": .dictionary([:]),
        "Contents": .reference(contents),
      ]),
      to: page
    )
    try writer.writeStream(
      chunks: [Data("0 0 m 72 72 l S\n".utf8)],
      compressed: false,
      to: contents
    )
    for (index, reference) in additional.enumerated() {
      try writer.write(.dictionary(["Value": .integer(index)]), to: reference)
    }
    return try writer.finish(root: catalog, pageCount: 1).data
  }

  /// Creates a PDF 1.7 document containing the requested number of compressed objects.
  public static func objectStreamDocument(containedObjectCount: Int = 1_000) -> Data {
    precondition(containedObjectCount > 0)
    var data = Data("%PDF-1.7\n".utf8)
    let catalogOffset = data.count
    data.append(Data("1 0 obj\n<< /Type /Catalog /Pages 2 0 R /Member 4 0 R >>\nendobj\n".utf8))
    let pagesOffset = data.count
    data.append(Data("2 0 obj\n<< /Type /Pages /Count 0 /Kids [] >>\nendobj\n".utf8))

    let objectStreamOffset = data.count
    var header = Data()
    var body = Data()
    for index in 0..<containedObjectCount {
      let objectNumber = 4 + index
      header.append(Data("\(objectNumber) \(body.count) ".utf8))
      body.append(Data("<< /Value \(index) >> ".utf8))
    }
    let payload = header + body
    data.append(
      Data(
        ("3 0 obj\n<< /Type /ObjStm /N \(containedObjectCount) /First \(header.count) "
          + "/Length \(payload.count) >>\nstream\n").utf8
      )
    )
    data.append(payload)
    data.append(Data("\nendstream\nendobj\n".utf8))

    let xrefObjectNumber = containedObjectCount + 4
    let xrefOffset = data.count
    var entries = Data()
    appendXRefEntry(type: 0, field2: 0, field3: 65_535, to: &entries)
    appendXRefEntry(type: 1, field2: catalogOffset, field3: 0, to: &entries)
    appendXRefEntry(type: 1, field2: pagesOffset, field3: 0, to: &entries)
    appendXRefEntry(type: 1, field2: objectStreamOffset, field3: 0, to: &entries)
    for index in 0..<containedObjectCount {
      appendXRefEntry(type: 2, field2: 3, field3: index, to: &entries)
    }
    appendXRefEntry(type: 1, field2: xrefOffset, field3: 0, to: &entries)
    data.append(
      Data(
        ("\(xrefObjectNumber) 0 obj\n"
          + "<< /Type /XRef /Size \(xrefObjectNumber + 1) /Root 1 0 R /W [1 4 2] "
          + "/Length \(entries.count) >>\nstream\n").utf8
      )
    )
    data.append(entries)
    data.append(Data("\nendstream\nendobj\nstartxref\n\(xrefOffset)\n%%EOF\n".utf8))
    return data
  }

  /// Creates a document whose catalog references one large stream directly.
  public static func streamDocument(bytes: Data, compressed: Bool) throws -> Data {
    var writer = try PDFDocumentWriter(
      sink: PDFDataOutputSink(),
      options: .init(version: .v1_7)
    )
    let catalog = try writer.reserveObject()
    let stream = try writer.reserveObject()
    try writer.write(
      .dictionary(["Type": .name("Catalog"), "Stream": .reference(stream)]),
      to: catalog
    )
    try writer.writeStream(chunks: [bytes], compressed: compressed, to: stream)
    return try writer.finish(root: catalog, pageCount: 0).data
  }

  private static func appendXRefEntry(
    type: UInt8,
    field2: Int,
    field3: Int,
    to data: inout Data
  ) {
    data.append(type)
    data.append(UInt8((field2 >> 24) & 0xFF))
    data.append(UInt8((field2 >> 16) & 0xFF))
    data.append(UInt8((field2 >> 8) & 0xFF))
    data.append(UInt8(field2 & 0xFF))
    data.append(UInt8((field3 >> 8) & 0xFF))
    data.append(UInt8(field3 & 0xFF))
  }
}
