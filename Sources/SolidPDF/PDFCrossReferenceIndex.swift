import Foundation

package enum PDFCrossReferenceEntry: Sendable, Hashable {
  case free(nextObjectNumber: Int, generationNumber: Int)
  case uncompressed(offset: Int64, generationNumber: Int)
  case compressed(objectStreamNumber: Int, index: Int)
}

struct PDFIndexedCrossReferenceEntry: Sendable, Hashable {
  let entry: PDFCrossReferenceEntry
  let definitionRevision: PDFRevisionIdentifier
}

struct PDFCrossReferenceIndex: Sendable {
  let version: PDFFileVersion
  let revisions: [PDFDocumentRevision]
  let snapshots: [PDFRevisionIdentifier: [Int: PDFIndexedCrossReferenceEntry]]
  let recoveryReport: PDFRecoveryReport?
  let recoveredObjectBoundaries: [Int: PDFRecoveredObjectBoundary]
  let recoveredValueOverrides: [Int: PDFObject]

  var latestRevision: PDFDocumentRevision { revisions[revisions.count - 1] }
  var entries: [Int: PDFCrossReferenceEntry] {
    snapshots[latestRevision.identifier, default: [:]].mapValues(\.entry)
  }
  var trailer: [PDFName: PDFObject] { latestRevision.trailer }
  var startCrossReferenceOffset: Int64 { latestRevision.startCrossReferenceOffset }
  var root: PDFObjectReference { latestRevision.root }
  var info: PDFObjectReference? { latestRevision.info }
  var identifier: [PDFString]? { latestRevision.fileIdentifier }
  var recoveryProvenance: PDFRecoveryProvenance? {
    guard let records = recoveryReport?.records, !records.isEmpty else { return nil }
    return PDFRecoveryProvenance(
      records: records.map(\.identifier),
      classification: records.contains(where: { $0.classification == .semanticInference })
        ? .semanticInference
        : .structuralRepair
    )
  }

  func entry(
    for objectNumber: Int,
    in revision: PDFRevisionIdentifier
  ) throws -> PDFIndexedCrossReferenceEntry? {
    guard let snapshot = snapshots[revision] else {
      throw PDFParsingError.unknownRevision(revision)
    }
    return snapshot[objectNumber]
  }

  static func recovered(
    plan: PDFRecoveredCrossReferencePlan,
    report: PDFRecoveryReport
  ) throws -> Self {
    guard let root = plan.trailer.pdfReference(named: "Root") else {
      throw PDFParsingError.malformed(
        .init(offset: plan.startOffset, message: "The recovered trailer lacks Root.")
      )
    }
    let documentIdentifier = UUID()
    let revisionIdentifier = PDFRevisionIdentifier(
      documentIdentifier: documentIdentifier,
      ordinal: 0
    )
    let provenance = report.records.isEmpty ? nil : PDFRecoveryProvenance(
      records: report.records.map(\.identifier),
      classification: report.records.contains(where: { $0.classification == .semanticInference })
        ? .semanticInference
        : .structuralRepair
    )
    let revision = PDFDocumentRevision(
      identifier: revisionIdentifier,
      representation: plan.representation,
      startCrossReferenceOffset: plan.startOffset,
      endOffset: plan.endOffset,
      trailer: plan.trailer,
      root: root,
      info: plan.trailer.pdfReference(named: "Info"),
      fileIdentifier: try parseRecoveredIdentifier(plan.trailer, offset: plan.startOffset),
      encryption: plan.trailer["Encrypt"],
      recoveryProvenance: provenance
    )
    let snapshot = plan.entries.mapValues {
      PDFIndexedCrossReferenceEntry(entry: $0, definitionRevision: revisionIdentifier)
    }
    return Self(
      version: plan.version,
      revisions: [revision],
      snapshots: [revisionIdentifier: snapshot],
      recoveryReport: report,
      recoveredObjectBoundaries: plan.boundaries,
      recoveredValueOverrides: plan.valueOverrides
    )
  }

  private static func parseRecoveredIdentifier(
    _ trailer: [PDFName: PDFObject],
    offset: Int64
  ) throws -> [PDFString]? {
    guard let values = trailer.pdfArray(named: "ID") else { return nil }
    let strings = values.compactMap { value -> PDFString? in
      guard case .string(let string) = value else { return nil }
      return string
    }
    guard strings.count == 2, strings.count == values.count else {
      throw PDFParsingError.malformed(
        .init(offset: offset, message: "The recovered trailer ID is malformed.")
      )
    }
    return strings
  }
}
