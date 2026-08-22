import Foundation

/// The typed, inert operation described by a PDF action dictionary.
public enum PDFActionKind: Sendable, Hashable {
  case goTo(PDFDestination)
  case goToRemote(file: PDFObject, destination: PDFDestination?, newWindow: Bool?)
  case goToEmbedded(file: PDFObject?, target: PDFObject, destination: PDFDestination?, newWindow: Bool?)
  case launch(file: PDFObject?, platformParameters: PDFObject?)
  case thread(file: PDFObject?, thread: PDFObject, bead: PDFObject?)
  case uri(PDFString, isMap: Bool)
  case sound(PDFObject)
  case movie(annotation: PDFObject?, title: PDFString?, operation: PDFName?)
  case hide(target: PDFObject, hidden: Bool)
  case named(PDFName)
  case submitForm(file: PDFObject, fields: [PDFObject], flags: Int64)
  case resetForm(fields: [PDFObject], flags: Int64)
  case importData(PDFObject)
  case javaScript(PDFObject)
  case setOptionalContentState([PDFObject], preserveRadioButtonState: Bool)
  case rendition(PDFObject)
  case transition(PDFObject)
  case goToThreeDView(annotation: PDFObject, view: PDFObject)
  case unknown(PDFName)
}

/// A parsed PDF action and its bounded `/Next` chain.
public struct PDFAction: Sendable, Hashable {
  public let kind: PDFActionKind
  public let next: [PDFAction]
  public let rawDictionary: [PDFName: PDFObject]

  public init(
    kind: PDFActionKind,
    next: [PDFAction] = [],
    rawDictionary: [PDFName: PDFObject]
  ) {
    self.kind = kind
    self.next = next
    self.rawDictionary = rawDictionary
  }
}
