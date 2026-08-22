/// Common typed fields retained for subtype-specific annotation processing.
public struct PDFAnnotationPayload: Sendable, Hashable {
  /// Optional geometric vertices, quad points, or line endpoints.
  public let points: [Double]
  /// Optional ink paths represented as coordinate arrays.
  public let inkLists: [[Double]]
  /// The associated destination, when present.
  public let destination: PDFDestination?
  /// The associated inert action, when present.
  public let action: PDFAction?
  /// The popup annotation associated with markup.
  public let popup: PDFAnnotationIdentifier?
  /// The annotation to which this annotation replies.
  public let replyTo: PDFAnnotationIdentifier?
  /// The reply relationship name.
  public let replyType: PDFName?
  /// Subtype-specific entries not normalized by this release.
  public let extensions: [PDFName: PDFObject]

  public init(
    points: [Double] = [],
    inkLists: [[Double]] = [],
    destination: PDFDestination? = nil,
    action: PDFAction? = nil,
    popup: PDFAnnotationIdentifier? = nil,
    replyTo: PDFAnnotationIdentifier? = nil,
    replyType: PDFName? = nil,
    extensions: [PDFName: PDFObject] = [:]
  ) {
    self.points = points
    self.inkLists = inkLists
    self.destination = destination
    self.action = action
    self.popup = popup
    self.replyTo = replyTo
    self.replyType = replyType
    self.extensions = extensions
  }
}

/// Subtype-discriminated annotation semantics.
public enum PDFAnnotationDetails: Sendable, Hashable {
  case text(PDFAnnotationPayload)
  case link(PDFAnnotationPayload)
  case freeText(PDFAnnotationPayload)
  case line(PDFAnnotationPayload)
  case square(PDFAnnotationPayload)
  case circle(PDFAnnotationPayload)
  case polygon(PDFAnnotationPayload)
  case polyLine(PDFAnnotationPayload)
  case highlight(PDFAnnotationPayload)
  case underline(PDFAnnotationPayload)
  case squiggly(PDFAnnotationPayload)
  case strikeOut(PDFAnnotationPayload)
  case stamp(PDFAnnotationPayload)
  case caret(PDFAnnotationPayload)
  case ink(PDFAnnotationPayload)
  case popup(PDFAnnotationPayload)
  case fileAttachment(PDFAnnotationPayload)
  case sound(PDFAnnotationPayload)
  case movie(PDFAnnotationPayload)
  case widget(PDFAnnotationPayload)
  case screen(PDFAnnotationPayload)
  case printerMark(PDFAnnotationPayload)
  case trapNet(PDFAnnotationPayload)
  case watermark(PDFAnnotationPayload)
  case threeD(PDFAnnotationPayload)
  case redact(PDFAnnotationPayload)
  case projection(PDFAnnotationPayload)
  case richMedia(PDFAnnotationPayload)
  case unknown(PDFName, PDFAnnotationPayload)
}

/// One lazily resolved page annotation.
public struct PDFAnnotation: Sendable, Hashable {
  public let identifier: PDFAnnotationIdentifier
  public let subtype: PDFAnnotationSubtype
  public let pageReference: PDFObjectReference
  public let rectangle: PDFRectangle
  public let flags: PDFAnnotationFlags
  public let contents: String?
  public let alternateDescription: String?
  public let title: String?
  public let uniqueName: PDFString?
  public let appearanceState: PDFName?
  public let appearances: PDFAnnotationAppearances
  public let optionalContent: PDFObject?
  public let details: PDFAnnotationDetails
  public let rawDictionary: [PDFName: PDFObject]
  public let definingRevision: PDFRevisionIdentifier

  package init(
    identifier: PDFAnnotationIdentifier,
    subtype: PDFAnnotationSubtype,
    pageReference: PDFObjectReference,
    rectangle: PDFRectangle,
    flags: PDFAnnotationFlags,
    contents: String?,
    alternateDescription: String?,
    title: String?,
    uniqueName: PDFString?,
    appearanceState: PDFName?,
    appearances: PDFAnnotationAppearances,
    optionalContent: PDFObject?,
    details: PDFAnnotationDetails,
    rawDictionary: [PDFName: PDFObject],
    definingRevision: PDFRevisionIdentifier
  ) {
    self.identifier = identifier
    self.subtype = subtype
    self.pageReference = pageReference
    self.rectangle = rectangle
    self.flags = flags
    self.contents = contents
    self.alternateDescription = alternateDescription
    self.title = title
    self.uniqueName = uniqueName
    self.appearanceState = appearanceState
    self.appearances = appearances
    self.optionalContent = optionalContent
    self.details = details
    self.rawDictionary = rawDictionary
    self.definingRevision = definingRevision
  }
}
