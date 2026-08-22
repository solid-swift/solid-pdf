/// A signature transform restricting permitted changes after signing.
public enum PDFSignatureTransform: Sendable, Hashable {
  /// A document modification-detection and prevention transform.
  case docMDP(PDFDocMDPTransform)
  /// A form-field modification-detection and prevention transform.
  case fieldMDP(PDFFieldMDPTransform)
  /// An unsupported transform retained by name and raw parameters.
  case unsupported(method: PDFName, parameters: PDFObject?)
}

/// Certification permissions declared by a DocMDP transform.
public struct PDFDocMDPTransform: Sendable, Hashable {
  /// The permission level from 1 through 3.
  public let permissionLevel: Int
  /// The transform parameters retained for inspection.
  public let rawParameters: [PDFName: PDFObject]

  /// Creates a DocMDP transform.
  public init(permissionLevel: Int, rawParameters: [PDFName: PDFObject]) {
    self.permissionLevel = permissionLevel
    self.rawParameters = rawParameters
  }
}

/// The field-selection rule in a FieldMDP transform.
public enum PDFFieldMDPAction: Sendable, Hashable {
  /// Protect every field.
  case all
  /// Protect only the named fields.
  case include
  /// Protect every field except the named fields.
  case exclude
}

/// Form-field permissions declared by a FieldMDP transform.
public struct PDFFieldMDPTransform: Sendable, Hashable {
  /// The field selection mode.
  public let action: PDFFieldMDPAction
  /// Fully qualified field names named by the transform.
  public let fieldNames: [String]
  /// The transform parameters retained for inspection.
  public let rawParameters: [PDFName: PDFObject]

  /// Creates a FieldMDP transform.
  public init(
    action: PDFFieldMDPAction,
    fieldNames: [String],
    rawParameters: [PDFName: PDFObject]
  ) {
    self.action = action
    self.fieldNames = fieldNames
    self.rawParameters = rawParameters
  }
}
