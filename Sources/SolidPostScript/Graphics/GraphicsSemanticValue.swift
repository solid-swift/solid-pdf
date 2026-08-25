import Foundation

/// A bounded format-neutral value attached to semantic marked content.
public indirect enum GraphicsSemanticValue: Sendable, Hashable {
  case null
  case boolean(Bool)
  case integer(Int64)
  case real(Double)
  case name(Data)
  case string(Data)
  case array([GraphicsSemanticValue])
  case dictionary([Data: GraphicsSemanticValue])
  case resource(GraphicsResourceIdentifier)
}
