import Foundation
import SolidPDF

struct PDFInlineImage {
  let dictionary: [PDFName: PDFObject]
  let data: Data
  let location: PDFContentLocation
}
