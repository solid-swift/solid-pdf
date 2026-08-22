import Foundation

enum PDFCrossReferenceEntry: Sendable, Hashable {
  case free(nextObjectNumber: Int, generationNumber: Int)
  case uncompressed(offset: Int64, generationNumber: Int)
  case compressed(objectStreamNumber: Int, index: Int)
}

struct PDFCrossReferenceIndex: Sendable {
  let version: PDFFileVersion
  let entries: [Int: PDFCrossReferenceEntry]
  let trailer: [PDFName: PDFObject]
  let startCrossReferenceOffset: Int64
  let root: PDFObjectReference
  let info: PDFObjectReference?
  let identifier: [PDFString]?
}
