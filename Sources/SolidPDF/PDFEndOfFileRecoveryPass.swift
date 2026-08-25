package struct PDFEndOfFileRecoveryPass: PDFRecoveryPass {
  package let descriptor = PDFRecoveryPassDescriptor(
    identifier: "source.terminal-eof",
    stage: .sourceFraming
  )

  package init() {}

  package func evaluate(_ snapshot: PDFRecoverySnapshot) async throws -> PDFRecoveryPassResult {
    guard !snapshot.model.contains(fact: "end-of-file") else { return .noMatch }
    if let marker = snapshot.evidence.endOfFileCandidates.last {
      let end = marker + 5
      let trailingLength = Int(snapshot.source.length - end)
      let trailing = try await snapshot.source.read(
        .init(uncheckedOffset: end, length: trailingLength)
      )
      let whitespaceOnly = trailing.allSatisfy(Self.isWhitespace)
      guard whitespaceOnly || snapshot.policy == .compatible else {
        return .unrecoverable(
          .init(offset: end, message: "Non-whitespace follows the terminal %%EOF marker.")
        )
      }
      return .proposals([
        .init(
          fact: "end-of-file",
          kind: .endOfFile,
          classification: whitespaceOnly ? .byteExact : .semanticInference,
          sourceRanges: [.init(uncheckedOffset: marker, length: 5)],
          message: whitespaceOnly
            ? "The terminal %%EOF marker was confirmed."
            : "Compatibility recovery selected the last %%EOF marker before trailing data.",
          mutation: .endOfFile(offset: end, acceptsMissingMarker: false)
        )
      ])
    }
    return .proposals([
      .init(
        fact: "end-of-file",
        kind: .endOfFile,
        classification: .structuralRepair,
        sourceRanges: [.init(uncheckedOffset: snapshot.source.length, length: 0)],
        message: "The physical source end was used for a missing %%EOF marker.",
        mutation: .endOfFile(offset: snapshot.source.length, acceptsMissingMarker: true)
      )
    ])
  }

  private static func isWhitespace(_ byte: UInt8) -> Bool {
    byte == 0 || byte == 0x09 || byte == 0x0A || byte == 0x0C || byte == 0x0D || byte == 0x20
  }
}
