/// An indirect PDF object reference.
public struct PDFObjectReference: Sendable, Hashable, Comparable {
  /// The one-based object number.
  public let objectNumber: Int

  init(objectNumber: Int) {
    self.objectNumber = objectNumber
  }

  public static func < (lhs: PDFObjectReference, rhs: PDFObjectReference) -> Bool {
    lhs.objectNumber < rhs.objectNumber
  }
}
