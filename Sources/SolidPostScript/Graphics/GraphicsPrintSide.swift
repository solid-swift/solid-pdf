import Foundation

/// One delivered sheet side referencing immutable logical page data.
public struct GraphicsPrintSide: Sendable, Hashable {
  /// The referenced logical page index.
  public let pageIndex: Int
  /// Physical placement applied to this side.
  public let placement: GraphicsPagePlacement
  /// The delivered colorant for separated output, or `nil` for composite output.
  public let separationColorant: String?
  /// One-based copy ordinal within its page set.
  public let copyOrdinal: Int
  /// One-based page-set ordinal.
  public let pageSetOrdinal: Int
  /// Whether the side represents inserted, non-imaged media.
  public let isInsertedSheet: Bool

  /// Creates a delivered print side.
  public init(
    pageIndex: Int,
    placement: GraphicsPagePlacement,
    separationColorant: String? = nil,
    copyOrdinal: Int,
    pageSetOrdinal: Int,
    isInsertedSheet: Bool = false
  ) {
    self.pageIndex = pageIndex
    self.placement = placement
    self.separationColorant = separationColorant
    self.copyOrdinal = copyOrdinal
    self.pageSetOrdinal = pageSetOrdinal
    self.isInsertedSheet = isInsertedSheet
  }
}
