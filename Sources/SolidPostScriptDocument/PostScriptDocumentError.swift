/// A document-container or rendering failure.
public enum PostScriptDocumentError: Swift.Error, Sendable, Equatable {
  case inputTooLarge
  case lineTooLong(offset: Int)
  case nestingLimit(offset: Int)
  case malformedDSC(offset: Int, message: String)
  case truncatedData(offset: Int)
  case invalidBoundingBox
  case missingEPSHeader
  case missingEPSBoundingBox
  case unsupportedDOSPreview
  case invalidPageSelection
  case noPages
  case timeout
}
