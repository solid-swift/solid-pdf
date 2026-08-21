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

extension GraphicsPagePlacement {
  func replacing(side: GraphicsSheetSide) -> Self {
    Self(
      orientation: orientation,
      side: side,
      leadingEdge: leadingEdge,
      imageShift: imageShift,
      pageOffset: pageOffset,
      mediaAdjustment: mediaAdjustment,
      margins: margins,
      mirrorsPage: mirrorsPage,
      producesNegative: producesNegative,
      isDuplex: isDuplex,
      tumbles: tumbles
    )
  }

  func transform(for mediaSize: GraphicsSize) -> GraphicsMatrix {
    let oriented: GraphicsMatrix = switch orientation {
    case .defaultOrientation:
      .identity
    case .counterclockwise90:
      GraphicsMatrix(a: 0, b: 1, c: -1, d: 0, tx: mediaSize.height, ty: 0)
    case .rotated180:
      GraphicsMatrix(a: -1, b: 0, c: 0, d: -1, tx: mediaSize.width, ty: mediaSize.height)
    case .counterclockwise270:
      GraphicsMatrix(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: mediaSize.width)
    }
    let tumble = side == .verso && tumbles
      ? GraphicsMatrix(a: -1, b: 0, c: 0, d: -1, tx: mediaSize.width, ty: mediaSize.height)
      : .identity
    let sideSign = side == .recto ? 1.0 : -1.0
    let offset = GraphicsMatrix(
      a: 1,
      b: 0,
      c: 0,
      d: 1,
      tx: pageOffset.x + imageShift.x * sideSign,
      ty: pageOffset.y + imageShift.y * sideSign
    )
    return mediaAdjustment.concatenated(with: oriented)
      .concatenated(with: tumble)
      .concatenated(with: offset)
  }
}
