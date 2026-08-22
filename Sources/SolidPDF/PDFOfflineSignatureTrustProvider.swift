import Foundation
@_spi(FixedExpiryValidationTime) import X509

/// An offline RFC 5280 trust provider backed only by caller-supplied certificates.
public struct PDFOfflineSignatureTrustProvider: PDFSignatureTrustProvider {
  private let trustAnchors: [PDFCertificate]
  private let intermediates: [PDFCertificate]
  private let revocationEvidence: [Data]

  /// Creates an offline provider from exact DER trust material.
  public init(
    trustAnchorsDER: [Data],
    intermediatesDER: [Data] = [],
    revocationEvidence: [Data] = []
  ) throws {
    trustAnchors = try trustAnchorsDER.map {
      try PDFCertificateBridge.portable(Certificate(derEncoded: [UInt8]($0)))
    }
    intermediates = try intermediatesDER.map {
      try PDFCertificateBridge.portable(Certificate(derEncoded: [UInt8]($0)))
    }
    self.revocationEvidence = revocationEvidence
  }

  /// Evaluates a signer against the explicit anchors without network access.
  public func evaluate(_ request: PDFSignatureTrustRequest) async throws -> PDFSignatureTrustResult {
    let leaf = try PDFCertificateBridge.parse(request.leaf)
    let anchors = try trustAnchors.map(PDFCertificateBridge.parse)
    let candidates = try (request.intermediates + intermediates).map(PDFCertificateBridge.parse)
    var verifier = Verifier(rootCertificates: CertificateStore(anchors)) {
      RFC5280Policy(fixedExpiryValidationTime: request.validationTime)
    }
    let result = await verifier.validate(leaf: leaf, intermediates: CertificateStore(candidates))
    switch result {
    case .validCertificate(let chain):
      return PDFSignatureTrustResult(
        trust: .trusted,
        chain: try chain.map(PDFCertificateBridge.portable),
        revocation: revocationEvidence.isEmpty && request.revocationEvidence.isEmpty ? .notChecked : .unknown
      )
    case .couldNotValidate:
      return PDFSignatureTrustResult(
        trust: .untrusted,
        revocation: revocationEvidence.isEmpty && request.revocationEvidence.isEmpty ? .notChecked : .unknown
      )
    }
  }
}
