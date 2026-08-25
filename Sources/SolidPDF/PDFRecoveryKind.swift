/// The structural area affected by a recovery record.
public enum PDFRecoveryKind: Sendable, Hashable {
  case header
  case endOfFile
  case startCrossReference
  case crossReference
  case revisionChain
  case indirectObject
  case streamBoundary
  case objectStream
  case trailer
  case catalog
  case pageTree
  case lexicalSeparator
}
