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
    let pages = try writer.reserveObject()
    let stream = try writer.reserveObject()
    try writer.write(
      .dictionary([
        "Type": .name("Catalog"), "Pages": .reference(pages), "Stream": .reference(stream),
      ]),
      to: catalog
    )
    try writer.write(
      .dictionary(["Type": .name("Pages"), "Count": .integer(0), "Kids": .array([])]),
      to: pages
    )
    try writer.writeStream(chunks: [bytes], compressed: compressed, to: stream)
    return try writer.finish(root: catalog, pageCount: 0).data
  }

  /// Creates a classic document with the requested number of chronological revisions.
  public static func incrementalDocument(revisionCount: Int = 256) -> Data {
    precondition(revisionCount > 0)
    var data = Data("%PDF-1.7\n".utf8)
    let rootOffset = data.count
    data.append(Data("1 0 obj\n<< /Type /Catalog /Pages 3 0 R /Value 2 0 R >>\nendobj\n".utf8))
    var valueOffset = data.count
    data.append(Data("2 0 obj\n0\nendobj\n".utf8))
    let pagesOffset = data.count
    data.append(Data("3 0 obj\n<< /Type /Pages /Count 0 /Kids [] >>\nendobj\n".utf8))
    var previousXRefOffset = data.count
    data.append(Data("xref\n0 4\n0000000000 65535 f \n".utf8))
    data.append(Data(String(format: "%010d 00000 n \n", rootOffset).utf8))
    data.append(Data(String(format: "%010d 00000 n \n", valueOffset).utf8))
    data.append(Data(String(format: "%010d 00000 n \n", pagesOffset).utf8))
    data.append(Data("trailer\n<< /Size 4 /Root 1 0 R >>\n".utf8))
    data.append(Data("startxref\n\(previousXRefOffset)\n%%EOF\n".utf8))

    for revision in 1..<revisionCount {
      valueOffset = data.count
      data.append(Data("2 0 obj\n\(revision)\nendobj\n".utf8))
      let xrefOffset = data.count
      data.append(Data("xref\n2 1\n".utf8))
      data.append(Data(String(format: "%010d 00000 n \n", valueOffset).utf8))
      data.append(
        Data(
          ("trailer\n<< /Size 4 /Root 1 0 R /Prev \(previousXRefOffset) >>\n"
            + "startxref\n\(xrefOffset)\n%%EOF\n").utf8
        )
      )
      previousXRefOffset = xrefOffset
    }
    return data
  }

  /// Creates a balanced page tree with inherited resources, labels, and shared content.
  public static func pageTreeDocument(pageCount: Int = 4_096, branchSize: Int = 32) throws -> Data {
    precondition(pageCount > 0 && branchSize > 1)
    var writer = try PDFDocumentWriter(
      sink: PDFDataOutputSink(),
      options: .init(version: .v2_0, compressionLevel: 0)
    )
    let catalog = try writer.reserveObject()
    let content = try writer.reserveObject()
    var pageReferences = [PDFObjectReference]()
    pageReferences.reserveCapacity(pageCount)
    for _ in 0..<pageCount { pageReferences.append(try writer.reserveObject()) }

    struct Node {
      let reference: PDFObjectReference
      let kids: [PDFObjectReference]
      let count: Int
    }
    var nodes = [Node]()
    var parentByChild = [PDFObjectReference: PDFObjectReference]()
    var level = pageReferences.map { ($0, 1) }
    while level.count > 1 || nodes.isEmpty {
      var next = [(PDFObjectReference, Int)]()
      for start in stride(from: 0, to: level.count, by: branchSize) {
        let slice = Array(level[start..<min(level.count, start + branchSize)])
        let reference = try writer.reserveObject()
        let kids = slice.map(\.0)
        let count = slice.reduce(0) { $0 + $1.1 }
        for child in kids { parentByChild[child] = reference }
        nodes.append(Node(reference: reference, kids: kids, count: count))
        next.append((reference, count))
      }
      level = next
      if level.count == 1 { break }
    }
    let root = level[0].0
    try writer.write(
      .dictionary([
        "Type": .name("Catalog"),
        "Pages": .reference(root),
        "PageLabels": .dictionary([
          "Nums": .array([
            .integer(0),
            .dictionary(["S": .name("D"), "P": .string("Page ")]),
          ])
        ]),
      ]),
      to: catalog
    )
    try writer.writeStream(chunks: [Data("q Q\n".utf8)], compressed: false, to: content)
    for page in pageReferences {
      try writer.write(
        .dictionary([
          "Type": .name("Page"),
          "Parent": .reference(parentByChild[page]!),
          "Contents": .reference(content),
        ]),
        to: page
      )
    }
    for node in nodes {
      var dictionary: [PDFName: PDFObject] = [
        "Type": .name("Pages"),
        "Count": .integer(node.count),
        "Kids": .array(node.kids.map(PDFObject.reference)),
      ]
      if let parent = parentByChild[node.reference] {
        dictionary["Parent"] = .reference(parent)
      } else {
        dictionary["MediaBox"] = .array([.integer(0), .integer(0), .integer(612), .integer(792)])
        dictionary["Resources"] = .dictionary([:])
      }
      try writer.write(.dictionary(dictionary), to: node.reference)
    }
    return try writer.finish(root: catalog, pageCount: pageCount).data
  }

  /// A qpdf-authored R4 RC4 interoperability fixture with password `user`.
  public static let r4RC4Document = decodedFixture(
    "JVBERi0xLjcKJb/3ov4KMSAwIG9iago8PCAvUGFnZXMgMiAwIFIgL1R5cGUgL0NhdGFsb2cgPj4K"
      + "ZW5kb2JqCjIgMCBvYmoKPDwgL0NvdW50IDEgL0tpZHMgWyAzIDAgUiBdIC9UeXBlIC9QYWdlcyA+"
      + "PgplbmRvYmoKMyAwIG9iago8PCAvQ29udGVudHMgNCAwIFIgL01lZGlhQm94IFsgMCAwIDcyIDcy"
      + "IF0gL1BhcmVudCAyIDAgUiAvUmVzb3VyY2VzIDw8ID4+IC9UeXBlIC9QYWdlID4+CmVuZG9iago0"
      + "IDAgb2JqCjw8IC9MZW5ndGggMjEgL0ZpbHRlciAvRmxhdGVEZWNvZGUgPj4Kc3RyZWFtCvHI+jNH"
      + "nAp9HzpCwAOSbNTgIYqERmVuZHN0cmVhbQplbmRvYmoKNSAwIG9iago8PCAvQ0YgPDwgL1N0ZENG"
      + "IDw8IC9BdXRoRXZlbnQgL0RvY09wZW4gL0NGTSAvVjIgL0xlbmd0aCAxNiA+PiA+PiAvRmlsdGVy"
      + "IC9TdGFuZGFyZCAvTGVuZ3RoIDEyOCAvTyA8MGJhMzgzNWY4OGY5MDM4OGU3NGU1NDU4NDEyNWNl"
      + "MTQyYmUwZGUyNGM2YjBkMzc3NDZlMDc1Yjg5MTc1NjY3MT4gL1AgLTQgL1IgNCAvU3RtRiAvU3Rk"
      + "Q0YgL1N0ckYgL1N0ZENGIC9VIDxmYWY1YzUxYjRlMDY5Mjk0ZTc5NmEzNzAyM2NkYzcwMDAxMjI0"
      + "NTZhOTFiYWU1MTM0MjczYTZkYjEzNGM4N2M0PiAvViA0ID4+CmVuZG9iagp4cmVmCjAgNgowMDAw"
      + "MDAwMDAwIDY1NTM1IGYgCjAwMDAwMDAwMTUgMDAwMDAgbiAKMDAwMDAwMDA2NCAwMDAwMCBuIAow"
      + "MDAwMDAwMTIzIDAwMDAwIG4gCjAwMDAwMDAyMjcgMDAwMDAgbiAKMDAwMDAwMDMxOCAwMDAwMCBu"
      + "IAp0cmFpbGVyIDw8IC9Sb290IDEgMCBSIC9TaXplIDYgL0lEIFs8YzY1ZDk4ZmRhN2UzMjZmNjU4"
      + "M2IwMjQ1OTFhN2ViOTQ+PDljYzk1MzAzODljODYyYzBkNzA3NDkxM2I3MjZhMTkyPl0gL0VuY3J5"
      + "cHQgNSAwIFIgPj4Kc3RhcnR4cmVmCjYxNAolJUVPRgo="
  )

  /// A qpdf-authored R6 AES-256 interoperability fixture with password `user`.
  public static let r6AESDocument = decodedFixture(
    "JVBERi0xLjcKJb/3ov4KMSAwIG9iago8PCAvRXh0ZW5zaW9ucyA8PCAvQURCRSA8PCAvQmFzZVZl"
      + "cnNpb24gLzEuNyAvRXh0ZW5zaW9uTGV2ZWwgOCA+PiA+PiAvUGFnZXMgMiAwIFIgL1R5cGUgL0Nh"
      + "dGFsb2cgPj4KZW5kb2JqCjIgMCBvYmoKPDwgL0NvdW50IDEgL0tpZHMgWyAzIDAgUiBdIC9UeXBl"
      + "IC9QYWdlcyA+PgplbmRvYmoKMyAwIG9iago8PCAvQ29udGVudHMgNCAwIFIgL01lZGlhQm94IFsg"
      + "MCAwIDcyIDcyIF0gL1BhcmVudCAyIDAgUiAvUmVzb3VyY2VzIDw8ID4+IC9UeXBlIC9QYWdlID4+"
      + "CmVuZG9iago0IDAgb2JqCjw8IC9MZW5ndGggNDggL0ZpbHRlciAvRmxhdGVEZWNvZGUgPj4Kc3Ry"
      + "ZWFtCj8KPfDd3xcAztqZn5+BiW0k+RkDozTea3v1WzJRkL6I39LZ6sQxVqN1LdPCQfRvEGVuZHN0"
      + "cmVhbQplbmRvYmoKNSAwIG9iago8PCAvQ0YgPDwgL1N0ZENGIDw8IC9BdXRoRXZlbnQgL0RvY09w"
      + "ZW4gL0NGTSAvQUVTVjMgL0xlbmd0aCAzMiA+PiA+PiAvRmlsdGVyIC9TdGFuZGFyZCAvTGVuZ3Ro"
      + "IDI1NiAvTyA8MGViYzJiYzA5MTlhOWMxYzRiMDM2NDAwZDNjZTA5ZGVhMDg3ZmYxMDExMjQ3NGJj"
      + "OGY4MGI1ZWY4N2RjOWFhYWMwMzhhMTVjZTVhMjBkZDdjNTMyMmE3MDMxOTUwOGE0PiAvT0UgPDNm"
      + "ZTViZmNhYWViOTE0Y2I2NzVjMzcyYjMzMzJiZTY2YjBiZjNmN2QwZTYwZWQ1ZDJjNGNiM2EzOGNj"
      + "YTNmODc+IC9QIC00IC9QZXJtcyA8Y2YzOTEwMmI3MDEwMmU4YjY5ZThkYTExZThhZDEwOTc+IC9S"
      + "IDYgL1N0bUYgL1N0ZENGIC9TdHJGIC9TdGRDRiAvVSA8NzlmNWZjNzhjOTU1NDdlNmQ5NDBjZjYy"
      + "ODM0ZjZmMmUyNzA0NTE3MzJmM2ZmNTUxYTdlZTMyMTFmMWQ2N2ExNTIwZjM5Y2ZkYjViNGZlOGE5"
      + "N2Q5Nzg1MmJjYjUyMGZhPiAvVUUgPDZlMmExY2Q0NWE2NDg1MzExMTc5YTFhMWUxMmUwN2VlMjhk"
      + "OTk1YWEwZThlNmFkZTQ0YjI1ZDJkYjhlNWEwYmI+IC9WIDUgPj4KZW5kb2JqCnhyZWYKMCA2CjAw"
      + "MDAwMDAwMDAgNjU1MzUgZiAKMDAwMDAwMDAxNSAwMDAwMCBuIAowMDAwMDAwMTMwIDAwMDAwIG4g"
      + "CjAwMDAwMDAxODkgMDAwMDAgbiAKMDAwMDAwMDI5MyAwMDAwMCBuIAowMDAwMDAwNDExIDAwMDAw"
      + "IG4gCnRyYWlsZXIgPDwgL1Jvb3QgMSAwIFIgL1NpemUgNiAvSUQgWzxjNjVkOThmZGE3ZTMyNmY2"
      + "NTgzYjAyNDU5MWE3ZWI5ND48NzYyYzY5NjI5OTc3YmI0MjBjZDhjNGE5MWY5MjQ1NTg+XSAvRW5j"
      + "cnlwdCA1IDAgUiA+PgpzdGFydHhyZWYKOTU4CiUlRU9GCg=="
  )

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

  private static func decodedFixture(_ value: String) -> Data {
    guard let data = Data(base64Encoded: value) else {
      preconditionFailure("A checked-in PDF benchmark fixture is malformed.")
    }
    return data
  }
}
