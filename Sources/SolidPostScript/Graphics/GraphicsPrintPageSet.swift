import Foundation

/// A group of sheets delivered together according to the Collate setting.
public struct GraphicsPrintPageSet: Sendable, Hashable {
  /// One-based page-set ordinal.
  public let ordinal: Int
  /// Logical pages participating in this set, in reading order.
  public let pageIndices: [Int]
  /// Physical sheets touched by the set, in delivery order.
  public let sheetIndices: [Int]
  /// Whether the set was collated as a document copy.
  public let isCollated: Bool

  /// Creates a page-set record.
  public init(ordinal: Int, pageIndices: [Int], sheetIndices: [Int], isCollated: Bool) {
    self.ordinal = ordinal
    self.pageIndices = pageIndices
    self.sheetIndices = sheetIndices
    self.isCollated = isCollated
  }
}
