/// A stable identifier for one repair within a recovered document.
public struct PDFRecoveryRecordIdentifier: Sendable, Hashable {
  package let ordinal: Int

  package init(ordinal: Int) {
    self.ordinal = ordinal
  }
}
