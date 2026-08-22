/// An immutable, all-or-nothing collection of semantic AcroForm updates.
public struct PDFFormUpdateTransaction: Sendable, Hashable {
  /// Field changes applied together in their supplied order.
  public let updates: [PDFFormFieldUpdate]

  /// Creates a form update transaction.
  public init(updates: [PDFFormFieldUpdate]) {
    self.updates = updates
  }
}
