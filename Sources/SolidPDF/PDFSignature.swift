import Foundation

/// A structurally parsed PDF signature value without cryptographic validation.
public struct PDFSignature: Sendable, Hashable {
  /// The signature's document-scoped identity, when it is stored indirectly.
  public let identifier: PDFSignatureIdentifier?
  /// The semantic role of the signature.
  public let kind: PDFSignatureKind
  /// The indirect signature dictionary reference, when available.
  public let dictionaryReference: PDFObjectReference?
  /// Signed source ranges in declared order.
  public let byteRanges: [PDFSourceRange]
  /// The decoded signature container bytes.
  public let contents: Data
  /// The preferred signature handler.
  public let filter: PDFName?
  /// The signature encoding or subfilter.
  public let subfilter: PDFName?
  /// The signer's stated reason.
  public let reason: String?
  /// The PDF date string retained without interpretation.
  public let signingTime: PDFString?
  /// Optional seed-value or document permission metadata.
  public let permissions: PDFObject?
  /// The original signature dictionary.
  public let rawDictionary: [PDFName: PDFObject]
  /// The revision defining the signature value.
  public let definingRevision: PDFRevisionIdentifier
  /// The exact lexical source range of the `/Contents` string token.
  public let contentsSourceRange: PDFSourceRange?
  /// The revision whose terminal boundary contains the declared signed ranges.
  public let signedRevision: PDFRevisionIdentifier?
  /// The parsed external signature container, when supported and well formed.
  public let container: PDFSignatureContainer?
  /// Portable signer metadata parsed from the external container.
  public let signers: [PDFSignatureSigner]
  /// Signature transforms in declaration order.
  public let transforms: [PDFSignatureTransform]

  package init(
    identifier: PDFSignatureIdentifier? = nil,
    kind: PDFSignatureKind = .approval,
    dictionaryReference: PDFObjectReference? = nil,
    byteRanges: [PDFSourceRange],
    contents: Data,
    filter: PDFName?,
    subfilter: PDFName?,
    reason: String?,
    signingTime: PDFString?,
    permissions: PDFObject?,
    rawDictionary: [PDFName: PDFObject],
    definingRevision: PDFRevisionIdentifier,
    contentsSourceRange: PDFSourceRange? = nil,
    signedRevision: PDFRevisionIdentifier? = nil,
    container: PDFSignatureContainer? = nil,
    signers: [PDFSignatureSigner] = [],
    transforms: [PDFSignatureTransform] = []
  ) {
    self.identifier = identifier
    self.kind = kind
    self.dictionaryReference = dictionaryReference
    self.byteRanges = byteRanges
    self.contents = contents
    self.filter = filter
    self.subfilter = subfilter
    self.reason = reason
    self.signingTime = signingTime
    self.permissions = permissions
    self.rawDictionary = rawDictionary
    self.definingRevision = definingRevision
    self.contentsSourceRange = contentsSourceRange
    self.signedRevision = signedRevision
    self.container = container
    self.signers = signers
    self.transforms = transforms
  }
}
