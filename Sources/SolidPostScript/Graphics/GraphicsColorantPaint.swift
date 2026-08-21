import Foundation

/// A normalized subtractive tint for one device colorant.
public struct GraphicsColorantComponent: Sendable, Hashable {
  public let name: String
  public let tint: Double

  /// Creates a colorant component, clipping its tint to zero through one.
  public init(name: String, tint: Double) {
    self.name = name
    self.tint = min(1, max(0, tint))
  }
}

/// A resolved colorant paint and its diagnostic composite fallback.
public struct GraphicsColorantPaint: Sendable, Hashable {
  public let components: [GraphicsColorantComponent]
  public let addressesAllColorants: Bool
  public let paintsNothing: Bool
  public let preview: GraphicsPaint

  /// Creates a resolved colorant paint.
  public init(
    components: [GraphicsColorantComponent],
    addressesAllColorants: Bool = false,
    paintsNothing: Bool = false,
    preview: GraphicsPaint
  ) {
    self.components = components
    self.addressesAllColorants = addressesAllColorants
    self.paintsNothing = paintsNothing
    self.preview = preview
  }
}

/// Ordered colorant samples for complete sampled-image rows.
public struct GraphicsColorantRows: Sendable, Hashable {
  public let startRow: Int
  public let rowCount: Int
  public let width: Int
  public let colorants: [String]
  public let tints: [Float]

  /// Creates an ordered colorant row batch.
  public init(startRow: Int, rowCount: Int, width: Int, colorants: [String], tints: [Float]) {
    self.startRow = startRow
    self.rowCount = rowCount
    self.width = width
    self.colorants = colorants
    self.tints = tints
  }
}
