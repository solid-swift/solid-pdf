import Foundation

actor PDFDocumentAuthenticity<Session: PDFInputSourceSession> {
  private let resolver: PDFDocumentResolver<Session>
  private let structure: PDFDocumentStructure<Session>
  private let interactive: PDFDocumentInteractiveStructure<Session>
  private let revisions: [PDFDocumentRevision]
  private let limits: PDFParsingLimits
  private var signaturesByRevision = [PDFRevisionIdentifier: [PDFSignature]]()
  private var closed = false

  init(
    resolver: PDFDocumentResolver<Session>,
    structure: PDFDocumentStructure<Session>,
    interactive: PDFDocumentInteractiveStructure<Session>,
    revisions: [PDFDocumentRevision],
    limits: PDFParsingLimits
  ) {
    self.resolver = resolver
    self.structure = structure
    self.interactive = interactive
    self.revisions = revisions
    self.limits = limits
  }

  func close() {
    closed = true
    signaturesByRevision.removeAll()
  }

  func signatures(in revision: PDFRevisionIdentifier) async throws -> [PDFSignature] {
    try ensureOpen(revision)
    if let cached = signaturesByRevision[revision] { return cached }
    var discovered = [PDFSignature]()
    var seen = Set<PDFObjectReference>()
    if let form = try await interactive.acroForm(in: revision) {
      for field in try await interactive.formFields(in: revision) where field.signature != nil {
        guard let signature = field.signature else { continue }
        if let reference = signature.dictionaryReference, !seen.insert(reference).inserted { continue }
        discovered.append(try await enrich(signature, kind: signature.kind, in: revision))
      }
      _ = form
    }
    let catalog = try await structure.catalog(in: revision)
    if let permissions = try await optionalDictionary(catalog.rawDictionary["Perms"], in: revision) {
      for (name, object) in permissions.sorted(by: { $0.key.bytes.lexicographicallyPrecedes($1.key.bytes) }) {
        guard case .reference(let reference) = object else {
          throw malformed("A catalog permission signature must be indirect.")
        }
        guard seen.insert(reference).inserted else { continue }
        var signature = try await interactive.signature(from: object, in: revision)
        let kind: PDFSignatureKind = switch name {
        case "DocMDP": .certification
        case "UR", "UR3": .usageRights
        default: .other(name)
        }
        signature = try await enrich(signature, kind: kind, in: revision)
        discovered.append(signature)
      }
    }
    guard discovered.count <= limits.maximumSignatures else {
      throw PDFParsingError.limitExceeded(.init(offset: 0, message: "The signature count exceeds its limit."))
    }
    signaturesByRevision[revision] = discovered
    return discovered
  }

  private func enrich(
    _ signature: PDFSignature,
    kind: PDFSignatureKind,
    in revision: PDFRevisionIdentifier
  ) async throws -> PDFSignature {
    var contents = signature.contents
    var sourceRange: PDFSourceRange?
    if let reference = signature.dictionaryReference {
      let object = try await resolver.resolve(reference, in: revision)
      guard case .file = object.provenance, let objectRange = object.sourceRange else {
        throw malformed("A signature dictionary must be an uncompressed ordinary object.")
      }
      let source = try await resolver.sourceBytes(in: objectRange)
      let token = try PDFSignatureSourceScanner.contentsToken(in: source, absoluteOffset: objectRange.offset)
      contents = token.bytes
      sourceRange = token.range
    }
    let format = containerFormat(signature.subfilter)
    let container: PDFSignatureContainer?
    switch format {
    case .unsupported:
      container = nil
    case .x509RSASHA1:
      container = PDFSignatureContainer(format: format, derRepresentation: contents)
    default:
      do {
        container = try PDFCMSParser(limits: limits).parse(contents, format: format)
      } catch PDFDERError.limitExceeded {
        throw PDFParsingError.limitExceeded(.init(offset: sourceRange?.offset ?? 0, message: "The signature container exceeds its configured limits."))
      } catch {
        throw PDFParsingError.malformed(.init(offset: sourceRange?.offset ?? 0, message: "The signature container is malformed."))
      }
    }
    let signedRevision = signedRevision(for: signature.byteRanges)
    return PDFSignature(
      identifier: signature.identifier,
      kind: kind,
      dictionaryReference: signature.dictionaryReference,
      byteRanges: signature.byteRanges,
      contents: contents,
      filter: signature.filter,
      subfilter: signature.subfilter,
      reason: signature.reason,
      signingTime: signature.signingTime,
      permissions: signature.permissions,
      rawDictionary: signature.rawDictionary,
      definingRevision: signature.definingRevision,
      contentsSourceRange: sourceRange,
      signedRevision: signedRevision,
      container: container,
      signers: container?.signers ?? [],
      transforms: signature.transforms
    )
  }

  private func signedRevision(for ranges: [PDFSourceRange]) -> PDFRevisionIdentifier? {
    let end = ranges.map(\.endOffset).max() ?? 0
    return revisions.first(where: { end <= $0.endOffset })?.identifier
  }

  private func containerFormat(_ subfilter: PDFName?) -> PDFSignatureContainerFormat {
    switch subfilter {
    case "adbe.pkcs7.detached": .pkcs7Detached
    case "adbe.pkcs7.sha1": .pkcs7SHA1
    case "adbe.x509.rsa_sha1": .x509RSASHA1
    case "ETSI.CAdES.detached": .cadesDetached
    case "ETSI.RFC3161": .rfc3161
    default: .unsupported(subfilter)
    }
  }

  private func optionalDictionary(
    _ object: PDFObject?,
    in revision: PDFRevisionIdentifier
  ) async throws -> [PDFName: PDFObject]? {
    guard let object else { return nil }
    let resolved: PDFObject
    if case .reference(let reference) = object {
      let indirect = try await resolver.resolve(reference, in: revision)
      guard case .value(let value) = indirect.value else { throw malformed("A dictionary reference resolved to a stream.") }
      resolved = value
    } else {
      resolved = object
    }
    guard case .dictionary(let dictionary) = resolved else { throw malformed("The value must be a dictionary.") }
    return dictionary
  }

  private func ensureOpen(_ revision: PDFRevisionIdentifier) throws {
    guard !closed else { throw PDFParsingError.documentClosed }
    guard revisions.contains(where: { $0.identifier == revision }) else {
      throw PDFParsingError.malformed(.init(offset: 0, message: "The revision does not belong to this document."))
    }
  }

  private func malformed(_ message: String) -> PDFParsingError {
    .malformed(.init(offset: 0, message: message))
  }
}
