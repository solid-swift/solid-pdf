import Foundation

package struct PDFDocumentStructureRecoveryPass: PDFRecoveryPass {
  package let descriptor = PDFRecoveryPassDescriptor(
    identifier: "structure.recover-catalog-types",
    stage: .documentStructure,
    priority: 100,
    invalidates: [.finalValidation]
  )

  package init() {}

  package func evaluate(_ snapshot: PDFRecoverySnapshot) async throws -> PDFRecoveryPassResult {
    guard let plan = snapshot.model.reconstructedCrossReference,
      !snapshot.model.contains(fact: "document-structure")
    else { return .noMatch }
    var objects = [Int: PDFRecoveryObjectCandidateParser.Parsed]()
    for candidate in snapshot.evidence.indirectObjectCandidates {
      guard plan.boundaries[candidate.reference.objectNumber]?.reference == candidate.reference,
        let parsed = try await PDFRecoveryObjectCandidateParser.parse(candidate, snapshot: snapshot)
      else { continue }
      objects[candidate.reference.objectNumber] = parsed
    }
    var trailer = plan.trailer
    var overrides = plan.valueOverrides
    var classification = PDFRecoveryClassification.structuralRepair
    var evidence = [PDFSourceRange]()
    let rootReference: PDFObjectReference
    if let existing = trailer.pdfReference(named: "Root"), objects[existing.objectNumber]?.boundary.reference == existing {
      rootReference = existing
    } else {
      let candidates = objects.values.filter { parsed in
        guard case .dictionary(let dictionary) = parsed.value,
          dictionary.pdfReference(named: "Pages") != nil
        else { return false }
        let type = dictionary.pdfName(named: "Type")
        return type == nil || type?.bytes == Data("Catalog".utf8)
      }.sorted { $0.boundary.sourceRange.offset < $1.boundary.sourceRange.offset }
      guard !candidates.isEmpty else {
        return .unrecoverable(.init(offset: plan.startOffset, message: "Recovery found no valid Catalog candidate."))
      }
      if candidates.count != 1 {
        guard snapshot.policy == .compatible else {
          return .unrecoverable(.init(offset: plan.startOffset, message: "Multiple Catalog candidates are ambiguous."))
        }
        classification = .semanticInference
      }
      let selected = candidates[candidates.count - 1]
      rootReference = selected.boundary.reference
      trailer["Root"] = .reference(rootReference)
      evidence.append(selected.boundary.sourceRange)
    }
    guard let rootObject = objects[rootReference.objectNumber],
      case .dictionary(var catalog) = rootObject.value,
      let pagesReference = catalog.pdfReference(named: "Pages"),
      let pagesObject = objects[pagesReference.objectNumber],
      pagesObject.boundary.reference == pagesReference,
      case .dictionary(var pages) = pagesObject.value,
      pages.pdfArray(named: "Kids") != nil,
      let pageCount = pages.pdfInteger(named: "Count"), pageCount >= 0
    else {
      return .unrecoverable(.init(offset: plan.startOffset, message: "The recovered Catalog and Pages structure is incomplete."))
    }
    if catalog.pdfName(named: "Type")?.bytes != Data("Catalog".utf8) {
      guard catalog["Type"] == nil else {
        return .unrecoverable(.init(offset: rootObject.boundary.sourceRange.offset, message: "The Catalog Type is invalid."))
      }
      catalog["Type"] = .name(PDFName("Catalog"))
      overrides[rootReference.objectNumber] = .dictionary(catalog)
      evidence.append(rootObject.boundary.sourceRange)
    }
    if pages.pdfName(named: "Type")?.bytes != Data("Pages".utf8) {
      guard pages["Type"] == nil else {
        return .unrecoverable(.init(offset: pagesObject.boundary.sourceRange.offset, message: "The Pages Type is invalid."))
      }
      pages["Type"] = .name(PDFName("Pages"))
      overrides[pagesReference.objectNumber] = .dictionary(pages)
      evidence.append(pagesObject.boundary.sourceRange)
    }
    let updated = PDFRecoveredCrossReferencePlan(
      version: plan.version,
      representation: plan.representation,
      entries: plan.entries,
      trailer: trailer,
      boundaries: plan.boundaries,
      valueOverrides: overrides,
      startOffset: plan.startOffset,
      endOffset: plan.endOffset
    )
    return .proposals([
      PDFRecoveryProposal(
        fact: "document-structure",
        kind: .catalog,
        classification: classification,
        sourceRanges: evidence.isEmpty ? [.init(uncheckedOffset: plan.startOffset, length: 0)] : evidence,
        message: classification == .semanticInference
          ? "Compatibility recovery selected the latest valid Catalog and restored required document types."
          : "Recovery established the unique Catalog and required document types.",
        mutation: .updatedCrossReference(updated)
      )
    ])
  }
}
