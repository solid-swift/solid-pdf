import SolidPDF

struct PDFContentInstruction {
  let operands: [PDFObject]
  let name: String
  let location: PDFContentLocation
}
