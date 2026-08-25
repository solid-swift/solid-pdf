package struct PDFRecoveryPassDescriptor: Sendable, Hashable {
  package let identifier: String
  package let stage: PDFRecoveryStage
  package let minimumPolicy: PDFRecoveryPolicy
  package let priority: Int
  package let invalidates: Set<PDFRecoveryStage>

  package init(
    identifier: String,
    stage: PDFRecoveryStage,
    minimumPolicy: PDFRecoveryPolicy = .structural,
    priority: Int = 0,
    invalidates: Set<PDFRecoveryStage> = []
  ) {
    self.identifier = identifier
    self.stage = stage
    self.minimumPolicy = minimumPolicy
    self.priority = priority
    self.invalidates = invalidates
  }
}
