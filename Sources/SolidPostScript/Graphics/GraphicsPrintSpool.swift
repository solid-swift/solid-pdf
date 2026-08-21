import Foundation

/// A portable semantic plan for physical print delivery.
public struct GraphicsPrintSpool: Sendable, Hashable {
  /// Logical pages, each retaining captured effects exactly once.
  public let pages: [GraphicsPrintPage]
  /// Sheets in physical delivery order.
  public let sheets: [GraphicsPrintSheet]
  /// Collated or per-page output sets.
  public let pageSets: [GraphicsPrintPageSet]
  /// Ordered roll-media and finishing actions.
  public let actions: [GraphicsPrintDeliveryAction]
  /// Sheet indexes in the order physically delivered.
  public let physicalDeliveryOrder: [Int]
  /// Sheet indexes in resulting normal reading order.
  public let stackReadOrder: [Int]

  /// Creates a completed print spool.
  public init(
    pages: [GraphicsPrintPage],
    sheets: [GraphicsPrintSheet],
    pageSets: [GraphicsPrintPageSet],
    actions: [GraphicsPrintDeliveryAction],
    physicalDeliveryOrder: [Int],
    stackReadOrder: [Int]
  ) {
    self.pages = pages
    self.sheets = sheets
    self.pageSets = pageSets
    self.actions = actions
    self.physicalDeliveryOrder = physicalDeliveryOrder
    self.stackReadOrder = stackReadOrder
  }
}
