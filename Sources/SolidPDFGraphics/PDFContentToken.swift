import SolidPDF

struct PDFContentToken {
  enum Value {
    case object(PDFObject)
    case keyword(String)
  }

  let value: Value
  let location: PDFContentLocation

  init(object: PDFObject, location: PDFContentLocation) {
    value = .object(object)
    self.location = location
  }

  init(keyword: String, location: PDFContentLocation) {
    value = .keyword(keyword)
    self.location = location
  }
}
