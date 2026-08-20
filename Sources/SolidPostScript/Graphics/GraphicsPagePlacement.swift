import Foundation

/// Physical placement applied to a page image independently of its graphics state.
public struct GraphicsPagePlacement: Sendable, Hashable {
  /// The orientation relative to the medium.
  public let orientation: GraphicsPageOrientation
  /// The active physical sheet side.
  public let side: GraphicsSheetSide
  /// The requested leading edge.
  public let leadingEdge: GraphicsLeadingEdge?
  /// The side-aware image shift in default-user-space points.
  public let imageShift: GraphicsPoint
  /// The page offset incorporated into the default matrix.
  public let pageOffset: GraphicsPoint
  /// Media-recovery scaling and centering applied before ordinary placement.
  public let mediaAdjustment: GraphicsMatrix
  /// The device-specific mechanical margin adjustment.
  public let margins: GraphicsPoint
  /// Whether device output is mirrored.
  public let mirrorsPage: Bool
  /// Whether the complete delivered page is color-inverted.
  public let producesNegative: Bool
  /// Whether the page device is duplexing.
  public let isDuplex: Bool
  /// Whether verso orientation tumbles around the short binding edge.
  public let tumbles: Bool

  /// Creates a page-placement value.
  public init(
    orientation: GraphicsPageOrientation = .defaultOrientation,
    side: GraphicsSheetSide = .recto,
    leadingEdge: GraphicsLeadingEdge? = nil,
    imageShift: GraphicsPoint = .init(x: 0, y: 0),
    pageOffset: GraphicsPoint = .init(x: 0, y: 0),
    mediaAdjustment: GraphicsMatrix = .identity,
    margins: GraphicsPoint = .init(x: 0, y: 0),
    mirrorsPage: Bool = false,
    producesNegative: Bool = false,
    isDuplex: Bool = false,
    tumbles: Bool = false
  ) {
    self.orientation = orientation
    self.side = side
    self.leadingEdge = leadingEdge
    self.imageShift = imageShift
    self.pageOffset = pageOffset
    self.mediaAdjustment = mediaAdjustment
    self.margins = margins
    self.mirrorsPage = mirrorsPage
    self.producesNegative = producesNegative
    self.isDuplex = isDuplex
    self.tumbles = tumbles
  }

  /// Default simplex placement.
  public static let simplex = Self()
}
