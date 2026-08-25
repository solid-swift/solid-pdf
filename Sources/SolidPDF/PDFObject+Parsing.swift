import Foundation

extension Dictionary where Key == PDFName, Value == PDFObject {
  func pdfObject(named name: PDFName) -> PDFObject? {
    self[name]
  }

  func pdfInteger(named name: PDFName) -> Int64? {
    guard case .number(.integer(let value)) = self[name] else { return nil }
    return value
  }

  func pdfName(named name: PDFName) -> PDFName? {
    guard case .name(let value) = self[name] else { return nil }
    return value
  }

  func pdfReference(named name: PDFName) -> PDFObjectReference? {
    guard case .reference(let value) = self[name] else { return nil }
    return value
  }

  func pdfArray(named name: PDFName) -> [PDFObject]? {
    guard case .array(let value) = self[name] else { return nil }
    return value
  }
}
