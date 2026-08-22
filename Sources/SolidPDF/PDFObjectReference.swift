/// An indirect PDF object reference.
public struct PDFObjectReference: Sendable, Hashable, Comparable {
  /// The one-based object number.
  public let objectNumber: Int
  /// The object generation number.
  public let generationNumber: Int

  package init(objectNumber: Int) {
    self.objectNumber = objectNumber
    generationNumber = 0
  }

  package init(uncheckedObjectNumber objectNumber: Int, generationNumber: Int) {
    self.objectNumber = objectNumber
    self.generationNumber = generationNumber
  }

  /// Creates a validated indirect object reference.
  public init(objectNumber: Int, generationNumber: Int) throws {
    guard objectNumber > 0, generationNumber >= 0, generationNumber <= 65_535 else {
      throw PDFObjectReferenceError.invalidReference
    }
    self.objectNumber = objectNumber
    self.generationNumber = generationNumber
  }

  public static func < (lhs: PDFObjectReference, rhs: PDFObjectReference) -> Bool {
    (lhs.objectNumber, lhs.generationNumber) < (rhs.objectNumber, rhs.generationNumber)
  }
}

/// An error produced while constructing an indirect object reference.
public enum PDFObjectReferenceError: Error, Sendable, Hashable {
  /// The object or generation number is outside the PDF-defined range.
  case invalidReference
}
