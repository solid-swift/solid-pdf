package enum PDFRecoveryStage: Int, Sendable, Hashable, CaseIterable {
  case sourceFraming
  case crossReferenceDiscovery
  case objectBoundaries
  case streamBoundaries
  case documentStructure
  case finalValidation
}
