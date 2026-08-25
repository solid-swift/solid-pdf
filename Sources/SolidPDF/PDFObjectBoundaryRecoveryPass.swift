package struct PDFObjectBoundaryRecoveryPass: PDFRecoveryPass {
  package let descriptor = PDFRecoveryPassDescriptor(
    identifier: "object.recover-boundary",
    stage: .objectBoundaries,
    priority: 100,
    invalidates: [.documentStructure, .finalValidation]
  )

  package init() {}

  package func evaluate(_ snapshot: PDFRecoverySnapshot) async throws -> PDFRecoveryPassResult {
    guard let plan = snapshot.model.reconstructedCrossReference else { return .noMatch }
    let proposals = plan.boundaries.values.compactMap { boundary -> PDFRecoveryProposal? in
      guard let repair = boundary.repair, repair.kind == .indirectObject else { return nil }
      let fact = "object-boundary-\(boundary.reference.objectNumber)-\(boundary.reference.generationNumber)"
      guard !snapshot.model.contains(fact: fact) else { return nil }
      return PDFRecoveryProposal(
        fact: fact,
        kind: repair.kind,
        classification: repair.classification,
        sourceRanges: repair.sourceRanges,
        object: boundary.reference,
        message: repair.message,
        mutation: .recordedFact(fact)
      )
    }
    return proposals.isEmpty ? .noMatch : .proposals(proposals)
  }
}
