/// A typed direct PDF object.
public indirect enum PDFObject: Sendable, Hashable {
  /// The null object.
  case null
  /// A Boolean value.
  case boolean(Bool)
  /// A numeric value.
  case number(PDFNumber)
  /// A name value.
  case name(PDFName)
  /// A string value.
  case string(PDFString)
  /// An array value.
  case array([PDFObject])
  /// A dictionary value.
  case dictionary([PDFName: PDFObject])
  /// An indirect object reference.
  case reference(PDFObjectReference)

  /// Creates an integer object.
  public static func integer(_ value: Int) -> PDFObject {
    .number(.integer(Int64(value)))
  }

  /// Creates a real object.
  public static func real(_ value: Double) -> PDFObject {
    .number(.real(value))
  }
}
