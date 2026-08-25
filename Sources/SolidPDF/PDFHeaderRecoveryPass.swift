import Foundation

package struct PDFHeaderRecoveryPass: PDFRecoveryPass {
  package let descriptor = PDFRecoveryPassDescriptor(
    identifier: "source.displaced-header",
    stage: .sourceFraming,
    invalidates: [.crossReferenceDiscovery, .objectBoundaries, .streamBoundaries, .documentStructure, .finalValidation]
  )

  package init() {}

  package func evaluate(_ snapshot: PDFRecoverySnapshot) async throws -> PDFRecoveryPassResult {
    guard !snapshot.model.contains(fact: "header") else { return .noMatch }
    var proposals = [PDFRecoveryProposal]()
    for offset in snapshot.evidence.headerCandidates {
      let available = Int(min(16, snapshot.source.length - offset))
      guard available >= 8 else { continue }
      let bytes = try await snapshot.source.read(.init(uncheckedOffset: offset, length: available))
      guard bytes.starts(with: Data("%PDF-".utf8)),
        let end = bytes.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }),
        let raw = String(bytes: bytes[5..<end], encoding: .ascii),
        let version = PDFFileVersion(rawValue: raw)
      else { continue }
      proposals.append(
        .init(
          fact: "header",
          kind: .header,
          classification: offset == 0 ? .byteExact : .structuralRepair,
          sourceRanges: [.init(uncheckedOffset: offset, length: end)],
          message: offset == 0
            ? "The PDF header was confirmed at the start of the source."
            : "The PDF header was recovered after leading source bytes.",
          mutation: .header(offset: offset, version: version)
        )
      )
    }
    return proposals.isEmpty
      ? .unrecoverable(.init(offset: 0, message: "Recovery found no valid PDF header."))
      : .proposals(proposals)
  }
}
