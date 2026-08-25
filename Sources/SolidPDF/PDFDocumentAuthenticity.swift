import Crypto
import CryptoExtras
import Foundation
import X509

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

  func validate(
    _ signature: PDFSignature,
    in revision: PDFRevisionIdentifier,
    options: PDFSignatureValidationOptions
  ) async throws -> PDFSignatureValidationResult {
    try ensureOpen(revision)
    let coverage = try await coverage(of: signature)
    let integrity = try await integrity(of: signature, coverage: coverage)
    let modifications = options.validatesModifications
      ? try await modificationStatus(of: signature, through: revision)
      : .indeterminate(changedObjects: [], reason: "Modification validation was disabled.")
    let timestamp: PDFSignatureTimestampStatus = signature.signers.compactMap(\.signingTime).first.map {
      .signingTime($0)
    } ?? .absent
    guard case .valid = integrity,
      let signer = signature.signers.first,
      let leaf = signer.certificate,
      let provider = options.trustProvider
    else {
      return PDFSignatureValidationResult(
        signature: signature.identifier,
        coverage: coverage,
        integrity: integrity,
        trust: .notEvaluated,
        revocation: .notChecked,
        timestamp: timestamp,
        modifications: modifications
      )
    }
    do {
      let available = signature.container?.certificates.filter { $0 != leaf } ?? []
      let trust = try await provider.evaluate(.init(
        leaf: leaf,
        intermediates: available,
        validationTime: options.validationTime ?? signer.signingTime ?? Date(),
        role: signature.kind == .documentTimestamp ? .timestampAuthority : .signer
      ))
      return PDFSignatureValidationResult(
        signature: signature.identifier,
        coverage: coverage,
        integrity: integrity,
        trust: trust.trust,
        revocation: trust.revocation,
        timestamp: timestamp,
        modifications: modifications,
        certificateChain: trust.chain,
        diagnostics: trust.diagnostics
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      return PDFSignatureValidationResult(
        signature: signature.identifier,
        coverage: coverage,
        integrity: integrity,
        trust: .indeterminate("The trust provider failed."),
        revocation: .notChecked,
        timestamp: timestamp,
        modifications: modifications,
        diagnostics: [.init(offset: 0, message: "The trust provider failed: \(error)")]
      )
    }
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

  private func coverage(of signature: PDFSignature) async throws -> PDFSignatureCoverage {
    let sourceLength = try await resolver.sourceLength()
    var previousEnd: Int64 = 0
    var gaps = [PDFSourceRange]()
    for range in signature.byteRanges {
      guard range.offset >= previousEnd, range.endOffset <= sourceLength else {
        throw malformed("A signature ByteRange is unsorted or outside the source.")
      }
      if range.offset > previousEnd {
        gaps.append(try PDFSourceRange(offset: previousEnd, length: Int(range.offset - previousEnd)))
      }
      previousEnd = range.endOffset
    }
    let signed = signature.signedRevision.flatMap { identifier in
      revisions.first(where: { $0.identifier == identifier })
    }
    if let signed, previousEnd < signed.endOffset {
      gaps.append(try PDFSourceRange(offset: previousEnd, length: Int(signed.endOffset - previousEnd)))
    }
    let unaccounted = gaps.filter { $0 != signature.contentsSourceRange }
    let later = signed.map { signedRevision in
      revisions.filter { $0.endOffset > signedRevision.endOffset }.map(\.identifier)
    } ?? []
    let trailing = max(0, sourceLength - (revisions.last?.endOffset ?? sourceLength))
    return PDFSignatureCoverage(
      coversSignedRevision: signature.byteRanges.first?.offset == 0
        && previousEnd == signed?.endOffset
        && unaccounted.isEmpty
        && signature.contentsSourceRange != nil,
      signedRevision: signature.signedRevision,
      laterRevisions: later,
      unsignedTrailingByteCount: trailing,
      unaccountedGaps: unaccounted
    )
  }

  private func integrity(
    of signature: PDFSignature,
    coverage: PDFSignatureCoverage
  ) async throws -> PDFSignatureIntegrityStatus {
    guard coverage.coversSignedRevision else { return .invalid(reason: "The signed byte ranges do not exactly cover the signed revision.") }
    guard let container = signature.container, let signer = signature.signers.first else {
      return .unsupported(algorithm: "The signature container has no supported signer.")
    }
    let contentDigest: Data
    do {
      let documentDigest = try await resolver.digest(of: signature.byteRanges, using: signer.digestAlgorithm)
      if container.format == .pkcs7SHA1 {
        let expectedContent = try await resolver.digest(of: signature.byteRanges, using: .sha1)
        guard let content = container.encapsulatedContent, content == expectedContent else {
          return .invalid(reason: "The encapsulated SHA-1 digest does not match the signed ranges.")
        }
        contentDigest = try digest(content, using: signer.digestAlgorithm)
      } else {
        contentDigest = documentDigest
      }
    } catch let error as PDFParsingError {
      if case .unsupported = error { return .unsupported(algorithm: String(describing: signer.digestAlgorithm)) }
      throw error
    }
    if let expected = signer.messageDigest, expected != contentDigest {
      return .invalid(reason: "The authenticated message-digest attribute does not match the signed ranges.")
    }
    if let signedType = signer.signedContentTypeIdentifier, signedType != container.contentTypeIdentifier {
      return .invalid(reason: "The authenticated content type does not match the container content type.")
    }
    guard let certificate = signer.certificate else { return .invalid(reason: "The signer certificate is unavailable.") }
    let signedBytes: Data
    if let attributes = signer.signedAttributesDER {
      signedBytes = attributes
    } else {
      signedBytes = try await resolver.materialize(
        ranges: signature.byteRanges,
        maximumBytes: limits.maximumAuthenticityScratchBytes
      )
    }
    let parsed = try PDFCertificateBridge.parse(certificate)
    let isValid: Bool
    if signer.signatureAlgorithm == .rsaPSS {
      isValid = try validateRSAPSS(signer, certificate: parsed, signedBytes: signedBytes)
    } else if let algorithm = x509SignatureAlgorithm(signer) {
      isValid = parsed.publicKey.isValidSignature(signer.signature, for: signedBytes, signatureAlgorithm: algorithm)
    } else {
      return .unsupported(algorithm: String(describing: signer.signatureAlgorithm))
    }
    return isValid ? .valid : .invalid(reason: "The public-key signature is invalid.")
  }

  private func modificationStatus(
    of signature: PDFSignature,
    through revision: PDFRevisionIdentifier
  ) async throws -> PDFSignatureModificationStatus {
    guard let signedRevision = signature.signedRevision else {
      return .indeterminate(changedObjects: [], reason: "The signed revision is unknown.")
    }
    let changes = try await resolver.changedObjectReferences(after: signedRevision, through: revision)
    guard !changes.isEmpty else { return .unchanged }
    let permission = signature.transforms.compactMap { transform -> Int? in
      if case .docMDP(let value) = transform { value.permissionLevel } else { nil }
    }.first
    let fieldRules = signature.transforms.compactMap { transform -> PDFFieldMDPTransform? in
      if case .fieldMDP(let value) = transform { value } else { nil }
    }
    guard permission != nil || !fieldRules.isEmpty else { return .permitted(changedObjects: changes) }
    var prohibited = false
    for reference in changes {
      let category = try await changeCategory(reference, in: revision)
      let allowedByDocument: Bool
      if let permission {
        allowedByDocument = switch (permission, category) {
        case (_, .maintenance), (2...3, .formOrSignature), (3, .annotation): true
        default: false
        }
      } else {
        allowedByDocument = true
      }
      if !allowedByDocument { prohibited = true }
      if category == .formOrSignature {
        let fieldName = try await changedFieldName(reference, in: revision)
        for rule in fieldRules {
          let listed = fieldName.map(rule.fieldNames.contains) ?? false
          let permittedByField = switch rule.action {
          case .all: false
          case .include: !listed
          case .exclude: listed
          }
          if !permittedByField { prohibited = true }
        }
      }
    }
    return prohibited ? .prohibited(changedObjects: changes) : .permitted(changedObjects: changes)
  }

  private enum ChangeCategory: Equatable { case maintenance, formOrSignature, annotation, other }

  private func changeCategory(
    _ reference: PDFObjectReference,
    in revision: PDFRevisionIdentifier
  ) async throws -> ChangeCategory {
    let object = try await resolver.resolve(reference, in: revision)
    let dictionary: [PDFName: PDFObject]
    switch object.value {
    case .value(.dictionary(let value)): dictionary = value
    case .stream(let stream): dictionary = stream.dictionary
    default: return .other
    }
    if dictionary.pdfName(named: "Type") == "DSS" || dictionary["VRI"] != nil { return .maintenance }
    if dictionary.pdfName(named: "Type") == "Sig" || dictionary["FT"] != nil { return .formOrSignature }
    if dictionary.pdfName(named: "Type") == "Annot" || dictionary["Subtype"] != nil { return .annotation }
    return .other
  }

  private func changedFieldName(
    _ reference: PDFObjectReference,
    in revision: PDFRevisionIdentifier
  ) async throws -> String? {
    let object = try await resolver.resolve(reference, in: revision)
    guard case .value(.dictionary(let dictionary)) = object.value,
      case .string(let name)? = dictionary["T"]
    else { return nil }
    return try PDFTextStringDecoder.decode(name, allowsUTF8: true)
  }

  private func x509SignatureAlgorithm(_ signer: PDFSignatureSigner) -> Certificate.SignatureAlgorithm? {
    switch (signer.signatureAlgorithm, signer.digestAlgorithm) {
    case (.rsaPKCS1v15, .sha1): .sha1WithRSAEncryption
    case (.rsaPKCS1v15, .sha256): .sha256WithRSAEncryption
    case (.rsaPKCS1v15, .sha384): .sha384WithRSAEncryption
    case (.rsaPKCS1v15, .sha512): .sha512WithRSAEncryption
    case (.ecdsa, .sha256): .ecdsaWithSHA256
    case (.ecdsa, .sha384): .ecdsaWithSHA384
    case (.ecdsa, .sha512): .ecdsaWithSHA512
    case (.ed25519, _): .ed25519
    default: nil
    }
  }

  private func digest(_ data: Data, using algorithm: PDFDigestAlgorithm) throws -> Data {
    switch algorithm {
    case .sha1: Data(Insecure.SHA1.hash(data: data))
    case .sha256: Data(SHA256.hash(data: data))
    case .sha384: Data(SHA384.hash(data: data))
    case .sha512: Data(SHA512.hash(data: data))
    default:
      throw PDFParsingError.unsupported(
        .signatureAlgorithm(String(describing: algorithm)),
        .init(offset: 0, message: "The signature digest algorithm is unsupported.")
      )
    }
  }

  private func validateRSAPSS(
    _ signer: PDFSignatureSigner,
    certificate: Certificate,
    signedBytes: Data
  ) throws -> Bool {
    let key = try _RSA.Signing.PublicKey(derRepresentation: certificate.publicKey.subjectPublicKeyInfoBytes)
    let signature = _RSA.Signing.RSASignature(rawRepresentation: signer.signature)
    switch signer.digestAlgorithm {
    case .sha1:
      return key.isValidSignature(signature, for: Insecure.SHA1.hash(data: signedBytes), padding: .PSS)
    case .sha256:
      return key.isValidSignature(signature, for: SHA256.hash(data: signedBytes), padding: .PSS)
    case .sha384:
      return key.isValidSignature(signature, for: SHA384.hash(data: signedBytes), padding: .PSS)
    case .sha512:
      return key.isValidSignature(signature, for: SHA512.hash(data: signedBytes), padding: .PSS)
    default:
      return false
    }
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
