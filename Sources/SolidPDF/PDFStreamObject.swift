/// A lazily backed PDF stream object.
public struct PDFStreamObject: Sendable, Hashable {
  /// The stream dictionary.
  public let dictionary: [PDFName: PDFObject]
  /// The exact encoded stream-data range in the original source.
  public let encodedRange: PDFSourceRange

  /// Creates a lazily backed stream object.
  public init(dictionary: [PDFName: PDFObject], encodedRange: PDFSourceRange) {
    self.dictionary = dictionary
    self.encodedRange = encodedRange
  }
}
