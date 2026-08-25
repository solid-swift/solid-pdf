/// The authority supporting one recovered PDF fact.
public enum PDFRecoveryClassification: Sendable, Hashable {
  /// Original source bytes establish the fact without repair.
  case byteExact
  /// PDF grammar and source evidence establish one unique repair.
  case structuralRepair
  /// Compatibility policy selected one plausible interpretation.
  case semanticInference
}
