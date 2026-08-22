/// A standard or extension PDF annotation subtype.
public enum PDFAnnotationSubtype: Sendable, Hashable {
  case text
  case link
  case freeText
  case line
  case square
  case circle
  case polygon
  case polyLine
  case highlight
  case underline
  case squiggly
  case strikeOut
  case stamp
  case caret
  case ink
  case popup
  case fileAttachment
  case sound
  case movie
  case widget
  case screen
  case printerMark
  case trapNet
  case watermark
  case threeD
  case redact
  case projection
  case richMedia
  case unknown(PDFName)

  package init(name: PDFName) {
    self = switch name {
    case "Text": .text
    case "Link": .link
    case "FreeText": .freeText
    case "Line": .line
    case "Square": .square
    case "Circle": .circle
    case "Polygon": .polygon
    case "PolyLine": .polyLine
    case "Highlight": .highlight
    case "Underline": .underline
    case "Squiggly": .squiggly
    case "StrikeOut": .strikeOut
    case "Stamp": .stamp
    case "Caret": .caret
    case "Ink": .ink
    case "Popup": .popup
    case "FileAttachment": .fileAttachment
    case "Sound": .sound
    case "Movie": .movie
    case "Widget": .widget
    case "Screen": .screen
    case "PrinterMark": .printerMark
    case "TrapNet": .trapNet
    case "Watermark": .watermark
    case "3D": .threeD
    case "Redact": .redact
    case "Projection": .projection
    case "RichMedia": .richMedia
    default: .unknown(name)
    }
  }
}
