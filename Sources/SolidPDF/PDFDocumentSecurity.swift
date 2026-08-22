/// Authenticated security metadata for an opened PDF document.
public struct PDFDocumentSecurity: Sendable, Hashable {
  /// The validated security-handler configuration.
  public let encryption: PDFEncryptionDescription
  /// The credential class that opened the document.
  public let authentication: PDFAuthenticationKind
  /// The exact signed `/P` value represented as its raw 32-bit pattern.
  public let rawPermissionFlags: UInt32
  /// The permissions effective for the authenticated credential.
  public let effectivePermissions: PDFPermissionSet
  /// The default stream crypt-filter name.
  public let streamFilter: PDFName
  /// The default string crypt-filter name.
  public let stringFilter: PDFName
  /// The default embedded-file crypt-filter name.
  public let embeddedFileFilter: PDFName

  package init(
    encryption: PDFEncryptionDescription,
    authentication: PDFAuthenticationKind,
    rawPermissionFlags: UInt32,
    effectivePermissions: PDFPermissionSet,
    streamFilter: PDFName,
    stringFilter: PDFName,
    embeddedFileFilter: PDFName
  ) {
    self.encryption = encryption
    self.authentication = authentication
    self.rawPermissionFlags = rawPermissionFlags
    self.effectivePermissions = effectivePermissions
    self.streamFilter = streamFilter
    self.stringFilter = stringFilter
    self.embeddedFileFilter = embeddedFileFilter
  }
}
