/// The degree of malformed-PDF recovery permitted while opening a document.
public enum PDFRecoveryPolicy: Sendable, Hashable {
  /// Accept only repairs with one uniquely supported interpretation.
  case structural
  /// Permit bounded deterministic selection between plausible interpretations.
  case compatible
}
