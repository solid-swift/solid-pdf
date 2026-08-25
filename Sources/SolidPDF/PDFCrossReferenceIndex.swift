import Foundation

enum PDFCrossReferenceEntry: Sendable, Hashable {
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
}
