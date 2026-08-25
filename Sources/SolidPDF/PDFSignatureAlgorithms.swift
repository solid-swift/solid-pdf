/// A digest algorithm declared by a signature container.
public enum PDFDigestAlgorithm: Sendable, Hashable {
  /// SHA-1.
  case sha1
  /// SHA-224.
  case sha224
  /// SHA-256.
  case sha256
  /// SHA-384.
  case sha384
  /// SHA-512.
  case sha512
  /// An unsupported or unrecognized object identifier.
  case unsupported(String)
}

/// A public-key signature algorithm declared by a signature container.
public enum PDFSignatureAlgorithm: Sendable, Hashable {
  /// RSA PKCS#1 version 1.5.
  case rsaPKCS1v15
  /// RSA Probabilistic Signature Scheme.
  case rsaPSS
  /// ECDSA over a NIST curve.
  case ecdsa
  /// Ed25519.
  case ed25519
  /// An unsupported or unrecognized object identifier.
  case unsupported(String)
}

/// The external signature container syntax selected by a PDF signature dictionary.
public enum PDFSignatureContainerFormat: Sendable, Hashable {
  /// Detached CMS SignedData.
  case pkcs7Detached
  /// CMS SignedData encapsulating the SHA-1 digest of the document ranges.
  case pkcs7SHA1
  /// A raw RSA SHA-1 signature with certificates supplied by `/Cert`.
  case x509RSASHA1
  /// Detached CAdES SignedData.
  case cadesDetached
  /// An RFC 3161 document timestamp token.
  case rfc3161
  /// An unsupported PDF subfilter.
  case unsupported(PDFName?)
}
