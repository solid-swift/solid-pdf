/// A bounded group of complete explicit sampled-image mask rows.
public struct GraphicsImageMaskRows: Sendable, Hashable {
  /// The zero-based mask row represented by the first opacity sample.
  public let startRow: Int
  /// The number of complete rows represented by `opacities`.
  public let rowCount: Int
  /// Row-major opacity values, where 1 paints and 0 is transparent.
  public let opacities: [Float]

  /// Creates a mask-row transfer.
  public init(startRow: Int, rowCount: Int, opacities: [Float]) {
    self.startRow = startRow
    self.rowCount = rowCount
    self.opacities = opacities
  }
}
